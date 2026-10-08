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
    fault = null;
    directory = await Directory.systemTemp.createTemp(
      'whatever-replacement-ui-',
    );
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
    await tester.ensureVisible(key('primary-action'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(key('primary-action'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isSaving) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Replacement confirmation did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> exhaustPartialBatch(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
  }) async {
    controller.changeScenario(MealScenario.cook);
    for (final option in controller.candidates.skip(3).toList()) {
      controller.excludeForSession(option.id);
    }
    controller.changeCookingCount(3);
    await mount(tester, size: size, scale: scale);
    await tap(tester, key('primary-action'));
    await tap(tester, key('draw-next-dish'));
    final outgoingId = controller.results.first.id;
    await tap(tester, key('replace-result-0'));
    await tap(tester, key('replacement-exclude'));
    expect(key('active-cooking-shortage'), findsNothing);
    await tester.ensureVisible(key('replacement-start'));
    await tester.pumpAndSettle();
    await tester.tap(key('replacement-start'));
    await tester.pump();
    expect(controller.isDrawing, isTrue);
    expect(key('active-cooking-shortage'), findsNothing);
    await tester.pumpAndSettle();
    expect(controller.results, hasLength(2));
    expect(controller.results.first.id, isNot(outgoingId));
    expect(controller.availableCount, 0);
    expect(controller.requestedCount, 3);
    expect(key('active-cooking-shortage'), findsOneWidget);
    expect(find.text('当前条件下还剩 0 道候选，无法补齐 3 道菜。'), findsOneWidget);
    expect(find.text('可以确认已选的 2 道菜，或调整条件重新开始。'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(key('draw-next-dish')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  }

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'exhausted replacement allows early save at $size and 2x text',
      (tester) async {
        await exhaustPartialBatch(tester, size: size, scale: 2);
        final ids = controller.results.map((option) => option.id).toList();
        await tester.ensureVisible(key('adjust-round-conditions'));
        await tester.pumpAndSettle();
        expect(key('adjust-round-conditions').hitTestable(), findsOneWidget);
        await confirm(tester);
        final history = await tester.runAsync(repository.history);
        expect(history, hasLength(1));
        expect(history!.single.options.map((option) => option.id), ids);
        expect(controller.requestedCount, 3);
        expect(controller.hasRound, isFalse);
        expect(key('active-cooking-shortage'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'exhausted batch adjustments preserve results until restart consent',
    (tester) async {
      await exhaustPartialBatch(tester);
      final ids = controller.results.map((option) => option.id).toList();
      final exclusions = controller.sessionExclusions;
      await tap(tester, key('adjust-round-conditions'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.results.map((option) => option.id), ids);
      await tap(tester, key('adjust-round-conditions'));
      await tap(tester, key('apply-category-filters'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.results.map((option) => option.id), ids);
      await tap(tester, key('adjust-round-conditions'));
      await tap(tester, key('filter-period-dinner'));
      await tap(tester, key('apply-category-filters'));
      expect(find.text('更换筛选条件？'), findsOneWidget);
      await tap(tester, find.text('继续这一餐'));
      expect(controller.period, MealPeriod.lunch);
      expect(controller.results.map((option) => option.id), ids);
      expect(controller.requestedCount, 3);
      expect(key('active-cooking-shortage'), findsOneWidget);
      await tap(tester, key('adjust-round-conditions'));
      await tap(tester, key('filter-period-dinner'));
      await tap(tester, key('apply-category-filters'));
      await tap(tester, find.text('应用并重新开始'));
      expect(controller.period, MealPeriod.dinner);
      expect(controller.results, isEmpty);
      expect(controller.hasRound, isFalse);
      expect(controller.requestedCount, 3);
      expect(controller.sessionExclusions, exclusions);
      expect(key('active-cooking-shortage'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ambiguous exhausted-batch save shows retry without adjustment advice',
    (tester) async {
      await exhaustPartialBatch(tester);
      final ids = controller.results.map((option) => option.id).toList();
      fault = (phase) {
        if (phase == ConfirmationPhase.beforeAcknowledgement) {
          throw StateError('lost acknowledgement');
        }
      };
      await confirm(tester);
      expect(controller.results.map((option) => option.id), ids);
      expect(find.text('重试保存'), findsOneWidget);
      expect(key('active-cooking-shortage'), findsNothing);
      expect(key('adjust-round-conditions'), findsNothing);
      fault = null;
      await confirm(tester);
      final history = await tester.runAsync(repository.history);
      expect(history, hasLength(1));
      expect(history!.single.options.map((option) => option.id), ids);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in MealScenario.values) {
    testWidgets('${scenario.name} replacement waits for explicit start', (
      tester,
    ) async {
      controller.changeScenario(scenario);
      await mount(tester);
      await tap(tester, key('primary-action'));
      final outgoing = controller.results.single;
      await tap(tester, key('replace-result-0'));
      expect(find.text('重新抽'), findsOneWidget);
      expect(find.text('排除它'), findsOneWidget);
      await tap(tester, key('replacement-exclude'));
      expect(controller.pendingReplacementIndex, 0);
      expect(controller.isDrawing, isFalse);
      expect(key('pending-replacement-0'), findsOneWidget);
      expect(find.text(outgoing.name), findsNothing);
      expect(
        tester.widget<FilledButton>(key('primary-action')).onPressed,
        isNull,
      );
      expect(key('replacement-start'), findsOneWidget);
      await tap(tester, key('replacement-start'));
      expect(controller.pendingReplacementIndex, isNull);
      expect(controller.results, hasLength(1));
      expect(controller.results.single.id, isNot(outgoing.id));
      expect(controller.sessionExclusions, contains(outgoing.id));
      expect(key('pending-replacement-0'), findsNothing);
      expect(key('replace-result-0'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('primary-action')).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in MealScenario.values) {
    testWidgets('${scenario.name} shortage keeps both choices and Back safe', (
      tester,
    ) async {
      controller.changeScenario(scenario);
      final pool = controller.candidates.toList();
      final retained = scenario == MealScenario.cook ? 2 : 1;
      for (final option in pool.skip(retained)) {
        controller.excludeForSession(option.id);
      }
      if (scenario == MealScenario.cook) controller.changeCookingCount(2);
      await mount(tester);
      await tap(tester, key('primary-action'));
      if (scenario == MealScenario.cook) {
        await tap(tester, key('draw-next-dish'));
      }
      final original = controller.results.map((option) => option.id).toList();
      final exclusions = controller.sessionExclusions;
      await tap(tester, key('replace-result-0'));
      for (final action in ['replacement-redraw', 'replacement-exclude']) {
        expect(tester.widget<TextButton>(key(action)).onPressed, isNotNull);
        await tap(tester, key(action));
        expect(key('replacement-shortage'), findsOneWidget);
        expect(controller.results.map((option) => option.id), original);
        expect(controller.pendingReplacementIndex, isNull);
        expect(controller.sessionExclusions, exclusions);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.results.map((option) => option.id), original);
      expect(controller.sessionExclusions, exclusions);
      expect(find.text('重试保存'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('放弃后，这次未确认的选择不会记入足迹。'), findsOneWidget);
      expect(find.textContaining('上次保存结果尚未确认'), findsNothing);
      await tap(tester, find.text('继续这一餐'));
      expect(controller.results.map((option) => option.id), original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending replacement survives tabs and locks partial batch', (
    tester,
  ) async {
    controller.changeScenario(MealScenario.cook);
    controller.changeCookingCount(3);
    await mount(tester);
    await tap(tester, key('primary-action'));
    await tap(tester, key('draw-next-dish'));
    final originals = controller.results.map((option) => option.id).toList();
    await tap(tester, key('replace-result-0'));
    await tap(tester, key('replacement-redraw'));
    expect(controller.pendingReplacementIndex, 0);
    expect(controller.sessionExclusions, isEmpty);
    expect(
      controller.candidates.map((option) => option.id),
      contains(originals[0]),
    );
    expect(
      controller.candidates.map((option) => option.id),
      isNot(contains(originals[1])),
    );
    expect(
      tester.widget<OutlinedButton>(key('draw-next-dish')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(key('replace-result-1')).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(key('primary-action')).onPressed,
      isNull,
    );
    await tap(tester, find.text('选项库'));
    await tap(tester, find.text('足迹'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('pending-replacement-0'), findsOneWidget);
    expect(key('replacement-start').hitTestable(), findsOneWidget);
    expect(controller.pendingReplacementIndex, 0);
    expect(controller.isDrawing, isFalse);
    await tap(tester, key('replacement-start'));
    expect(controller.results, hasLength(2));
    expect(controller.results[1].id, originals[1]);
    expect(controller.pendingReplacementIndex, isNull);
    expect(
      tester.widget<OutlinedButton>(key('draw-next-dish')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending reset and Android Back require whole-round consent', (
    tester,
  ) async {
    controller.changeScenario(MealScenario.cook);
    controller.changeCookingCount(2);
    await mount(tester);
    await tap(tester, key('primary-action'));
    await tap(tester, key('draw-next-dish'));
    final outgoing = controller.results.last;
    await tap(tester, key('replace-result-1'));
    await tap(tester, key('replacement-exclude'));
    await tap(tester, key('restart-round'));
    await tap(tester, find.text('继续这一餐'));
    expect(controller.pendingReplacementIndex, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('先放下这一餐？'), findsOneWidget);
    await tap(tester, find.text('继续这一餐'));
    expect(controller.pendingReplacementIndex, 1);
    await tap(tester, key('restart-round'));
    await tap(tester, find.text('清空并重新开始'));
    expect(controller.hasRound, isFalse);
    expect(controller.pendingReplacementIndex, isNull);
    expect(controller.results, isEmpty);
    expect(controller.sessionExclusions, contains(outgoing.id));
    expect(
      controller.candidates.map((option) => option.id),
      isNot(contains(outgoing.id)),
    );
    expect(key('replacement-start'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('full batch replacement stays reachable at $size and 2x text', (
      tester,
    ) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(10);
      await mount(tester, size: size, scale: 2);
      for (var index = 0; index < 10; index++) {
        await tap(
          tester,
          key(index == 0 ? 'primary-action' : 'draw-next-dish'),
        );
      }
      final original = controller.results.map((option) => option.id).toList();
      await tap(tester, key('replace-result-4'));
      await tap(tester, key('replacement-exclude'));
      await tester.ensureVisible(key('pending-replacement-4'));
      await tester.pumpAndSettle();
      expect(key('pending-replacement-4').hitTestable(), findsOneWidget);
      expect(key('draw-next-dish'), findsNothing);
      await tap(tester, key('replacement-start'));
      expect(controller.results, hasLength(10));
      for (var index = 0; index < 10; index++) {
        if (index == 4) continue;
        expect(controller.results[index].id, original[index]);
      }
      expect(controller.results[4].id, isNot(original[4]));
      await tester.ensureVisible(key('primary-action'));
      await tester.pumpAndSettle();
      expect(key('primary-action').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
