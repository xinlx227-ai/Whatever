import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/wheel.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController model;
  bool failSave = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('first-restore-ui-');
    failSave = false;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) {
        if (failSave && phase == ConfirmationPhase.beforeAcknowledgement) {
          throw StateError('Lost acknowledgement');
        }
      },
    );
    model = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 10, 12),
      random: Random(43),
    );
    await model.initialize();
  });
  tearDown(() async {
    model.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MealApp(controller: model));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> idle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 1000 && model.isBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(model.isBusy, isFalse);
    });
    await tester.pumpAndSettle();
  }

  Future<void> browseFirstCard(WidgetTester tester) async {
    final fan = tester.widget<ListView>(key('card-fan-scroll'));
    fan.controller!.jumpTo(0);
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester) async {
    await browseFirstCard(tester);
    await tap(tester, key('candidate-card-0'));
    await tap(tester, key('candidate-card-0'));
  }

  testWidgets(
    'mode paging belongs only to entry artwork and preference persists',
    (tester) async {
      await mount(tester);
      await tester.drag(key('entry-mode-pages'), const Offset(-360, 0));
      await idle(tester);
      expect(model.preferences.mode, DrawMode.cards);
      await tester.drag(key('category-filter-button'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(model.preferences.mode, DrawMode.cards);
      await tap(tester, key('primary-action'));
      expect(find.byType(NavigationBar), findsNothing);
      expect(key('entry-mode-pages'), findsNothing);
      expect(key('draw-mode-wheel'), findsNothing);
      await tap(tester, key('draw-back'));
      expect(find.text('离开本次抽取？'), findsOneWidget);
      await tap(tester, find.text('离开'));
      expect(key('entry-mode-pages'), findsOneWidget);
      expect(model.hasRound, isFalse);
      expect(
        (await tester.runAsync(repository.preferences))!.mode,
        DrawMode.cards,
      );
    },
  );

  testWidgets('wheel pauses in exit dialog and background without resampling', (
    tester,
  ) async {
    await mount(tester);
    await tester.ensureVisible(key('primary-action'));
    await tester.tap(key('primary-action'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final sampled = model.candidates[model.selectedIndex!].id;
    final sizeBeforeDialog = tester.getSize(find.byType(MealWheel));
    await tester.tap(key('draw-back'));
    await tester.pumpAndSettle();
    final angle = tester.widget<MealWheel>(find.byType(MealWheel)).angle;
    final size = tester.getSize(find.byType(MealWheel));
    expect(size, sizeBeforeDialog);
    await tester.pump(const Duration(seconds: 5));
    expect(model.isDrawing, isTrue);
    expect(model.results, isEmpty);
    expect(tester.widget<MealWheel>(find.byType(MealWheel)).angle, angle);
    expect(tester.getSize(find.byType(MealWheel)), size);
    await tester.tap(find.text('继续抽取'));
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedAngle = tester.widget<MealWheel>(find.byType(MealWheel)).angle;
    await tester.pump(const Duration(seconds: 10));
    expect(model.isDrawing, isTrue);
    expect(tester.widget<MealWheel>(find.byType(MealWheel)).angle, pausedAngle);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(model.results.single.id, sampled);
    expect(tester.takeException(), isNull);
  });

  for (final mode in DrawMode.values) {
    testWidgets(
      'entry remount restores the $mode artwork after mode switching',
      (tester) async {
        await mount(tester);
        final previousMode = mode == DrawMode.wheel
            ? DrawMode.cards
            : DrawMode.wheel;
        for (final selection in [previousMode, mode]) {
          await tester.ensureVisible(key('draw-mode-${selection.name}'));
          await tester.runAsync(
            () => tester.tap(key('draw-mode-${selection.name}')),
          );
          await idle(tester);
        }
        expect(model.preferences.mode, mode);
        expect(
          tester.widget<PageView>(key('entry-mode-pages')).controller!.page,
          mode == DrawMode.wheel ? 0 : 1,
        );
        await tester.ensureVisible(key('primary-action'));
        await tester.tap(key('primary-action'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(key('draw-stage'), findsOneWidget);
        if (mode == DrawMode.wheel) expect(model.isDrawing, isTrue);
        await tester.tap(key('draw-back'));
        await tester.pumpAndSettle();
        await tap(tester, find.text('离开'));
        expect(model.hasRound, isFalse);
        expect(model.preferences.mode, mode);
        expect(
          tester.widget<PageView>(key('entry-mode-pages')).controller!.page,
          mode == DrawMode.wheel ? 0 : 1,
        );
        expect((await tester.runAsync(repository.preferences))!.mode, mode);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wheel shrink also pauses and reduced motion never rotates between frames',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(key('primary-action'));
      await tester.tap(key('primary-action'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 40));
      expect(model.results, hasLength(1));
      final sizeBeforeDialog = tester.getSize(find.byType(MealWheel));
      await tester.tap(key('draw-back'));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(MealWheel));
      expect(size, sizeBeforeDialog);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getSize(find.byType(MealWheel)), size);
      await tap(tester, find.text('离开'));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.ensureVisible(key('primary-action'));
      await tester.tap(key('primary-action'));
      await tester.pump();
      final angle = tester.widget<MealWheel>(find.byType(MealWheel)).angle;
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<MealWheel>(find.byType(MealWheel)).angle, angle);
      await tester.pumpAndSettle();
      expect(tester.widget<MealWheel>(find.byType(MealWheel)).angle, angle);
      expect(model.results, hasLength(1));
    },
  );

  for (final mode in DrawMode.values) {
    testWidgets(
      '$mode pending decision pauses reveal; reduced meal retries exactly once',
      (tester) async {
        model.changeScenario(MealScenario.cook);
        model.changeCookingCount(3);
        await tester.runAsync(
          () => model.updatePreferences(model.preferences.copyWith(mode: mode)),
        );
        await mount(tester);
        await tap(tester, key('primary-action'));
        if (mode == DrawMode.cards) {
          await reveal(tester);
          model.collectCard();
          await tester.pumpAndSettle();
          await reveal(tester);
          model.collectCard();
          model.focusResult(1);
          await tester.pumpAndSettle();
        } else {
          await tap(tester, key('draw-next-dish'));
        }
        final retained = model.results.first.id;
        final outgoing = model.results.last.id;
        await tap(tester, key('replace-result-1'));
        await tester.ensureVisible(key('replacement-exclude'));
        await tester.tap(key('replacement-exclude'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(model.results.map((e) => e.id), [retained]);
        expect(model.sessionExclusions, contains(outgoing));
        expect(key('replacement-start'), findsNothing);
        if (mode == DrawMode.cards) {
          await tester.pumpAndSettle();
          await browseFirstCard(tester);
          await tap(tester, key('candidate-card-0'));
          await tester.tap(key('candidate-card-0'));
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(model.isDrawing, isTrue);
        // Scroll immediately; settling before opening the decision would finish it.
        await tester.ensureVisible(key('primary-action'));
        await tester.pump();
        await tester.runAsync(() => tester.tap(key('primary-action')));
        await tester.pumpAndSettle();
        expect(find.text('正在替换一道菜，要继续抽取，还是直接确认已有的 1 道菜？'), findsOneWidget);
        final selected = model.selectedIndex;
        await tester.pump(const Duration(seconds: 5));
        expect(model.isDrawing, isTrue);
        expect(model.selectedIndex, selected);
        failSave = true;
        await tester.runAsync(() => tester.tap(find.text('确认这 1 道菜')));
        await tester.pump();
        await idle(tester);
        expect(model.hasPendingReplacement, isFalse);
        expect(model.isDrawing, isFalse);
        expect(model.results.map((e) => e.id), [retained]);
        expect(find.text('重试保存'), findsOneWidget);
        failSave = false;
        await tester.ensureVisible(key('primary-action'));
        await tester.runAsync(() => tester.tap(key('primary-action')));
        await tester.pump();
        await idle(tester);
        expect(key('draw-stage'), findsNothing);
        final records = await tester.runAsync(repository.history);
        expect(records, hasLength(1));
        expect(records!.single.options.map((e) => e.id), [retained]);
        expect(model.cookingCount, 3);
        expect(model.sessionExclusions, contains(outgoing));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
