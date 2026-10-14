import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late String categoryId;
  final events = <dynamic>[];
  Finder key(String name) => find.byKey(ValueKey(name));

  setUp(() async {
    events.clear();
    directory = await Directory.systemTemp.createTemp('whatever-stage-a11y-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
    );
    await repository.saveCategory(name: '长名称验证', scenario: MealScenario.cook);
    for (var index = 0; index < 12; index++) {
      final saved = await repository.saveOption(
        name: '手工验证第${index + 1}道包含完整中文食材烹饪方式和配菜的超长名称',
        scenario: 'cook',
        category: '长名称验证',
        periods: {MealPeriod.lunch},
        allowUncertainDuplicate: true,
      );
      expect(saved.status, OptionMutationStatus.saved);
    }
    controller = MealController(
      repository: repository,
      random: Random(16),
      clock: () => DateTime(2026, 10, 13, 12),
    );
    await controller.initialize();
    controller.changeScenario(MealScenario.cook);
    categoryId = controller
        .categoriesFor(MealScenario.cook)
        .singleWhere((category) => category.name == '长名称验证')
        .id;
    controller.changeCategoryFilters({categoryId});
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
    bool reduced = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(
          disableAnimations: reduced,
          accessibleNavigation: true,
        );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async => events.add(message),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> activate(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForSave(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isSaving || controller.isBusy) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Accessible confirmation did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reduced motion uses static wheel feedback and still needs confirmation',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await mount(tester);
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        final start = tester.getSemantics(key('primary-action'));
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          start.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        final rotor = key('wheel-rotor');
        final angle = List<double>.of(
          tester.widget<Transform>(rotor).transform.storage,
        );
        final bounds = tester.getRect(key('wheel-status'));
        for (var frame = 0; frame < 3; frame++) {
          // AnimationController also shortens its clock for system reduced
          // motion; sample before that brief static feedback completes.
          await tester.pump(const Duration(milliseconds: 1));
          expect(
            tester.widget<Transform>(rotor).transform.storage,
            orderedEquals(angle),
          );
          expect(tester.getRect(key('wheel-status')), bounds);
          expect(controller.isDrawing, isTrue);
        }
        await tester.pumpAndSettle();
        expect(controller.results, hasLength(1));
        expect(controller.history, isEmpty);
        expect(key('draw-result'), findsOneWidget);
        expect(
          tester
              .getSemantics(key('primary-action'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'wheel semantics expose state once and move focus to full result',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await mount(tester, reduced: false);
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        final start = tester.getSemantics(key('primary-action'));
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          start.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        final status = tester.getSemantics(key('wheel-status'));
        expect(status.label, '转盘，共 12 个候选');
        expect(status.value, '正在挑选');
        expect(status.flagsCollection.isLiveRegion, isTrue);
        final snapshot = status.getSemanticsData();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.getSemantics(key('wheel-status')).getSemanticsData().label,
          snapshot.label,
        );
        expect(events.where((event) => event['type'] == 'focus'), isEmpty);
        await tester.pumpAndSettle();
        final name = controller.result!.name;
        final result = tester.getSemantics(find.bySemanticsLabel('抽取结果：$name'));
        expect(
          events.where((event) => event['type'] == 'focus').single['nodeId'],
          result.id,
        );
        expect(key('draw-result').hitTestable(), findsOneWidget);
        expect(controller.history, isEmpty);
        expect(tester.getSemantics(key('wheel-status')).value, '已揭晓');
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'semantic actions filter, replace, confirm once and inspect history',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await mount(tester);
        await activate(tester, key('category-filter-button'));
        await activate(tester, key('filter-period-breakfast'));
        await activate(tester, key('apply-category-filters'));
        await waitForSave(tester);
        expect(controller.availableCount, 0);
        expect(
          tester
              .getSemantics(key('primary-action'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        await activate(tester, key('adjust-empty-conditions'));
        await activate(tester, key('filter-period-lunch'));
        await activate(tester, key('apply-category-filters'));
        await waitForSave(tester);
        expect(controller.availableCount, 12);
        await activate(tester, key('primary-action'));
        final outgoing = controller.result!.id;
        await activate(tester, key('replace-result-0'));
        await activate(tester, key('replacement-exclude'));
        expect(controller.results.single.id, isNot(outgoing));
        final chosen = controller.result!.name;
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        final confirm = tester.getSemantics(key('primary-action'));
        await tester.runAsync(() async {
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(confirm.id, SemanticsAction.tap);
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(confirm.id, SemanticsAction.tap);
        });
        await waitForSave(tester);
        expect(controller.history, hasLength(1));
        await activate(tester, find.text('足迹'));
        await activate(
          tester,
          key('history-${controller.history.single.operationId}'),
        );
        expect(find.text('足迹详情'), findsOneWidget);
        final fullName = find.text(chosen);
        await tester.ensureVisible(fullName);
        await tester.pumpAndSettle();
        expect(fullName.hitTestable(), findsOneWidget);
        expect(tester.getSemantics(fullName).label, contains(chosen));
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'ten full Chinese results and controls reachable at $size x$scale',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            controller.changeCookingCount(10);
            await mount(tester, size: size, scale: scale);
            for (var index = 0; index < 10; index++) {
              await activate(
                tester,
                key(index == 0 ? 'primary-action' : 'draw-next-dish'),
              );
              expect(controller.results, hasLength(index + 1));
              expect(tester.takeException(), isNull);
            }
            for (var index = 0; index < 10; index++) {
              await activate(tester, key('cooking-result-$index'));
              expect(controller.result!.id, controller.results[index].id);
              expect(
                tester.widget<Text>(key('draw-result')).data,
                controller.results[index].name,
              );
              expect(key('draw-result').hitTestable(), findsOneWidget);
              expect(
                tester.getSemantics(key('cooking-result-$index')).label,
                contains(controller.results[index].name),
              );
              expect(
                tester
                    .getSemantics(key('cooking-result-$index'))
                    .flagsCollection
                    .isSelected,
                Tristate.isTrue,
              );
              expect(tester.takeException(), isNull);
            }
            for (final index in [0, 5, 9]) {
              await activate(tester, key('cooking-result-$index'));
              await tester.ensureVisible(key('replace-result-$index'));
              await tester.pumpAndSettle();
              expect(
                key('replace-result-$index').hitTestable(),
                findsOneWidget,
              );
            }
            await tester.ensureVisible(key('primary-action'));
            await tester.pumpAndSettle();
            final bounds = tester.getRect(key('primary-action'));
            expect(bounds.top, greaterThanOrEqualTo(24));
            expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
            expect(key('primary-action').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }
}
