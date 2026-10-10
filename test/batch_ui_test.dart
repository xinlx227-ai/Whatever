import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
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
  ConfirmationFault? fault;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-batch-ui-');
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 8, 12, 30),
      random: Random(37),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    final button = key('primary-action');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(button);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isSaving) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Batch confirmation did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'count scope, ordered explicit draws and early confirmation form one record',
    (tester) async {
      await mount(tester);
      expect(key('cooking-count-controls'), findsNothing);
      await tap(tester, key('decide-scenario-cook'));
      expect(controller.cookingCount, 1);
      expect(
        tester.getTopLeft(key('cooking-count-controls')).dy,
        greaterThan(tester.getBottomLeft(key('category-filter-button')).dy),
      );
      await tap(tester, key('cooking-count-3'));
      await tap(tester, key('primary-action'));
      expect(controller.results, hasLength(1));
      final first = controller.results.first.id;
      expect(find.text('就做这 1 道菜'), findsOneWidget);
      await tap(tester, key('draw-next-dish'));
      expect(controller.results, hasLength(2));
      expect(controller.results.first.id, first);
      expect(controller.results.map((item) => item.id).toSet(), hasLength(2));
      expect(find.text('已选 2 / 3 道'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tap(tester, key('draw-back'));
      await tap(tester, find.text('继续抽取'));
      expect(controller.results, hasLength(2));
      final names = controller.results.map((item) => item.name).join('、');
      await confirm(tester);
      expect(controller.results, isEmpty);
      expect(controller.cookingCount, 3);
      final entries = await tester.runAsync(repository.history);
      expect(entries, hasLength(1));
      expect(entries!.single.options, hasLength(2));
      await tap(tester, find.text('足迹'));
      expect(find.text(names), findsOneWidget);
      expect(find.text('12:30 · 午餐 · 做什么'), findsOneWidget);
      await tap(tester, find.text('决定'));
      await tap(tester, key('decide-scenario-restaurant'));
      expect(key('cooking-count-controls'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom count validates range and restart cancellation preserves results',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      await mount(tester);
      await tap(tester, key('cooking-count-custom'));
      for (final invalid in ['0', '11', '1.5', '']) {
        await tester.enterText(key('custom-cooking-count-input'), invalid);
        await tap(tester, key('apply-custom-cooking-count'));
        expect(find.text('请输入 1 到 10 之间的整数'), findsOneWidget);
      }
      await tester.enterText(key('custom-cooking-count-input'), '10');
      await tap(tester, key('apply-custom-cooking-count'));
      expect(controller.cookingCount, 10);
      await tap(tester, key('primary-action'));
      final chosen = controller.results.single.id;
      expect(key('cooking-count-2'), findsNothing);
      await tap(tester, key('restart-round'));
      await tap(tester, find.text('继续抽取'));
      expect(controller.cookingCount, 10);
      expect(controller.results.single.id, chosen);
      await tap(tester, key('restart-round'));
      await tap(tester, find.text('清空并重新开始'));
      await tap(tester, key('cooking-count-2'));
      expect(controller.cookingCount, 2);
      expect(controller.hasRound, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shortage offers reduced count or filters and never auto draws', (
    tester,
  ) async {
    controller.changeScenario(MealScenario.cook);
    final category = controller
        .categoriesFor(MealScenario.cook)
        .singleWhere((item) => item.name == '汤羹');
    controller.changeCategoryFilters({category.id});
    final available = controller.candidates.length;
    expect(available, inInclusiveRange(1, 9));
    controller.changeCookingCount(10);
    await mount(tester);
    await tap(tester, key('primary-action'));
    expect(find.text('这次的菜还不够'), findsOneWidget);
    await tap(tester, find.text('调整筛选条件'));
    expect(key('apply-category-filters'), findsOneWidget);
    await tap(tester, key('apply-category-filters'));
    expect(controller.cookingCount, 10);
    expect(controller.hasRound, isFalse);
    await tap(tester, key('primary-action'));
    await tap(tester, find.text('改为 $available 道'));
    expect(controller.cookingCount, available);
    expect(controller.hasRound, isFalse);
    await tap(tester, key('primary-action'));
    expect(controller.results.single.categories, contains('汤羹'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lost acknowledgement keeps ordered batch and disables adding until retry',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester);
      await tap(tester, key('primary-action'));
      await tap(tester, key('draw-next-dish'));
      final ids = controller.results.map((item) => item.id).toList();
      fault = (phase) {
        if (phase == ConfirmationPhase.beforeAcknowledgement) {
          throw StateError('lost acknowledgement');
        }
      };
      await confirm(tester);
      expect(controller.results.map((item) => item.id), ids);
      expect(find.text('重试保存'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(key('draw-next-dish')).onPressed,
        isNull,
      );
      await confirm(tester);
      final entries = await tester.runAsync(repository.history);
      expect(entries, hasLength(1));
      expect(entries!.single.options.map((item) => item.id), ids);
      expect(controller.hasRound, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'ten results and custom controls remain reachable at $size and 2x text',
      (tester) async {
        controller.changeScenario(MealScenario.cook);
        controller.changeCookingCount(10);
        await mount(tester, size: size, scale: 2);
        await tap(tester, key('cooking-count-custom'));
        await tap(tester, key('apply-custom-cooking-count'));
        for (var index = 0; index < 10; index++) {
          await tap(
            tester,
            key(index == 0 ? 'primary-action' : 'draw-next-dish'),
          );
          expect(controller.results, hasLength(index + 1));
          expect(tester.takeException(), isNull);
        }
        expect(key('draw-next-dish'), findsNothing);
        for (var index = 0; index < 10; index++) {
          await tester.ensureVisible(key('cooking-result-$index'));
          await tester.pumpAndSettle();
          expect(key('cooking-result-$index').hitTestable(), findsOneWidget);
        }
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(key('primary-action')).dy,
          lessThanOrEqualTo(size.height),
        );
        expect(key('primary-action').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
