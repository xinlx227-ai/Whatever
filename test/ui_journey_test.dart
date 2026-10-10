import 'dart:async';
import 'dart:io';
import 'dart:math';

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
  late String databasePath;
  late MealRepository repository;
  late MealController controller;
  ConfirmationFault? fault;

  Future<void> open() async {
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 6, 12, 30),
      random: Random(37),
    );
    await controller.initialize();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-ui-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    fault = null;
    await open();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  final primary = find.byKey(const Key('primary-action'));
  final result = find.byKey(const Key('draw-result'));

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> tapPrimary(WidgetTester tester) async {
    await tester.ensureVisible(primary);
    await tester.pumpAndSettle();
    if (controller.result == null) {
      await tester.tap(primary);
    } else {
      // Start real database work in the real async zone, keeping animation
      // gestures in the simulated frame clock.
      await tester.runAsync(() => tester.tap(primary));
    }
    await tester.pump();
  }

  Future<String> draw(WidgetTester tester) async {
    await tapPrimary(tester);
    await tester.pumpAndSettle();
    expect(result, findsOneWidget);
    return tester.widget<Text>(result).data!;
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> saveFinished(WidgetTester tester) async {
    // Real SQLite runs outside the widget test's simulated clock.
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isSaving) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('SQLite confirmation did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  Future<void> expectStored(WidgetTester tester, int count) async {
    final entries = await tester.runAsync(repository.history);
    expect(entries, hasLength(count));
  }

  testWidgets(
    'one spin reveals once and explicit confirmation survives reopening',
    (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      expect(find.text('午餐 · 吃什么'), findsOneWidget);

      await tester.ensureVisible(primary);
      await tester.tap(primary);
      await tester.tap(primary);
      await tester.pump();
      expect(find.byKey(const Key('draw-stage')), findsOneWidget);
      expect(primary, findsNothing);
      expect(result, findsNothing);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(result, findsNothing);
      expect(haptics, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final selected = tester.widget<Text>(result).data!;
      expect(
        controller.candidates.map((food) => food.name),
        contains(selected),
      );
      expect(haptics, hasLength(1));
      expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');
      await expectStored(tester, 0);

      await tapPrimary(tester);
      await saveFinished(tester);
      expect(result, findsNothing);
      expect(find.text('这一餐已记入足迹，好好享用吧'), findsOneWidget);
      await tab(tester, '足迹');
      expect(find.text(selected), findsOneWidget);
      await expectStored(tester, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        controller.dispose();
        await repository.close();
        await open();
      });
      await tester.pumpWidget(MealApp(controller: controller));
      await tester.pumpAndSettle();
      expect(result, findsNothing);
      await tab(tester, '足迹');
      expect(find.text(selected), findsOneWidget);
      await expectStored(tester, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving disables another confirmation until durable success', (
    tester,
  ) async {
    late Completer<void> entered;
    late Completer<void> release;
    await tester.runAsync(() async {
      entered = Completer<void>();
      release = Completer<void>();
    });
    fault = (phase) async {
      if (phase == ConfirmationPhase.afterHeaderWritten) {
        entered.complete();
        await release.future;
      }
    };
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await mount(tester);
    final selected = await draw(tester);
    await tapPrimary(tester);
    await tester.runAsync(
      () => entered.future.timeout(const Duration(seconds: 10)),
    );
    await tester.pump();
    expect(find.text('正在记下这一餐…'), findsOneWidget);
    expect(tester.widget<FilledButton>(primary).onPressed, isNull);
    await tester.tap(primary);
    await tester.pump();
    expect(tester.widget<Text>(result).data, selected);
    release.complete();
    await saveFinished(tester);
    await expectStored(tester, 1);
    await tab(tester, '足迹');
    expect(find.text(selected), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed save keeps the visible result and offers explicit retry',
    (tester) async {
      var failOnce = true;
      fault = (phase) {
        if (phase == ConfirmationPhase.afterHeaderWritten && failOnce) {
          failOnce = false;
          throw StateError('Injected write failure');
        }
      };
      await mount(tester);
      final selected = await draw(tester);
      await tapPrimary(tester);
      await saveFinished(tester);
      expect(tester.widget<Text>(result).data, selected);
      expect(find.text('暂时无法确认保存结果，请重试，不会重复记录。'), findsOneWidget);
      expect(find.text('重试保存'), findsOneWidget);
      await expectStored(tester, 0);
      await tapPrimary(tester);
      await saveFinished(tester);
      expect(result, findsNothing);
      await tab(tester, '足迹');
      expect(find.text(selected), findsOneWidget);
      await expectStored(tester, 1);
    },
  );

  testWidgets('full-screen draw hides tabs and settings until explicit leave', (
    tester,
  ) async {
    await mount(tester);
    final selected = await draw(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('category-filter-button')), findsNothing);
    expect(find.byKey(const Key('draw-mode-cards')), findsNothing);
    await tester.tap(find.byKey(const Key('draw-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续抽取'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(result).data, selected);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('离开'));
    await tester.pumpAndSettle();
    expect(controller.hasRound, isFalse);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tab(tester, '选项库');
    expect(find.text('豆奶'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tab(tester, '足迹');
    expect(find.text('第一餐，值得期待'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    await expectStored(tester, 0);
  });

  testWidgets(
    'restart keeps entry settings and waits for another manual draw',
    (tester) async {
      await mount(tester);
      final selected = await draw(tester);
      expect(find.widgetWithText(ChoiceChip, '晚餐'), findsNothing);
      await tester.tap(find.byKey(const Key('restart-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续抽取'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(result).data, selected);
      await tester.tap(find.byKey(const Key('restart-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空并重新开始'));
      await tester.pumpAndSettle();
      expect(controller.period, MealPeriod.lunch);
      expect(controller.hasRound, isFalse);
      expect(find.byKey(const Key('draw-stage')), findsNothing);
      final dinner = find.widgetWithText(ChoiceChip, '晚餐');
      await tester.ensureVisible(dinner);
      await tester.tap(dinner);
      await tester.pumpAndSettle();
      expect(controller.period, MealPeriod.dinner);
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, findsNothing);
      await expectStored(tester, 0);
    },
  );

  testWidgets('abandoning an active spin cancels its eventual reveal', (
    tester,
  ) async {
    await mount(tester);
    await tapPrimary(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('离开'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(result, findsNothing);
    expect(find.text('转一下，开饭'), findsOneWidget);
    await expectStored(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back dismisses the transient prompt before touching the round', (
    tester,
  ) async {
    await mount(tester);
    final selected = await draw(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<Text>(result).data, selected);
    expect(controller.isModeLocked, isTrue);
  });

  testWidgets(
    'lifecycle pause and resume preserve animation choice and manual period',
    (tester) async {
      await mount(tester);
      await tapPrimary(tester);
      await tester.pump(const Duration(milliseconds: 500));
      final selectedIndex = controller.selectedIndex;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.selectedIndex, selectedIndex);
      expect(controller.period, MealPeriod.lunch);
      expect(result, findsOneWidget);
      await expectStored(tester, 0);
    },
  );

  testWidgets('saved library changes cancel an active full-screen draw', (
    tester,
  ) async {
    await mount(tester);
    await tapPrimary(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('选项库'), findsNothing);
    await tester.runAsync(() => controller.applyDataChange(changed: true));
    await tester.pumpAndSettle();
    expect(find.text('选项或足迹已更新，这一轮已重置，请重新选择。'), findsOneWidget);
    expect(find.byKey(const Key('draw-stage')), findsNothing);
    expect(result, findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(result, findsNothing);
    await expectStored(tester, 0);
  });

  testWidgets(
    'system reduced motion reveals promptly with the same save flow',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mount(tester);
      await tapPrimary(tester);
      expect(result, findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(result, findsOneWidget);
      final selected = tester.widget<Text>(result).data!;
      await expectStored(tester, 0);
      await tapPrimary(tester);
      await saveFinished(tester);
      await tab(tester, '足迹');
      expect(find.text(selected), findsOneWidget);
      await expectStored(tester, 1);
    },
  );

  testWidgets('phone reveal and resume keep result and confirmation visible', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(393, 851);
    tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();
    final selected = await draw(tester);
    void expectCompletionVisible() {
      for (final target in [result, primary]) {
        final bounds = tester.getRect(target);
        expect(bounds.top, greaterThanOrEqualTo(24));
        expect(bounds.bottom, lessThanOrEqualTo(827));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(393));
        expect(target.hitTestable(), findsOneWidget);
      }
    }

    expectCompletionVisible();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续抽取'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(result).data, selected);
    expectCompletionVisible();
    await expectStored(tester, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'large text at $size keeps actions reachable without overflow',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await mount(tester);
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final selected = await draw(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(result);
        await tester.pumpAndSettle();
        expect(result.hitTestable(), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        await tester.tap(find.byKey(const Key('draw-back')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('继续抽取'));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(result).data, selected);
        await tapPrimary(tester);
        await saveFinished(tester);
        await tab(tester, '足迹');
        await tester.ensureVisible(find.text(selected));
        await tester.pumpAndSettle();
        expect(find.text(selected).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectStored(tester, 1);
      },
    );
  }
}
