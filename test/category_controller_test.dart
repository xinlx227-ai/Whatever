import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';

class IndexedRandom implements Random {
  int index = 0;
  @override
  int nextInt(int max) => index % max;
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
  late IndexedRandom random;
  ConfirmationFault? fault;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'whatever-category-controller-',
    );
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    random = IndexedRandom();
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 7, 12),
      random: random,
    );
    await controller.initialize();
  });
  tearDown(() async {
    fault = null;
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  MealCategory category(String name, [MealScenario? scenario]) => controller
      .categoriesFor(scenario ?? controller.scenario)
      .singleWhere((category) => category.name == name);

  test(
    'overlapping memberships form one union and each random index selects one identity',
    () {
      controller.changeScenario(MealScenario.cook);
      final ids = {category('家常菜').id, category('快手菜').id, category('下饭菜').id};
      controller.changeCategoryFilters(ids);
      final expected = controller.options
          .where(
            (option) =>
                option.scenario == 'cook' &&
                option.periods.contains(MealPeriod.lunch) &&
                option.categories.any({'家常菜', '快手菜', '下饭菜'}.contains),
          )
          .map((option) => option.id)
          .toSet();
      expect(
        controller.candidates.map((option) => option.id),
        unorderedEquals(expected),
      );
      expect(
        controller.candidates.where(
          (option) => option.id == 'cook-tomato-eggs',
        ),
        hasLength(1),
      );
      final drawn = <String>[];
      for (var index = 0; index < expected.length; index++) {
        random.index = index;
        expect(controller.startDraw(), isTrue);
        controller.finishDraw();
        drawn.add(controller.result!.id);
        controller.abandon();
      }
      expect(drawn, unorderedEquals(expected));
    },
  );

  test(
    'no-op or failed category saves preserve a round; real cross-scenario changes reset it',
    () async {
      final home = category('家常菜', MealScenario.cook);
      controller.startDraw();
      controller.finishDraw();
      final result = controller.result;
      expect(
        (await controller.saveCategory(
          id: home.id,
          name: ' 家常菜 ',
          scenario: MealScenario.cook,
        )).status,
        OptionMutationStatus.unchanged,
      );
      expect(
        (await controller.saveCategory(
          id: home.id,
          name: '全部',
          scenario: MealScenario.cook,
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(controller.result, same(result));
      expect(controller.restartNotice, isNull);
      expect(
        (await controller.saveCategory(
          id: home.id,
          name: '家里的味道',
          scenario: MealScenario.cook,
        )).changed,
        isTrue,
      );
      expect(controller.hasRound, isFalse);
      expect(controller.restartNotice, isNotNull);
      expect(controller.scenario, MealScenario.eat);
    },
  );

  test(
    'selected category keeps identity on rename and follows deletion to renamed fallback',
    () async {
      await controller.saveCategory(name: '周末');
      final custom = category('周末');
      final food = (await controller.saveOption(
        name: '私房午餐',
        periods: {MealPeriod.lunch},
        category: custom.name,
      )).option!;
      controller.changeCategoryFilters({custom.id});
      await controller.saveCategory(id: custom.id, name: '随心');
      expect(controller.selectedCategoryIds, {custom.id});
      expect(controller.candidates.single.id, food.id);
      final fallback = controller.fallbackCategory(MealScenario.eat);
      await controller.saveCategory(id: fallback.id, name: '待整理');
      controller.startDraw();
      controller.finishDraw();
      await controller.confirm();
      await controller.deleteCategory(custom.id);
      expect(controller.selectedCategoryIds, {fallback.id});
      expect(controller.candidates.single.id, food.id);
      expect(controller.candidates.single.category, '待整理');
      expect(controller.history.single.option.id, food.id);
      expect(controller.startDraw(), isTrue);
      controller.finishDraw();
      expect(controller.changeCategoryFilters({fallback.id}), isTrue);
      expect(controller.hasRound, isTrue);
      expect(controller.changeCategoryFilters({'invalid-id'}), isFalse);
      expect(controller.hasRound, isTrue);
      controller.changeScenario(MealScenario.cook);
      expect(controller.selectedCategoryIds, isEmpty);
    },
  );

  test(
    'empty recovery restores session exclusions while deactivation and filters remain',
    () async {
      controller.changeCategoryFilters({category('盖饭套餐').id});
      final initial = controller.candidates.toList();
      await controller.setOptionActive(initial.first.id, false);
      for (final option in initial.skip(1)) {
        controller.excludeForSession(option.id);
      }
      expect(controller.candidates, isEmpty);
      expect(controller.startDraw(), isFalse);
      expect(controller.restoreSessionExclusions(), isTrue);
      expect(controller.error, isNull);
      expect(
        controller.candidates.map((option) => option.id),
        unorderedEquals(initial.skip(1).map((option) => option.id)),
      );
      expect(
        controller.options
            .firstWhere((option) => option.id == initial.first.id)
            .isActive,
        isFalse,
      );
      expect(controller.selectedCategoryIds, {category('盖饭套餐').id});
    },
  );

  test(
    'category writes wait for in-flight confirmation and block new draws',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      controller.startDraw();
      controller.finishDraw();
      final chosen = controller.result!;
      final confirmation = controller.confirm();
      await entered.future;
      final mutation = controller.saveCategory(name: '收藏');
      expect(controller.isBusy, isTrue);
      expect(controller.startDraw(), isFalse);
      release.complete();
      expect(await confirmation, isTrue);
      expect((await mutation).changed, isTrue);
      expect(controller.history.single.option.id, chosen.id);
      expect(
        controller
            .categoriesFor(MealScenario.eat)
            .any((category) => category.name == '收藏'),
        isTrue,
      );
    },
  );
}
