import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late DateTime now;

  Set<String> ids(Iterable<FoodOption> options) =>
      options.map((option) => option.id).toSet();

  Future<void> createController() async {
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: Random(14),
    );
    await controller.initialize();
  }

  Future<void> reopen() async {
    controller.dispose();
    await repository.close();
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    await createController();
  }

  Future<FoodOption> addOption(
    String name, {
    MealScenario scenario = MealScenario.eat,
    String? category,
  }) async {
    final saved = await controller.saveOption(
      name: name,
      scenario: scenario.name,
      category: category ?? controller.fallbackCategory(scenario).name,
      periods: MealPeriod.values.toSet(),
      allowUncertainDuplicate: true,
    );
    expect(saved.status, OptionMutationStatus.saved);
    return saved.option!;
  }

  Future<void> saveHistory(
    String operationId,
    List<FoodOption> options,
    DateTime localTime, {
    MealPeriod period = MealPeriod.lunch,
  }) async {
    await repository.confirm(
      ConfirmationOperation(
        operationId: operationId,
        confirmedAt: localTime.toUtc(),
        period: period,
        options: options,
      ),
    );
    await controller.applyDataChange(changed: true);
  }

  Future<void> enableFilter(DrawMode mode) async {
    expect(
      await controller.updatePreferences(
        MealPreferences(mode: mode, excludeYesterday: true),
      ),
      isTrue,
    );
  }

  FoodOption draw() {
    expect(controller.canDraw, isTrue);
    if (controller.preferences.mode == DrawMode.cards) {
      expect(controller.selectCard(0), isTrue);
    }
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    final result = controller.result!;
    if (controller.preferences.mode == DrawMode.cards &&
        !controller.isSingleTarget) {
      expect(controller.collectCard(), isTrue);
    }
    return result;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-yesterday-');
    now = DateTime(2026, 10, 11, 12);
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    await createController();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  for (final today in [
    DateTime(2027, 1, 1),
    DateTime(2026, 5, 1),
    DateTime(2024, 3, 1),
    DateTime(2025, 3, 1),
  ]) {
    test('UTC history uses local [midnight, midnight) before $today', () async {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final before = await addOption('边界前刻餐');
      final atStart = await addOption('边界起点餐');
      final atEnd = await addOption('边界末刻餐');
      final atToday = await addOption('边界今天餐');
      final unrelated = await addOption('边界未选餐');
      await saveHistory('before', [
        before,
      ], yesterday.subtract(const Duration(microseconds: 1)));
      await saveHistory('start', [atStart], yesterday);
      await saveHistory('end', [
        atEnd,
      ], today.subtract(const Duration(microseconds: 1)));
      await saveHistory('today', [atToday], today);
      // Supply a UTC clock too: eligibility must normalize both inputs locally.
      now = DateTime(today.year, today.month, today.day, 12).toUtc();
      await enableFilter(DrawMode.wheel);
      expect(
        ids(controller.candidates),
        containsAll(ids([before, atToday, unrelated])),
      );
      expect(
        ids(controller.candidates).intersection(ids([atStart, atEnd])),
        isEmpty,
      );
      expect(
        controller.history.every((entry) => entry.confirmedAt.isUtc),
        isTrue,
      );
      expect(
        controller.history
            .singleWhere((entry) => entry.operationId == 'start')
            .confirmedAt,
        yesterday.toUtc(),
      );
      await reopen();
      expect(controller.preferences.excludeYesterday, isTrue);
      expect(
        ids(controller.candidates).intersection(ids([atStart, atEnd])),
        isEmpty,
      );
      expect(ids(controller.candidates), containsAll(ids([before, atToday])));
    });
  }

  test(
    'all batch identities count across periods without category or scenario bleed',
    () async {
      final cookA = await addOption('昨日甲餐', scenario: MealScenario.cook);
      final cookB = await addOption('昨日乙餐', scenario: MealScenario.cook);
      final cookC = await addOption('昨日丙餐', scenario: MealScenario.cook);
      final eatA = await addOption('昨日甲餐');
      final eatC = await addOption('昨日丙餐');
      final restaurantA = await addOption(
        '昨日甲餐',
        scenario: MealScenario.restaurant,
      );
      await saveHistory(
        'cooking-breakfast',
        [cookA, cookB],
        DateTime(2026, 10, 10, 6),
        period: MealPeriod.breakfast,
      );
      await saveHistory(
        'eating-dinner',
        [eatC],
        DateTime(2026, 10, 10, 19),
        period: MealPeriod.dinner,
      );
      await enableFilter(DrawMode.wheel);
      expect(controller.changePeriod(MealPeriod.lateNight), isTrue);
      expect(controller.changeScenario(MealScenario.cook), isTrue);
      expect(
        ids(controller.candidates).intersection(ids([cookA, cookB])),
        isEmpty,
      );
      expect(ids(controller.candidates), contains(cookC.id));
      expect(controller.changeScenario(MealScenario.eat), isTrue);
      expect(ids(controller.candidates), contains(eatA.id));
      expect(ids(controller.candidates), isNot(contains(eatC.id)));
      expect(controller.changeScenario(MealScenario.restaurant), isTrue);
      expect(ids(controller.candidates), contains(restaurantA.id));
      expect(controller.period, MealPeriod.lateNight);
      await reopen();
      final meal = controller.history.singleWhere(
        (entry) => entry.operationId == 'cooking-breakfast',
      );
      expect(meal.options.map((option) => option.id), [cookA.id, cookB.id]);
      expect(meal.period, MealPeriod.breakfast);
    },
  );

  test(
    'public rename, delete and restore retain yesterday identity until history deletion',
    () async {
      final original = await addOption('妈妈的招牌餐');
      await saveHistory('identity', [original], DateTime(2026, 10, 10, 12));
      await enableFilter(DrawMode.cards);
      final renamed = await controller.saveOption(
        id: original.id,
        name: '妈妈的拿手餐',
        category: original.category,
        periods: original.periods,
        confirmSameFood: true,
        allowUncertainDuplicate: true,
      );
      expect(renamed.status, OptionMutationStatus.saved);
      expect(renamed.option!.id, original.id);
      expect(ids(controller.cardDeck), isNot(contains(original.id)));
      expect((await controller.deleteOption(original.id)).changed, isTrue);
      final prompt = await controller.saveOption(
        name: renamed.option!.name,
        category: original.category,
        periods: original.periods,
      );
      expect(prompt.status, OptionMutationStatus.restorationRequired);
      expect(prompt.option!.id, original.id);
      final restored = await controller.saveOption(
        name: renamed.option!.name,
        category: original.category,
        periods: original.periods,
        confirmRestore: true,
        restoreOptionId: original.id,
      );
      expect(restored.status, OptionMutationStatus.saved);
      expect(restored.option!.id, original.id);
      expect(restored.option!.isDeleted, isFalse);
      expect(restored.option!.isActive, isTrue);
      await reopen();
      expect(controller.preferences.excludeYesterday, isTrue);
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.history.single.option.id, original.id);
      expect(controller.history.single.option.name, renamed.option!.name);
      expect(ids(controller.cardDeck), isNot(contains(original.id)));
      expect(await controller.deleteHistory('identity'), isTrue);
      expect(ids(controller.cardDeck), contains(original.id));
      await reopen();
      expect(controller.history, isEmpty);
      expect(ids(controller.cardDeck), contains(original.id));
    },
  );

  for (final mode in DrawMode.values) {
    test(
      '$mode filter restart requires consent and a successful durable write',
      () async {
        expect(
          await controller.updatePreferences(MealPreferences(mode: mode)),
          isTrue,
        );
        expect(controller.changeScenario(MealScenario.cook), isTrue);
        expect(controller.changeCookingCount(3), isTrue);
        expect(controller.changePeriod(MealPeriod.dinner), isTrue);
        final outgoing = draw();
        final retained = draw();
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        final pool = controller.candidates;
        if (mode == DrawMode.cards) expect(controller.selectCard(0), isTrue);
        expect(controller.startDraw(), isTrue);
        final selectedIndex = controller.selectedIndex;
        final preferences = MealPreferences(mode: mode, excludeYesterday: true);
        expect(await controller.updatePreferences(preferences), isFalse);
        final otherMode = mode == DrawMode.wheel
            ? DrawMode.cards
            : DrawMode.wheel;
        expect(
          await controller.updatePreferences(
            MealPreferences(mode: otherMode, excludeYesterday: true),
            restartRound: true,
          ),
          isFalse,
        );
        final database = await databaseFactoryFfi.openDatabase(
          '${directory.path}/meal.sqlite',
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          await database.execute('''
          CREATE TRIGGER fail_yesterday_preferences AFTER INSERT ON preferences
          WHEN NEW.exclude_yesterday = 1
          BEGIN SELECT RAISE(ABORT, 'Injected yesterday preference failure'); END
        ''');
          expect(
            await controller.updatePreferences(preferences, restartRound: true),
            isFalse,
          );
          expect(controller.preferences.excludeYesterday, isFalse);
          expect((await repository.preferences()).excludeYesterday, isFalse);
          expect(controller.hasRound, isTrue);
          expect(controller.isModeLocked, isTrue);
          expect(controller.hasPendingReplacement, isTrue);
          expect(controller.isDrawing, isTrue);
          expect(controller.selectedIndex, selectedIndex);
          expect(controller.candidates, same(pool));
          expect(controller.results.single.id, retained.id);
          expect(controller.sessionExclusions, {outgoing.id});
          expect(controller.error, isNotNull);
          await database.execute('DROP TRIGGER fail_yesterday_preferences');
          expect(
            await controller.updatePreferences(preferences, restartRound: true),
            isTrue,
          );
          expect(controller.preferences.excludeYesterday, isTrue);
          expect((await repository.preferences()).excludeYesterday, isTrue);
          expect(controller.hasRound, isFalse);
          expect(controller.isModeLocked, isFalse);
          expect(controller.hasPendingReplacement, isFalse);
          expect(controller.isDrawing, isFalse);
          expect(controller.results, isEmpty);
          expect(controller.selectedIndex, isNull);
          expect(controller.sessionExclusions, {outgoing.id});
          expect(controller.period, MealPeriod.dinner);
          controller.finishDraw();
          expect(controller.results, isEmpty);
        } finally {
          await database.close();
        }
        await reopen();
        expect(controller.preferences.mode, mode);
        expect(controller.preferences.excludeYesterday, isTrue);
      },
    );

    test(
      '$mode freezes midnight scope through replacements and recomputes next round',
      () async {
        expect(
          (await controller.saveCategory(
            name: '午夜专用分类',
            scenario: MealScenario.cook,
          )).status,
          OptionMutationStatus.saved,
        );
        final category = controller
            .categoriesFor(MealScenario.cook)
            .singleWhere((value) => value.name == '午夜专用分类');
        final dishes = <FoodOption>[];
        for (final suffix in ['甲', '乙', '丙', '丁', '戊', '己', '庚']) {
          dishes.add(
            await addOption(
              '午夜$suffix餐',
              scenario: MealScenario.cook,
              category: category.name,
            ),
          );
        }
        await saveHistory(
          'old-day',
          [dishes[0]],
          DateTime(2026, 10, 9, 18),
          period: MealPeriod.dinner,
        );
        await saveHistory(
          'new-day',
          [dishes[1]],
          DateTime(2026, 10, 10, 6),
          period: MealPeriod.breakfast,
        );
        expect(controller.changeScenario(MealScenario.cook), isTrue);
        expect(controller.changeCategoryFilters({category.id}), isTrue);
        expect(controller.changeCookingCount(3), isTrue);
        expect(controller.changePeriod(MealPeriod.dinner), isTrue);
        now = DateTime(2026, 10, 10, 23, 59);
        await enableFilter(mode);
        expect(controller.excludeForSession(dishes[2].id), isTrue);
        final scope = ids(dishes).difference({dishes[0].id, dishes[2].id});
        expect(ids(controller.candidates), scope);
        final outgoing = draw();
        now = DateTime(2026, 10, 11, 0, 1).toUtc();
        final retained = draw();
        expect(retained.id, isNot(outgoing.id));
        expect(scope, contains(retained.id));
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        final excluded = {dishes[2].id, outgoing.id};
        expect(controller.sessionExclusions, excluded);
        expect(
          ids(controller.candidates),
          scope.difference({outgoing.id, retained.id}),
        );
        final replaced = draw();
        expect(
          controller.beginReplacement(1, ReplacementChoice.redraw),
          isTrue,
        );
        expect(
          ids(controller.candidates),
          scope.difference({outgoing.id, retained.id}),
        );
        draw();
        draw();
        expect(controller.results, hasLength(3));
        expect(ids(controller.results), hasLength(3));
        expect(ids(controller.results).difference(scope), isEmpty);
        expect(ids(controller.results).intersection(excluded), isEmpty);
        expect(controller.results.first.id, retained.id);
        expect(scope, contains(replaced.id));
        expect(controller.period, MealPeriod.dinner);
        expect(controller.currentLocalPeriod, MealPeriod.lateNight);
        expect(controller.abandon(), isTrue);
        final nextScope = ids(dishes).difference({...excluded, dishes[1].id});
        expect(ids(controller.candidates), nextScope);
        if (mode == DrawMode.cards) expect(ids(controller.cardDeck), nextScope);
        expect(controller.period, MealPeriod.dinner);
        expect(controller.sessionExclusions, excluded);
        final next = draw();
        expect(nextScope, contains(next.id));
        expect(await controller.confirm(), isTrue);
        expect(controller.history.first.period, MealPeriod.dinner);
        expect(controller.history.first.option.id, next.id);
        expect(controller.sessionExclusions, excluded);
      },
    );

    test(
      '$mode empty pool recovers via public history deletion and filter reset',
      () async {
        final category = await controller.saveCategory(name: '昨日专用分类');
        expect(category.status, OptionMutationStatus.saved);
        final categoryId = controller
            .categoriesFor(MealScenario.eat)
            .singleWhere((value) => value.name == '昨日专用分类')
            .id;
        final only = await addOption('昨日唯一餐', category: '昨日专用分类');
        await saveHistory('only', [only], DateTime(2026, 10, 10, 12));
        expect(controller.changeCategoryFilters({categoryId}), isTrue);
        await enableFilter(mode);
        expect(controller.availableCount, 0);
        expect(controller.canDraw, isFalse);
        if (mode == DrawMode.cards) expect(controller.cardDeck, isEmpty);
        expect(await controller.deleteHistory('only'), isTrue);
        expect(ids(controller.candidates), {only.id});
        draw();
        expect(controller.abandon(), isTrue);
        await saveHistory(
          'only-again',
          [only],
          DateTime(2026, 10, 10, 19),
          period: MealPeriod.dinner,
        );
        expect(controller.availableCount, 0);
        expect(
          await controller.updatePreferences(MealPreferences(mode: mode)),
          isTrue,
        );
        expect(ids(controller.candidates), {only.id});
        draw();
      },
    );
  }
}
