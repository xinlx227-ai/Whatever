import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

class ReplacementIndexRandom implements Random {
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
  late ReplacementIndexRandom random;
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

  List<String> ids(Iterable<FoodOption> options) =>
      options.map((option) => option.id).toList();

  void cooking(int count) {
    expect(controller.changeScenario(MealScenario.cook), isTrue);
    expect(controller.changeCookingCount(count), isTrue);
  }

  FoodOption drawOne() {
    expect(controller.canDraw, isTrue);
    expect(controller.startDraw(), isTrue);
    final pool = controller.candidates;
    final chosen = pool[controller.selectedIndex!];
    expect(random.bounds.last, pool.length);
    controller.finishDraw();
    expect(controller.result, same(chosen));
    expect(controller.candidates, same(pool));
    expect(controller.candidates[controller.selectedIndex!], same(chosen));
    return chosen;
  }

  void keepCandidates(int count) {
    for (final option in controller.candidates.skip(count).toList()) {
      expect(controller.excludeForSession(option.id), isTrue);
    }
  }

  Future<void> expectStoredMeal(List<String> expected) async {
    final database = await databaseFactoryFfi.openDatabase(
      '${directory.path}/meal.sqlite',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      expect(await database.query('history_records'), hasLength(1));
      final items = await database.query('history_items', orderBy: 'position');
      expect(items.map((item) => item['option_id']).toList(), expected);
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await database.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'replacement-controller-',
    );
    now = DateTime(2026, 10, 8, 12);
    random = ReplacementIndexRandom();
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

  for (final count in [2, 3]) {
    for (final choice in ReplacementChoice.values) {
      test(
        '$choice removes then appends in a ${count == 2 ? 'full' : 'partial'} batch',
        () async {
          cooking(count);
          final scope = ids(controller.candidates).toSet();
          final original = [drawOne(), drawOne()];
          final snapshot = controller.results;
          expect(controller.beginReplacement(0, choice), isTrue);
          final pool = controller.candidates;
          final expectedPool = scope.difference({original[1].id});
          if (choice == ReplacementChoice.exclude) {
            expectedPool.remove(original[0].id);
          }
          expect(ids(pool).toSet(), expectedPool);
          expect(ids(pool).toSet(), hasLength(pool.length));
          expect(controller.hasPendingReplacement, isTrue);
          expect(ids(controller.results), [original[1].id]);
          expect(controller.result, isNull);
          expect(controller.selectedIndex, isNull);
          expect(controller.isDrawing, isFalse);
          expect(controller.canDraw, isTrue);
          expect(controller.canConfirm, isFalse);
          expect(await controller.confirm(), isFalse);
          expect(controller.canReplace(1), isFalse);
          expect(
            controller.beginReplacement(1, ReplacementChoice.exclude),
            isFalse,
          );
          expect(controller.restoreSessionExclusions(), isFalse);
          final replacement = drawOne();
          expect(controller.hasPendingReplacement, isFalse);
          expect(ids(controller.results), [original[1].id, replacement.id]);
          expect(controller.results[0], same(original[1]));
          expect(ids(snapshot), ids(original));
          expect(controller.results, hasLength(2));
          expect(controller.canConfirm, isTrue);
          controller.finishDraw();
          expect(controller.results, hasLength(2));
          if (count == 3) {
            final third = drawOne();
            expect(third.id, isNot(original[1].id));
            expect(third.id, isNot(replacement.id));
            if (choice == ReplacementChoice.exclude) {
              expect(third.id, isNot(original[0].id));
            }
          }
          expect(controller.canDraw, isFalse);
          final finalIds = ids(controller.results);
          expect(await controller.confirm(), isTrue);
          expect(ids(controller.history.single.options), finalIds);
          await expectStoredMeal(finalIds);
        },
      );
    }
  }

  test('redraw can select the outgoing item again after reshuffling', () {
    cooking(2);
    final original = [drawOne(), drawOne()];
    final poolBefore = ids(controller.candidates);
    expect(controller.beginReplacement(1, ReplacementChoice.redraw), isTrue);
    expect(ids(controller.candidates), isNot(poolBefore));
    random.index = controller.candidates.indexWhere(
      (option) => option.id == original[1].id,
    );
    expect(random.index, greaterThanOrEqualTo(0));
    expect(drawOne(), same(original[1]));
    expect(ids(controller.results), ids(original));
    expect(controller.sessionExclusions, isEmpty);
  });

  test(
    'every remaining identity stays selectable with one uniform index draw',
    () {
      cooking(2);
      final scope = ids(controller.candidates);
      drawOne();
      final retained = drawOne();
      for (final target in scope.where((id) => id != retained.id)) {
        expect(
          controller.beginReplacement(
            controller.results.indexWhere((option) => option.id != retained.id),
            ReplacementChoice.redraw,
          ),
          isTrue,
        );
        final pool = controller.candidates;
        expect(pool, hasLength(scope.length - 1));
        random.index = pool.indexWhere((option) => option.id == target);
        expect(random.index, greaterThanOrEqualTo(0));
        final drawsBefore = random.bounds.length;
        expect(drawOne().id, target);
        expect(random.bounds.length, drawsBefore + 1);
        expect(controller.results[0], same(retained));
      }
    },
  );

  for (final scenario in [MealScenario.eat, MealScenario.restaurant]) {
    test(
      '$scenario replacement requires a separate start and stays one result',
      () async {
        expect(controller.changeScenario(scenario), isTrue);
        final original = drawOne();
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        expect(controller.sessionExclusions, {original.id});
        expect(controller.result, isNull);
        expect(controller.isDrawing, isFalse);
        expect(controller.hasRound, isTrue);
        expect(controller.isModeLocked, isTrue);
        expect(controller.startDraw(), isTrue);
        expect(controller.hasPendingReplacement, isTrue);
        expect(controller.startDraw(), isFalse);
        expect(controller.canConfirm, isFalse);
        expect(await controller.confirm(), isFalse);
        controller.finishDraw();
        expect(controller.results, hasLength(1));
        expect(controller.result!.id, isNot(original.id));
        expect(controller.canDraw, isFalse);
        expect(controller.canConfirm, isTrue);
      },
    );
  }

  for (final scenario in MealScenario.values) {
    test(
      '$scenario impossible replacement preserves outgoing and exclusions for both choices',
      () {
        expect(controller.changeScenario(scenario), isTrue);
        if (scenario == MealScenario.cook) {
          expect(controller.changeCookingCount(2), isTrue);
        }
        keepCandidates(controller.requestedCount);
        for (var index = 0; index < controller.requestedCount; index++) {
          drawOne();
        }
        final results = controller.results;
        final result = controller.result;
        final pool = controller.candidates;
        final exclusions = controller.sessionExclusions;
        final selectedIndex = controller.selectedIndex;
        for (final choice in ReplacementChoice.values) {
          expect(controller.canReplace(0), isTrue);
          expect(controller.beginReplacement(0, choice), isFalse);
          expect(controller.error, contains('没有其他'));
          expect(controller.hasConfirmationAttempt, isFalse);
          expect(controller.results, same(results));
          expect(controller.result, same(result));
          expect(controller.candidates, same(pool));
          expect(controller.selectedIndex, selectedIndex);
          expect(controller.sessionExclusions, exclusions);
          expect(controller.hasPendingReplacement, isFalse);
          expect(controller.canConfirm, isTrue);
        }
      },
    );
  }

  test(
    'exclusions survive confirmation and resets; restoration keeps deactivation',
    () async {
      cooking(3);
      final inactive = controller.candidates.last.id;
      expect(
        (await controller.setOptionActive(inactive, false)).changed,
        isTrue,
      );
      final excluded = drawOne().id;
      expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
      drawOne();
      expect(await controller.confirm(), isTrue);
      expect(controller.sessionExclusions, {excluded});
      expect(ids(controller.candidates), isNot(contains(excluded)));
      expect(controller.changeScenario(MealScenario.eat), isTrue);
      expect(controller.sessionExclusions, {excluded});
      expect(controller.changeScenario(MealScenario.cook), isTrue);
      drawOne();
      expect(controller.abandon(), isTrue);
      expect(controller.changePeriod(MealPeriod.dinner), isTrue);
      expect(controller.sessionExclusions, {excluded});
      expect(ids(controller.candidates), isNot(contains(excluded)));
      expect(controller.restoreSessionExclusions(), isTrue);
      expect(controller.sessionExclusions, isEmpty);
      expect(ids(controller.candidates), contains(excluded));
      expect(ids(controller.candidates), isNot(contains(inactive)));
      expect(
        controller.options
            .firstWhere((option) => option.id == inactive)
            .isActive,
        isFalse,
      );
    },
  );

  test(
    'a fresh controller clears a pending replacement and session exclusions',
    () async {
      final excluded = drawOne().id;
      expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
      controller.dispose();
      await createController();
      expect(controller.hasPendingReplacement, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.sessionExclusions, isEmpty);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(ids(controller.candidates), contains(excluded));
      expect(controller.history, isEmpty);
    },
  );

  test('replacement freezes yesterday scope across midnight', () async {
    cooking(3);
    now = DateTime(2026, 10, 7, 12);
    final yesterday = drawOne();
    expect(await controller.confirm(), isTrue);
    now = DateTime(2026, 10, 8, 23, 59);
    expect(
      await controller.updatePreferences(
        const MealPreferences(excludeYesterday: true),
      ),
      isTrue,
    );
    final scope = ids(controller.candidates).toSet();
    final original = [drawOne(), drawOne()];
    now = DateTime(2026, 10, 9, 0, 1);
    expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
    expect(
      ids(controller.candidates).toSet(),
      scope.difference(ids(original).toSet()),
    );
    expect(ids(controller.candidates), isNot(contains(yesterday.id)));
    drawOne();
    expect(controller.beginReplacement(1, ReplacementChoice.redraw), isTrue);
    expect(ids(controller.candidates), isNot(contains(original[0].id)));
    expect(ids(controller.candidates), isNot(contains(yesterday.id)));
    drawOne();
    expect(controller.abandon(), isTrue);
    expect(ids(controller.candidates), contains(yesterday.id));
    expect(ids(controller.candidates), isNot(contains(original[0].id)));
    expect(controller.period, MealPeriod.lunch);
  });

  test(
    'unchanged actions preserve pending state; durable edits invalidate it',
    () async {
      cooking(3);
      final outgoing = drawOne();
      expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
      final pool = controller.candidates;
      expect(controller.changePeriod(controller.period), isTrue);
      expect(controller.changeScenario(controller.scenario), isTrue);
      expect(controller.changeCookingCount(3), isTrue);
      expect(
        controller.changeCategoryFilters(controller.selectedCategoryIds),
        isTrue,
      );
      await controller.applyDataChange(changed: false);
      expect(
        (await controller.setOptionActive(outgoing.id, true)).changed,
        isFalse,
      );
      expect(controller.hasPendingReplacement, isTrue);
      expect(controller.candidates, same(pool));
      expect(controller.restartNotice, isNull);
      final changed = await controller.saveCategory(name: '另一个场景分类');
      expect(changed.changed, isTrue);
      expect(controller.hasPendingReplacement, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.result, isNull);
      expect(controller.selectedIndex, isNull);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.sessionExclusions, {outgoing.id});
      expect(controller.takeRestartNotice(), isNotNull);
    },
  );

  test(
    'whole-round reset clears pending and live spin without undoing exclusions',
    () {
      cooking(3);
      final home = controller
          .categoriesFor(MealScenario.cook)
          .firstWhere((category) => category.name == '快手菜');
      final resets = <void Function()>[
        () => controller.changePeriod(MealPeriod.dinner),
        () => controller.changeCookingCount(2),
        () => controller.changeCategoryFilters({home.id}),
        () => controller.abandon(),
        () => controller.changeScenario(MealScenario.restaurant),
      ];
      final excluded = <String>{};
      for (final reset in resets) {
        final outgoing = drawOne();
        excluded.add(outgoing.id);
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        expect(controller.startDraw(), isTrue);
        reset();
        expect(controller.hasPendingReplacement, isFalse);
        expect(controller.results, isEmpty);
        expect(controller.result, isNull);
        expect(controller.isDrawing, isFalse);
        expect(controller.selectedIndex, isNull);
        expect(controller.hasRound, isFalse);
        expect(controller.sessionExclusions, excluded);
        controller.finishDraw();
        expect(controller.results, isEmpty);
      }
    },
  );

  test('invalid slot or drawing cannot begin replacement', () {
    expect(controller.canReplace(0), isFalse);
    expect(controller.beginReplacement(0, ReplacementChoice.exclude), isFalse);
    cooking(3);
    drawOne();
    for (final index in [-1, 1, 20]) {
      expect(controller.canReplace(index), isFalse);
      expect(
        controller.beginReplacement(index, ReplacementChoice.exclude),
        isFalse,
      );
    }
    expect(controller.startDraw(), isTrue);
    expect(controller.canReplace(0), isFalse);
    expect(controller.beginReplacement(0, ReplacementChoice.exclude), isFalse);
    expect(controller.sessionExclusions, isEmpty);
  });

  for (final failurePhase in [
    ConfirmationPhase.afterItemWritten,
    ConfirmationPhase.beforeAcknowledgement,
  ]) {
    test(
      '$failurePhase locks the replaced payload and retry saves it exactly once',
      () async {
        cooking(4);
        drawOne();
        drawOne();
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        final outgoing = controller.sessionExclusions.single;
        drawOne();
        final finalIds = ids(controller.results);
        final confirmedAt = now;
        fault = (phase) {
          if (phase == failurePhase) {
            throw StateError('Injected confirmation failure');
          }
        };
        expect(await controller.confirm(), isFalse);
        expect(controller.hasConfirmationAttempt, isTrue);
        expect(controller.canConfirm, isTrue);
        expect(controller.canDraw, isFalse);
        expect(controller.startDraw(), isFalse);
        expect(controller.canReplace(0), isFalse);
        expect(
          controller.beginReplacement(0, ReplacementChoice.redraw),
          isFalse,
        );
        expect(controller.hasPendingReplacement, isFalse);
        expect(ids(controller.results), finalIds);
        if (failurePhase == ConfirmationPhase.beforeAcknowledgement) {
          await expectStoredMeal(finalIds);
        } else {
          expect(await repository.history(), isEmpty);
        }
        fault = null;
        now = now.add(const Duration(days: 1));
        expect(await controller.confirm(), isTrue);
        expect(controller.hasConfirmationAttempt, isFalse);
        expect(controller.history.single.confirmedAt, confirmedAt.toUtc());
        expect(ids(controller.history.single.options), finalIds);
        expect(controller.sessionExclusions, {outgoing});
        expect(await controller.confirm(), isFalse);
        await expectStoredMeal(finalIds);
      },
    );
  }

  test(
    'saving reserves replacement boundary and repeated confirms are blocked',
    () async {
      cooking(3);
      drawOne();
      expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
      drawOne();
      final finalIds = ids(controller.results);
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      final saving = controller.confirm();
      await entered.future;
      expect(controller.canConfirm, isFalse);
      expect(await controller.confirm(), isFalse);
      expect(controller.canReplace(0), isFalse);
      expect(
        controller.beginReplacement(0, ReplacementChoice.exclude),
        isFalse,
      );
      expect(controller.abandon(), isFalse);
      release.complete();
      expect(await saving, isTrue);
      await expectStoredMeal(finalIds);
    },
  );
}
