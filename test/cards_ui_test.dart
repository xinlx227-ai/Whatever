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
      clock: () => DateTime(2026, 10, 9, 12, 30),
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

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
    bool reducedMotion = true,
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
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, [int index = 0]) async {
    final locked = controller.isModeLocked;
    await tap(tester, key('candidate-card-$index'));
    expect(controller.result, isNull);
    expect(controller.isModeLocked, locked);
    await tap(tester, key('candidate-card-$index'));
    expect(controller.result, isNotNull);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(key('primary-action'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(key('primary-action'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isSaving ||
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
    'scroll preserves selection and hidden identities; blank cancels',
    (tester) async {
      await mount(tester);
      final semantics = tester.ensureSemantics();
      final ids = controller.cardDeck.map((option) => option.id).toList();
      await tap(tester, key('candidate-card-0'));
      final selected = controller.selectedCard;
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
      expect(controller.selectedCard?.id, selected!.id);
      expect(controller.cardDeck.map((option) => option.id), ids);
      expect(controller.hasRound, isFalse);
      await tap(tester, key('card-center-blank'));
      expect(controller.selectedCardIndex, isNull);
      final last = ids.length - 1;
      await tap(tester, key('candidate-card-$last'));
      expect(controller.selectedCardIndex, last);
      expect(controller.cardDeck.map((option) => option.id), ids);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'real card replacement waits for two taps and saves directly to history',
    (tester) async {
      await mount(tester);
      await reveal(tester);
      final outgoing = controller.result!;
      expect(key('central-card-face'), findsOneWidget);
      expect(key('card-fan-scroll'), findsOneWidget);
      expect(key('cooking-result-0'), findsNothing);
      await tap(tester, key('draw-mode-wheel'));
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.result?.id, outgoing.id);
      expect(find.text('这一餐已经开始，确认或重新开始后才能切换模式。'), findsOneWidget);
      await tap(tester, key('replace-result-0'));
      await tap(tester, key('replacement-exclude'));
      expect(controller.pendingReplacementIndex, 0);
      expect(controller.selectedCardIndex, isNull);
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
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.hasRound, isFalse);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      final history = await tester.runAsync(repository.history);
      expect(history!.single.option.id, replacement.id);
      await tap(tester, find.text('足迹'));
      expect(find.text(replacement.name), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back before reveal remains unstarted and mode switch cancels selection',
    (tester) async {
      await mount(tester);
      await tap(tester, key('candidate-card-0'));
      final selected = controller.selectedCard!.id;
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.selectedCard!.id, selected);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(key('draw-mode-wheel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(key('draw-mode-wheel'));
        while (controller.isBusy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.preferences.mode, DrawMode.wheel);
      expect(controller.selectedCardIndex, isNull);
      expect(controller.hasRound, isFalse);
      expect(controller.results, isEmpty);
    },
  );

  testWidgets('save failure preserves card and tutorial until retry succeeds', (
    tester,
  ) async {
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
    expect(controller.preferences.cardTutorialDismissed, isFalse);
    expect(find.text('重试保存'), findsOneWidget);
    fault = null;
    await save(tester);
    expect(controller.preferences.cardTutorialDismissed, isTrue);
    final history = await tester.runAsync(repository.history);
    expect(history, hasLength(1));
    expect(history!.single.option.id, id);
  });

  testWidgets(
    'target-many cards preserve count and offer Wheel without single-card controls',
    (tester) async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      await mount(tester);
      expect(controller.requestedCount, 3);
      expect(key('cards-target-many-notice'), findsOneWidget);
      expect(key('card-fan-scroll'), findsNothing);
      expect(key('primary-action'), findsNothing);
      await tester.ensureVisible(key('cards-use-wheel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(key('cards-use-wheel'));
        while (controller.isBusy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.preferences.mode, DrawMode.wheel);
      expect(controller.requestedCount, 3);
      expect(key('cooking-count-3'), findsOneWidget);
      expect(key('primary-action'), findsOneWidget);
    },
  );

  testWidgets(
    'selection, deck and dark shared navigation survive tab visits; skip persists',
    (tester) async {
      await mount(tester);
      await tap(tester, key('candidate-card-1'));
      final id = controller.selectedCard!.id;
      final ids = controller.cardDeck.map((option) => option.id).toList();
      await tap(tester, find.text('选项库'));
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      await tap(tester, find.text('决定'));
      expect(controller.selectedCard?.id, id);
      expect(controller.cardDeck.map((option) => option.id), ids);
      await tester.ensureVisible(key('skip-card-tutorial'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(key('skip-card-tutorial'));
        await controller.dismissCardTutorial();
      });
      await tester.pumpAndSettle();
      expect(key('skip-card-tutorial'), findsNothing);
      final reopened = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 9, 12),
      );
      await tester.runAsync(reopened.initialize);
      expect(reopened.preferences.mode, DrawMode.cards);
      expect(reopened.preferences.cardTutorialDismissed, isTrue);
      reopened.dispose();
    },
  );

  for (final replacing in [false, true]) {
    for (final destination in ['选项库', '足迹']) {
      testWidgets(
        '$destination text and blank taps preserve ${replacing ? 'replacement' : 'initial'} selection',
        (tester) async {
          await mount(tester);
          if (replacing) {
            await reveal(tester);
            await tap(tester, key('replace-result-0'));
            await tap(tester, key('replacement-redraw'));
          }
          await tap(tester, key('candidate-card-1'));
          final id = controller.selectedCard!.id;
          final ids = controller.cardDeck.map((option) => option.id).toList();
          await tap(tester, find.text(destination));
          await tap(
            tester,
            find.text(
              destination == '选项库' ? '留下喜欢的，让下一餐多一点期待。' : '确认一次选择，就会在这里留下足迹。',
            ),
          );
          expect(controller.selectedCard?.id, id);
          // The header's expanded title leaves ordinary blank space to its right.
          await tester.ensureVisible(find.text('这一餐'));
          await tester.pumpAndSettle();
          final title = tester.getRect(find.text('这一餐'));
          await tester.tapAt(Offset(title.right - 4, title.center.dy));
          await tester.pumpAndSettle();
          expect(controller.selectedCard?.id, id);
          await tap(tester, find.text('决定'));
          expect(controller.selectedCard?.id, id);
          expect(controller.cardDeck.map((option) => option.id), ids);
          expect(controller.pendingReplacementIndex, replacing ? 0 : null);
          expect(controller.hasRound, replacing);
          expect(controller.result, isNull);
          await tap(tester, key('candidate-card-1'));
          expect(controller.result?.id, id);
          expect(controller.pendingReplacementIndex, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
        final navigation = tester.getRect(find.byType(NavigationBar));
        expect(button.bottom, lessThanOrEqualTo(navigation.top));
        expect(key('primary-action').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'flip consumes once and keeps state when visiting another tab during motion',
    (tester) async {
      await mount(tester, reducedMotion: false);
      await tap(tester, key('candidate-card-0'));
      await tester.tap(key('candidate-card-0'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isDrawing, isTrue);
      expect(controller.isModeLocked, isTrue);
      await tester.tap(find.text('足迹'));
      await tester.pumpAndSettle();
      expect(controller.isDrawing, isFalse);
      expect(controller.results, hasLength(1));
      await tap(tester, find.text('决定'));
      expect(key('central-card-face'), findsOneWidget);
      expect(controller.results, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('先放下这一餐？'), findsOneWidget);
      await tap(tester, find.text('继续这一餐'));
      expect(controller.results, hasLength(1));
    },
  );
}
