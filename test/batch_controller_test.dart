import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

class BatchIndexRandom implements Random {
  int index = 0;
  final bounds = <int>[];

  @override
  int nextInt(int max) {
    bounds.add(max);
    return index % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late BatchIndexRandom random;
  late DateTime now;
  ConfirmationFault? fault;

  Future<void> createController() async {
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: random,
    );
    await controller.initialize();
  }

  void cooking(int count) {
    expect(controller.changeScenario(MealScenario.cook), isTrue);
    expect(controller.changeCookingCount(count), isTrue);
  }

  FoodOption drawOne() {
    expect(controller.canDraw, isTrue);
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    return controller.result!;
  }

  List<String> ids(Iterable<FoodOption> options) =>
      options.map((option) => option.id).toList();

  Future<Database> inspect() => databaseFactoryFfi.openDatabase(
    '${directory.path}/meal.sqlite',
    options: OpenDatabaseOptions(singleInstance: false),
  );

  Future<void> expectStoredCounts(int records, int items) async {
    final database = await inspect();
    try {
      expect(await database.query('history_records'), hasLength(records));
      expect(await database.query('history_items'), hasLength(items));
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await database.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('batch-controller-');
    now = DateTime(2026, 10, 8, 12);
    random = BatchIndexRandom();
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    await createController();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'count is cooking-only, bounded and retained only within the session',
    () async {
      expect(controller.cookingCount, 1);
      expect(controller.requestedCount, 1);
      expect(controller.changeCookingCount(3), isFalse);
      cooking(10);
      for (final invalid in [-1, 0, 11]) {
        expect(controller.changeCookingCount(invalid), isFalse);
        expect(controller.cookingCount, 10);
      }
      for (final scenario in [MealScenario.eat, MealScenario.restaurant]) {
        expect(controller.changeScenario(scenario), isTrue);
        expect(controller.requestedCount, 1);
        expect(controller.cookingCount, 10);
        expect(controller.changeCookingCount(2), isFalse);
        drawOne();
        expect(controller.canDraw, isFalse);
        expect(controller.startDraw(), isFalse);
        controller.abandon();
      }
      expect(controller.changeScenario(MealScenario.cook), isTrue);
      expect(controller.requestedCount, 10);
      drawOne();
      expect(controller.abandon(), isTrue);
      expect(controller.cookingCount, 10);
      controller.dispose();
      await createController();
      expect(controller.scenario, MealScenario.eat);
      expect(controller.cookingCount, 1);
      expect(controller.results, isEmpty);
      expect(controller.isModeLocked, isFalse);
    },
  );

  test(
    'one press reveals one unique ordered slot and keeps the spin index valid',
    () async {
      cooking(3);
      final initial = controller.candidates;
      final originalCount = initial.length;
      final expected = [initial.last.id, initial.first.id, initial[1].id];
      final slots = <List<FoodOption>>[];
      for (var slot = 0; slot < 3; slot++) {
        slots.add(controller.results);
        random.index = slot == 0 ? originalCount - 1 : 0;
        final previous = controller.result;
        expect(controller.startDraw(), isTrue);
        final pool = controller.candidates;
        final selected = pool[controller.selectedIndex!];
        expect(controller.result, same(previous));
        expect(controller.results, hasLength(slot));
        expect(controller.isModeLocked, isTrue);
        expect(controller.canDraw, isFalse);
        expect(controller.startDraw(), isFalse);
        expect(await controller.confirm(), isFalse);
        for (final drawn in expected.take(slot)) {
          expect(ids(pool), isNot(contains(drawn)));
        }
        expect(random.bounds.last, originalCount - slot);
        expect(controller.candidates, same(pool));
        controller.finishDraw();
        expect(controller.result, same(selected));
        expect(
          controller.candidates[controller.selectedIndex!],
          same(selected),
        );
        expect(ids(controller.results), expected.take(slot + 1).toList());
        expect(
          controller.results.map((option) => option.id).toSet(),
          hasLength(slot + 1),
        );
        expect(controller.availableCount, originalCount - slot - 1);
        controller.finishDraw();
        expect(controller.results, hasLength(slot + 1));
        expect(slots.last, hasLength(slot));
        expect(() => controller.results.clear(), throwsUnsupportedError);
      }
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      expect(controller.isModeLocked, isTrue);
      expect(controller.sessionExclusions, isEmpty);
      await expectStoredCounts(0, 0);
      expect(
        controller.options
            .where((option) => expected.contains(option.id))
            .every((option) => option.isActive),
        isTrue,
      );
      controller.abandon();
      expect(ids(controller.candidates), ids(initial));
    },
  );

  test(
    'early confirmation stores actual dishes once and resets progress only',
    () async {
      cooking(5);
      final excluded = controller.candidates.last.id;
      expect(controller.excludeForSession(excluded), isTrue);
      final chosen = [drawOne(), drawOne()];
      final confirmedAt = now;
      expect(await controller.confirm(), isTrue);
      final entry = controller.history.single;
      expect(ids(entry.options), ids(chosen));
      expect(entry.confirmedAt, confirmedAt.toUtc());
      expect(entry.period, MealPeriod.lunch);
      expect(controller.results, isEmpty);
      expect(controller.result, isNull);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.cookingCount, 5);
      expect(controller.scenario, MealScenario.cook);
      expect(controller.sessionExclusions, {excluded});
      expect(controller.canDraw, isTrue);
      expect(await controller.confirm(), isFalse);
      await expectStoredCounts(1, 2);
      controller.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/meal.sqlite',
      );
      await createController();
      expect(ids(controller.history.single.options), ids(chosen));
      expect(controller.cookingCount, 1);
    },
  );

  test(
    'shortage refuses initial draw until explicit available-count recovery',
    () async {
      cooking(10);
      controller.changePeriod(MealPeriod.breakfast);
      final eligible = controller.candidates;
      expect(eligible, hasLength(6));
      expect(controller.availableCount, 6);
      expect(controller.hasCandidateShortage, isTrue);
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      expect(controller.error, contains('6'));
      expect(controller.results, isEmpty);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.cookingCount, 10);
      expect(controller.changeCookingCount(controller.availableCount), isTrue);
      expect(controller.error, isNull);
      expect(controller.hasCandidateShortage, isFalse);
      for (var index = 0; index < eligible.length; index++) {
        drawOne();
      }
      expect(ids(controller.results), ids(eligible));
      expect(controller.availableCount, 0);
      expect(controller.hasCandidateShortage, isFalse);
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      await expectStoredCounts(0, 0);
    },
  );

  test(
    'empty shortage never permits zero count or inserts ineligible options',
    () {
      cooking(3);
      controller.changePeriod(MealPeriod.breakfast);
      for (final option in controller.candidates) {
        controller.excludeForSession(option.id);
      }
      expect(controller.availableCount, 0);
      expect(controller.hasCandidateShortage, isFalse);
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      expect(controller.error, contains('没有符合条件'));
      expect(controller.changeCookingCount(0), isFalse);
      expect(controller.hasRound, isFalse);
      expect(controller.restoreSessionExclusions(), isTrue);
      expect(controller.canDraw, isTrue);
      expect(controller.requestedCount, 3);
    },
  );

  test(
    'union filtering, yesterday, activation and session exclusions compose',
    () async {
      cooking(3);
      final tomorrowIds = ids(controller.candidates.take(2));
      for (var index = 0; index < 2; index++) {
        drawOne();
      }
      expect(await controller.confirm(), isTrue);
      now = now.add(const Duration(days: 1));
      expect(
        await controller.updatePreferences(
          const MealPreferences(excludeYesterday: true),
        ),
        isTrue,
      );
      final categoryIds = controller
          .categoriesFor(MealScenario.cook)
          .where((category) => {'家常菜', '快手菜'}.contains(category.name))
          .map((category) => category.id)
          .toSet();
      expect(controller.changeCategoryFilters(categoryIds), isTrue);
      final deactivated = controller.candidates.first.id;
      expect(
        (await controller.setOptionActive(deactivated, false)).changed,
        isTrue,
      );
      final excluded = controller.candidates.first.id;
      expect(controller.excludeForSession(excluded), isTrue);
      final eligible = controller.options
          .where(
            (option) =>
                option.scenario == 'cook' &&
                option.isActive &&
                !option.isDeleted &&
                option.periods.contains(MealPeriod.lunch) &&
                option.categories.any({'家常菜', '快手菜'}.contains) &&
                !tomorrowIds.contains(option.id) &&
                option.id != excluded,
          )
          .toList();
      expect(ids(controller.candidates), ids(eligible));
      expect(
        controller.candidates.map((option) => option.id).toSet(),
        hasLength(eligible.length),
      );
      drawOne();
      drawOne();
      drawOne();
      expect(ids(controller.results), ids(eligible.take(3)));
      expect(ids(controller.results), isNot(contains(deactivated)));
      expect(ids(controller.results), isNot(contains(excluded)));
      for (final id in tomorrowIds) {
        expect(ids(controller.results), isNot(contains(id)));
      }
    },
  );

  test(
    'the entire batch uses its initial calendar-day eligibility after midnight',
    () async {
      cooking(3);
      now = DateTime(2026, 10, 7, 12);
      final yesterday = [drawOne(), drawOne()];
      expect(await controller.confirm(), isTrue);
      now = DateTime(2026, 10, 8, 23, 59);
      expect(
        await controller.updatePreferences(
          const MealPreferences(excludeYesterday: true),
        ),
        isTrue,
      );
      final scope = ids(controller.candidates);
      expect(controller.startDraw(), isTrue);
      final pool = controller.candidates;
      final selectedIndex = controller.selectedIndex;
      now = DateTime(2026, 10, 9, 0, 1);
      expect(controller.candidates, same(pool));
      expect(controller.selectedIndex, selectedIndex);
      controller.finishDraw();
      final first = controller.result!.id;
      expect(controller.startDraw(), isTrue);
      expect(
        ids(controller.candidates),
        scope.where((id) => id != first).toList(),
      );
      for (final option in yesterday) {
        expect(ids(controller.candidates), isNot(contains(option.id)));
      }
      controller.finishDraw();
      expect(controller.period, MealPeriod.lunch);
      expect(controller.abandon(), isTrue);
      expect(ids(controller.candidates), containsAll(ids(yesterday)));
      expect(controller.cookingCount, 3);
    },
  );

  test(
    'unchanged conditions preserve slots; count change explicitly clears a live spin',
    () async {
      cooking(3);
      final excluded = controller.candidates.last.id;
      controller.excludeForSession(excluded);
      drawOne();
      expect(controller.startDraw(), isTrue);
      final results = controller.results;
      final pool = controller.candidates;
      final index = controller.selectedIndex;
      expect(controller.changeCookingCount(3), isTrue);
      expect(controller.changePeriod(controller.period), isTrue);
      expect(controller.changeScenario(controller.scenario), isTrue);
      expect(
        controller.changeCategoryFilters(controller.selectedCategoryIds),
        isTrue,
      );
      await controller.applyDataChange(changed: false);
      expect(controller.results, same(results));
      expect(controller.candidates, same(pool));
      expect(controller.selectedIndex, index);
      expect(controller.isDrawing, isTrue);
      expect(controller.changeCookingCount(0), isFalse);
      expect(controller.results, same(results));
      expect(
        await controller.updatePreferences(
          const MealPreferences(mode: DrawMode.cards),
        ),
        isFalse,
      );
      expect(
        controller.excludeForSession(controller.candidates.first.id),
        isFalse,
      );
      expect(controller.restoreSessionExclusions(), isFalse);
      expect(controller.changeCookingCount(2), isTrue);
      expect(controller.results, isEmpty);
      expect(controller.selectedIndex, isNull);
      expect(controller.hasRound, isFalse);
      expect(controller.isDrawing, isFalse);
      expect(controller.isModeLocked, isFalse);
      controller.finishDraw();
      expect(controller.results, isEmpty);
      expect(controller.requestedCount, 2);
      expect(controller.sessionExclusions, {excluded});
    },
  );

  test(
    'period, scenario, filters and abandonment reset all partial batch state',
    () async {
      cooking(4);
      final excluded = controller.candidates.last.id;
      controller.excludeForSession(excluded);
      final home = controller
          .categoriesFor(MealScenario.cook)
          .firstWhere((category) => category.name == '家常菜');
      final resets = <void Function()>[
        () {
          controller.changePeriod(MealPeriod.dinner);
        },
        () {
          controller.changeCategoryFilters({home.id});
        },
        () {
          controller.changeScenario(MealScenario.restaurant);
        },
        () {
          controller.abandon();
        },
      ];
      for (final reset in resets) {
        drawOne();
        reset();
        expect(controller.results, isEmpty);
        expect(controller.result, isNull);
        expect(controller.selectedIndex, isNull);
        expect(controller.hasRound, isFalse);
        expect(controller.isModeLocked, isFalse);
        expect(controller.cookingCount, 4);
        expect(controller.sessionExclusions, {excluded});
      }
      expect(controller.history, isEmpty);
      await expectStoredCounts(0, 0);
    },
  );

  test(
    'no-op library edits preserve a batch; a durable cross-scenario edit resets it',
    () async {
      cooking(3);
      drawOne();
      drawOne();
      final results = controller.results;
      final pool = controller.candidates;
      final restaurant = controller.options.firstWhere(
        (option) => option.scenario == 'restaurant',
      );
      final unchanged = await controller.saveOption(
        id: restaurant.id,
        name: restaurant.name,
        scenario: restaurant.scenario,
        periods: restaurant.periods,
        category: restaurant.category,
        address: restaurant.address,
        notes: restaurant.notes,
      );
      expect(unchanged.status, OptionMutationStatus.unchanged);
      expect(controller.results, same(results));
      expect(controller.candidates, same(pool));
      expect(controller.restartNotice, isNull);
      final changed = await controller.saveOption(
        id: restaurant.id,
        name: restaurant.name,
        scenario: restaurant.scenario,
        periods: restaurant.periods,
        category: restaurant.category,
        address: '测试路 7 号',
        notes: restaurant.notes,
      );
      expect(changed.changed, isTrue);
      expect(controller.results, isEmpty);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.cookingCount, 3);
      expect(controller.restartNotice, isNotNull);
    },
  );

  test(
    'partial multi-item write failure freezes early payload for a later retry',
    () async {
      cooking(4);
      final selected = [drawOne(), drawOne()];
      final database = await inspect();
      try {
        await database.execute('''
        CREATE TRIGGER fail_second_dish BEFORE INSERT ON history_items
        WHEN NEW.position = 1
        BEGIN
          SELECT RAISE(ABORT, 'Injected second dish failure');
        END
      ''');
        final confirmedAt = now;
        final snapshot = controller.results;
        expect(await controller.confirm(), isFalse);
        expect(controller.results, same(snapshot));
        expect(controller.error, isNotNull);
        expect(controller.isModeLocked, isTrue);
        expect(controller.canDraw, isFalse);
        expect(controller.startDraw(), isFalse);
        await expectStoredCounts(0, 0);
        await database.execute('DROP TRIGGER fail_second_dish');
        now = now.add(const Duration(days: 1));
        expect(await controller.confirm(), isTrue);
        expect(ids(controller.history.single.options), ids(selected));
        expect(controller.history.single.confirmedAt, confirmedAt.toUtc());
        expect(controller.history.single.period, MealPeriod.lunch);
        expect(controller.results, isEmpty);
        expect(controller.error, isNull);
        await expectStoredCounts(1, 2);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'lost acknowledgement cannot append a dish and retries the same complete meal',
    () async {
      cooking(5);
      var acknowledgementCalls = 0;
      fault = (phase) {
        if (phase == ConfirmationPhase.beforeAcknowledgement) {
          acknowledgementCalls++;
          throw StateError('Injected lost batch acknowledgement');
        }
      };
      final selected = [drawOne(), drawOne(), drawOne()];
      final confirmedAt = now;
      expect(await controller.confirm(), isFalse);
      final committed = (await repository.history()).single;
      expect(ids(committed.options), ids(selected));
      expect(controller.history.single.operationId, committed.operationId);
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      expect(ids(controller.results), ids(selected));
      await expectStoredCounts(1, 3);
      now = now.add(const Duration(days: 1));
      expect(await controller.confirm(), isTrue);
      expect(acknowledgementCalls, 1);
      expect(controller.history.single.operationId, committed.operationId);
      expect(controller.history.single.confirmedAt, confirmedAt.toUtc());
      expect(ids(controller.history.single.options), ids(selected));
      expect(controller.hasRound, isFalse);
      await expectStoredCounts(1, 3);
    },
  );

  test(
    'library writes reserve the boundary and wait for complete batch confirmation',
    () async {
      cooking(3);
      final selected = [drawOne(), drawOne()];
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      final confirmation = controller.confirm();
      await entered.future;
      final mutation = controller.saveCategory(name: '稍后吃');
      expect(controller.isBusy, isTrue);
      expect(controller.canDraw, isFalse);
      expect(controller.startDraw(), isFalse);
      expect(await controller.confirm(), isFalse);
      expect(controller.changeCookingCount(2), isFalse);
      expect(controller.changePeriod(MealPeriod.dinner), isFalse);
      expect(controller.changeScenario(MealScenario.eat), isFalse);
      expect(controller.abandon(), isFalse);
      expect(ids(controller.results), ids(selected));
      release.complete();
      expect(await confirmation, isTrue);
      expect((await mutation).changed, isTrue);
      expect(controller.isBusy, isFalse);
      expect(controller.hasRound, isFalse);
      expect(ids(controller.history.single.options), ids(selected));
      expect(controller.cookingCount, 3);
      await expectStoredCounts(1, 2);
    },
  );
}
