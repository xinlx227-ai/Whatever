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
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  ConfirmationFault? fault;

  setUp(() async {
    fault = null;
    directory = await Directory.systemTemp.createTemp('whatever-cards-ui-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 10, 12, 30),
      random: Random(39),
    );
    await controller.initialize();
    await controller.updatePreferences(
      controller.preferences.copyWith(mode: DrawMode.cards),
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
    bool reducedMotion = true,
    bool settleStage = true,
    bool enterStage = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reducedMotion);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
    if (enterStage) {
      await tester.ensureVisible(key('primary-action'));
      await tester.pumpAndSettle();
      await tester.tap(key('primary-action'));
      await tester.pump();
      if (settleStage) await tester.pumpAndSettle();
      expect(key('draw-stage'), findsOneWidget);
    }
  }

  Future<void> reveal(WidgetTester tester, [int index = 0]) async {
    await tap(tester, key('candidate-card-$index'));
    expect(controller.cardCentralResult, isNull);
    expect(controller.selectedCardIndex, index);
    await tap(tester, key('candidate-card-$index'));
    expect(controller.cardCentralResult, isNotNull);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(key('primary-action'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(key('primary-action'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isBusy ||
          (controller.error == null &&
              !controller.preferences.cardTutorialDismissed)) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Card save did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all hidden cards remain reachable; browsing preserves selection',
    (tester) async {
      await mount(tester);
      final semantics = tester.ensureSemantics();
      final ids = controller.cardDeck.map((option) => option.id).toList();
      await tap(tester, key('candidate-card-0'));
      final selected = controller.selectedCard!.id;
      expect(
        tester.getSemantics(key('candidate-card-0')).label,
        contains('第 1 张牌'),
      );
      for (final option in controller.cardDeck) {
        expect(find.text(option.name), findsNothing);
        expect(
          tester.getSemantics(key('candidate-card-0')).label,
          isNot(contains(option.name)),
        );
      }
      await tester.drag(key('card-fan-scroll'), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(controller.selectedCard?.id, selected);
      expect(controller.cardDeck.map((option) => option.id), ids);
      await tap(tester, key('card-center-blank'));
      expect(controller.selectedCardIndex, isNull);
      for (var index = 0; index < ids.length; index++) {
        await tap(tester, key('candidate-card-$index'));
        expect(controller.selectedCard?.id, ids[index]);
      }
      expect(controller.results, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('stage hides mode/settings/navigation even before first flip', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(key('draw-mode-wheel'), findsNothing);
    expect(key('entry-mode-pages'), findsNothing);
    await tap(tester, key('candidate-card-0'));
    final id = controller.selectedCard!.id;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('离开本次抽取？'), findsOneWidget);
    await tap(tester, find.text('继续抽取'));
    expect(controller.selectedCard!.id, id);
    await tap(tester, key('draw-back'));
    await tap(tester, find.text('离开'));
    expect(key('draw-stage'), findsNothing);
    expect(controller.results, isEmpty);
    expect(controller.selectedCardIndex, isNull);
    expect(controller.preferences.mode, DrawMode.cards);
  });

  testWidgets(
    'replacement removes outgoing and waits for manual two-tap reveal',
    (tester) async {
      await mount(tester);
      await reveal(tester);
      final outgoing = controller.result!;
      expect(key('central-card-face'), findsOneWidget);
      expect(key('collected-card-scroll'), findsNothing);
      await tap(tester, key('replace-result-0'));
      await tap(tester, key('replacement-exclude'));
      expect(controller.hasPendingReplacement, isTrue);
      expect(controller.results, isEmpty);
      expect(controller.result, isNull);
      expect(controller.isDrawing, isFalse);
      expect(
        controller.cardDeck.any((option) => option.id == outgoing.id),
        isFalse,
      );
      expect(key('primary-action'), findsNothing);
      await reveal(tester);
      final replacement = controller.result!;
      expect(replacement.id, isNot(outgoing.id));
      await save(tester);
      expect(key('draw-stage'), findsNothing);
      expect(controller.hasRound, isFalse);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      final history = await tester.runAsync(repository.history);
      expect(history!.single.option.id, replacement.id);
      await tap(tester, find.text('足迹'));
      expect(find.text(replacement.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-target center collects, row reopens, next draw does not shuffle',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester, reducedMotion: false);
      final revision = controller.cardDeckShuffleRevision;
      await reveal(tester);
      final first = controller.cardCentralResult!;
      expect(key('collected-card-0'), findsNothing);
      expect(find.text('点击大卡，收入本餐'), findsOneWidget);
      await tap(tester, key('collect-central-card'));
      expect(controller.cardCentralResult, isNull);
      expect(key('collected-card-0'), findsOneWidget);
      expect(find.text('正在洗牌…'), findsNothing);
      expect(controller.cardDeckShuffleRevision, revision);
      await tap(tester, key('collected-card-0'));
      expect(controller.cardCentralResult!.id, first.id);
      expect(key('collected-card-0'), findsOneWidget);
      await tap(tester, key('collect-central-card'));
      await reveal(tester);
      expect(controller.cardCentralResult!.id, isNot(first.id));
      expect(controller.results, hasLength(2));
      // A revealed central result is valid even before collection.
      await save(tester);
      final history = await tester.runAsync(repository.history);
      expect(history!.single.options, hasLength(2));
      expect(history.single.options.first.id, first.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial shuffle ignores taps and exit dialog pauses/resumes same progress',
    (tester) async {
      await mount(tester, reducedMotion: false, settleStage: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在洗牌…'), findsOneWidget);
      await tester.tap(key('candidate-card-0'), warnIfMissed: false);
      expect(controller.selectedCardIndex, isNull);
      await tester.tap(key('draw-back'));
      await tester.pumpAndSettle();
      final before = tester.widget<Positioned>(key('fan-position-0'));
      final ids = controller.cardDeck.map((option) => option.id).toList();
      await tester.pump(const Duration(seconds: 3));
      final after = tester.widget<Positioned>(key('fan-position-0'));
      expect(after.left, before.left);
      expect(after.top, before.top);
      await tester.tap(find.text('继续抽取'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final resumed = tester.widget<Positioned>(key('fan-position-0'));
      expect(resumed.left, isNot(before.left));
      expect(controller.cardDeck.map((option) => option.id), ids);
      await tester.pumpAndSettle();
      expect(find.text('正在洗牌…'), findsNothing);
      await reveal(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collection travels to row, blocks next taps, and resumes after background pause',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester, reducedMotion: false);
      await reveal(tester);
      final id = controller.result!.id;
      await tester.ensureVisible(key('collect-central-card'));
      await tester.pumpAndSettle();
      await tester.tap(key('collect-central-card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(key('collecting-card-position'), findsOneWidget);
      final moving = tester.widget<Positioned>(key('collecting-card-position'));
      final scale = tester.widget<Transform>(key('collecting-card-scale'));
      expect(moving.top, greaterThan(0));
      expect(scale.transform.entry(0, 0), lessThan(1));
      expect(controller.canConfirm, isTrue);
      expect(controller.results.single.id, id);
      expect(tester.widget<InkWell>(key('candidate-card-0')).onTap, isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final stopped = tester.widget<Positioned>(
        key('collecting-card-position'),
      );
      final stoppedScale = tester.widget<Transform>(
        key('collecting-card-scale'),
      );
      await tester.pump(const Duration(seconds: 3));
      final afterPause = tester.widget<Positioned>(
        key('collecting-card-position'),
      );
      expect(afterPause.left, stopped.left);
      expect(afterPause.top, stopped.top);
      expect(
        tester.widget<Transform>(key('collecting-card-scale')).transform,
        stoppedScale.transform,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.widget<Positioned>(key('collecting-card-position')).top,
        greaterThan(stopped.top!),
      );
      await tester.pumpAndSettle();
      expect(key('collecting-card-position'), findsNothing);
      expect(key('collected-card-0'), findsOneWidget);
      expect(controller.collectedResults.single.id, id);
      expect(tester.widget<InkWell>(key('candidate-card-0')).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving during collection cancels motion without adding another result',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester, reducedMotion: false);
      await reveal(tester);
      final id = controller.result!.id;
      await tester.ensureVisible(key('collect-central-card'));
      await tester.pumpAndSettle();
      await tester.tap(key('collect-central-card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(key('collecting-card-position'), findsOneWidget);
      await tester.ensureVisible(key('primary-action'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(key('primary-action'));
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (controller.isBusy ||
            controller.hasRound ||
            !controller.preferences.cardCollectionTutorialDismissed) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Save during collection did not finish');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(key('draw-stage'), findsNothing);
      expect(key('collecting-card-position'), findsNothing);
      expect(controller.results, isEmpty);
      final history = await tester.runAsync(repository.history);
      expect(history, hasLength(1));
      expect(history!.single.options.single.id, id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'round reset cancels collection without re-adding the old result',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester, reducedMotion: false);
      await reveal(tester);
      await tester.ensureVisible(key('collect-central-card'));
      await tester.pumpAndSettle();
      await tester.tap(key('collect-central-card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(key('collecting-card-position'), findsOneWidget);
      controller.abandon();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(key('collecting-card-position'), findsNothing);
      expect(controller.results, isEmpty);
      expect(controller.collectedResults, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first multi-card collection guidance survives completed basic tutorial',
    (tester) async {
      await tester.runAsync(controller.dismissCardTutorial);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      expect(controller.preferences.cardCollectionTutorialDismissed, isFalse);
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester);
      await reveal(tester);
      expect(find.text('点击大卡，收入本餐'), findsOneWidget);
      await tester.ensureVisible(key('collect-central-card'));
      await tester.pumpAndSettle();
      await tester.tap(key('collect-central-card'));
      await tester.pump();
      expect(key('collecting-card-position'), findsNothing);
      expect(controller.cardCentralResult, isNull);
      expect(key('collected-card-0'), findsOneWidget);
      expect(tester.widget<InkWell>(key('candidate-card-0')).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failure retains central card and tutorial until retry succeeds',
    (tester) async {
      await mount(tester);
      await reveal(tester);
      final id = controller.result!.id;
      fault = (phase) {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          throw StateError('save failure');
        }
      };
      await save(tester);
      expect(controller.result!.id, id);
      expect(key('draw-stage'), findsOneWidget);
      expect(controller.preferences.cardTutorialDismissed, isFalse);
      expect(find.text('重试保存'), findsOneWidget);
      fault = null;
      await save(tester);
      expect(key('draw-stage'), findsNothing);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      final history = await tester.runAsync(repository.history);
      expect(history, hasLength(1));
      expect(history!.single.option.id, id);
    },
  );

  testWidgets('skip persists and later entries omit tutorial', (tester) async {
    await mount(tester);
    await tester.ensureVisible(key('skip-card-tutorial'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(key('skip-card-tutorial'));
      await controller.dismissCardTutorial();
    });
    await tester.pumpAndSettle();
    expect(key('skip-card-tutorial'), findsNothing);
    expect(key('card-guidance'), findsNothing);
    final reopened = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 10, 12),
    );
    await tester.runAsync(reopened.initialize);
    expect(reopened.preferences.cardTutorialDismissed, isTrue);
    reopened.dispose();
  });

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets(
      'full names and confirmation scroll safely at $size and 2x text',
      (tester) async {
        const name = '家里慢慢炖的一大锅番茄土豆胡萝卜牛肉';
        await tester.runAsync(
          () => controller.saveOption(name: name, periods: {MealPeriod.lunch}),
        );
        for (final option
            in controller.candidates
                .where((option) => option.name != name)
                .toList()) {
          controller.excludeForSession(option.id);
        }
        await mount(tester, size: size, scale: 2);
        await reveal(tester);
        expect(find.text(name), findsOneWidget);
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        final button = tester.getRect(key('primary-action'));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        expect(key('primary-action').hitTestable(), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'flip stays hidden until reveal and background pauses without resampling',
    (tester) async {
      await mount(tester, reducedMotion: false);
      await tap(tester, key('candidate-card-0'));
      final id = controller.selectedCard!.id;
      await tester.tap(key('candidate-card-0'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isDrawing, isTrue);
      expect(find.text(controller.selectedCard!.name), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(controller.isDrawing, isTrue);
      expect(controller.selectedCard!.id, id);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.results.single.id, id);
      expect(key('central-card-face'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
