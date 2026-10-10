import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-category-ui-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 7, 12),
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder chip(String name) => find.widgetWithText(FilterChip, name);
  final open = find.byKey(const Key('category-filter-button'));
  final apply = find.byKey(const Key('apply-category-filters'));

  testWidgets(
    'filter drafts and restart cancellation preserve result; union applies only after consent',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      await mount(tester);
      controller.startDraw();
      controller.finishDraw();
      await tester.pumpAndSettle();
      final chosen = controller.result;
      await tap(tester, open);
      await tap(tester, chip('家常菜'));
      await tap(tester, find.byTooltip('取消筛选'));
      expect(controller.selectedCategoryIds, isEmpty);
      expect(controller.result, same(chosen));
      await tap(tester, open);
      await tap(tester, chip('家常菜'));
      await tap(tester, chip('快手菜'));
      await tap(tester, apply);
      expect(find.text('更换筛选条件？'), findsOneWidget);
      await tap(tester, find.text('继续抽取'));
      expect(controller.result, same(chosen));
      expect(controller.selectedCategoryIds, isEmpty);
      await tap(tester, open);
      await tap(tester, apply);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.result, same(chosen));
      await tap(tester, open);
      await tap(tester, chip('家常菜'));
      await tap(tester, chip('快手菜'));
      await tap(tester, apply);
      await tap(tester, find.text('应用并重新开始'));
      expect(controller.hasRound, isFalse);
      expect(controller.selectedCategoryIds, hasLength(2));
      expect(controller.candidates, hasLength(8));
      expect(
        controller.candidates.where((food) => food.id == 'cook-tomato-eggs'),
        hasLength(1),
      );
      await tap(tester, find.byKey(const Key('primary-action')));
      expect(controller.result, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zero candidates offers condition adjustment and exclusion recovery without reactivation',
    (tester) async {
      final category = controller
          .categoriesFor(MealScenario.eat)
          .singleWhere((value) => value.name == '盖饭套餐');
      controller.changeCategoryFilters({category.id});
      final foods = controller.candidates.toList();
      await tester.runAsync(
        () => controller.setOptionActive(foods.first.id, false),
      );
      for (final food in foods.skip(1)) {
        controller.excludeForSession(food.id);
      }
      await mount(tester);
      expect(find.textContaining('没有符合条件的选项'), findsOneWidget);
      await tap(tester, find.byKey(const Key('adjust-empty-conditions')));
      await tap(tester, find.byKey(const Key('filter-all')));
      await tap(tester, apply);
      expect(controller.candidates, isNotEmpty);
      expect(controller.sessionExclusions, hasLength(2));
      controller.changeCategoryFilters({category.id});
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('restore-session-exclusions')));
      expect(controller.candidates, hasLength(2));
      expect(
        controller.options
            .singleWhere((food) => food.id == foods.first.id)
            .isActive,
        isFalse,
      );
      expect(controller.sessionExclusions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('filter sheet supports long names and large text at $size', (
      tester,
    ) async {
      await tester.runAsync(
        () => controller.saveCategory(name: '周末一家人一起做的家常饭菜和喜欢的小食'),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mount(tester);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tap(tester, open);
      await tap(tester, chip('周末一家人一起做的家常饭菜和喜欢的小食'));
      await tap(tester, apply);
      expect(controller.selectedCategoryIds, hasLength(1));
      expect(controller.candidates, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
