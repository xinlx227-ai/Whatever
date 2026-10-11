import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/card_draw.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-yesterday-ui-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 11, 12),
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

  Future<void> waitForPreferences(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isBusy) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Preference write did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  final entryFilter = find.byKey(const Key('yesterday-filter-button'));
  final sheetFilter = find.byKey(const Key('filter-yesterday'));
  final apply = find.byKey(const Key('apply-category-filters'));

  testWidgets(
    'conditions sheet pauses the unfinished card shuffle until dismissal',
    (tester) async {
      await tester.runAsync(() async {
        await controller.updatePreferences(
          const MealPreferences(mode: DrawMode.cards),
        );
        await controller.dismissCardTutorial();
      });
      await mount(tester);
      await tester.ensureVisible(find.byKey(const Key('primary-action')));
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('stage-filter-button')));
      await tester.pump();
      expect(tester.widget<CardDraw>(find.byType(CardDraw)).paused, isTrue);
      final position = find.byKey(const ValueKey('fan-position-0'));
      final before = tester.widget<Positioned>(position).left;
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Positioned>(position).left, before);
      await tester.tap(find.byTooltip('取消筛选'));
      await tester.pumpAndSettle();
      expect(tester.widget<CardDraw>(find.byType(CardDraw)).paused, isFalse);
      expect(tester.widget<Positioned>(position).left, isNot(before));
      expect(controller.hasRound, isFalse);
      expect(controller.preferences.excludeYesterday, isFalse);
    },
  );

  for (final mode in DrawMode.values) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets('$mode yesterday controls support large text at $size', (
        tester,
      ) async {
        await tester.runAsync(
          () => controller.updatePreferences(MealPreferences(mode: mode)),
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
        await tap(tester, entryFilter);
        await waitForPreferences(tester);
        expect(tester.widget<FilterChip>(entryFilter).selected, isTrue);
        expect(tester.getSize(entryFilter).height, greaterThanOrEqualTo(48));
        await tap(tester, find.byKey(const Key('category-filter-button')));
        expect(tester.widget<FilterChip>(sheetFilter).selected, isTrue);
        await tap(tester, sheetFilter);
        await tap(tester, apply);
        await waitForPreferences(tester);
        expect(controller.preferences.excludeYesterday, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$mode filter is selectable in every scenario and persists', (
      tester,
    ) async {
      await tester.runAsync(
        () => controller.updatePreferences(MealPreferences(mode: mode)),
      );
      await mount(tester);
      expect(tester.widget<FilterChip>(entryFilter).selected, isFalse);
      await tap(tester, entryFilter);
      await waitForPreferences(tester);
      for (final scenario in MealScenario.values) {
        await tap(
          tester,
          find.byKey(ValueKey('decide-scenario-${scenario.name}')),
        );
        expect(tester.widget<FilterChip>(entryFilter).selected, isTrue);
        expect(controller.scenario, scenario);
      }
      expect(
        (await tester.runAsync(repository.preferences))!.excludeYesterday,
        isTrue,
      );
      await tap(tester, entryFilter);
      await waitForPreferences(tester);
      expect(tester.widget<FilterChip>(entryFilter).selected, isFalse);
      expect(
        (await tester.runAsync(repository.preferences))!.excludeYesterday,
        isFalse,
      );
    });

    testWidgets('$mode round filter drafts require restart consent', (
      tester,
    ) async {
      await tester.runAsync(
        () => controller.updatePreferences(MealPreferences(mode: mode)),
      );
      await tester.runAsync(controller.dismissCardTutorial);
      await mount(tester);
      await tap(tester, find.byKey(const Key('primary-action')));
      if (mode == DrawMode.cards) {
        controller.selectCard(0);
        controller.startDraw();
        controller.finishDraw();
        await tester.pumpAndSettle();
      }
      final chosen = controller.result;
      expect(chosen, isNotNull);
      final stageFilter = find.byKey(const Key('stage-filter-button'));
      await tap(tester, stageFilter);
      await tap(tester, sheetFilter);
      await tap(tester, find.byTooltip('取消筛选'));
      expect(controller.result, same(chosen));
      expect(controller.preferences.excludeYesterday, isFalse);

      await tap(tester, stageFilter);
      await tap(tester, sheetFilter);
      await tap(tester, apply);
      await tap(tester, find.text('继续抽取'));
      expect(controller.result, same(chosen));
      expect(controller.preferences.excludeYesterday, isFalse);

      await tap(tester, stageFilter);
      await tap(tester, apply);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.result, same(chosen));

      await tap(tester, stageFilter);
      await tap(tester, sheetFilter);
      await tap(tester, apply);
      await tap(tester, find.text('应用并重新开始'));
      await waitForPreferences(tester);
      expect(controller.hasRound, isFalse);
      expect(controller.preferences.excludeYesterday, isTrue);
      expect(find.byKey(const Key('draw-stage')), findsNothing);
      expect(tester.widget<FilterChip>(entryFilter).selected, isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final scenario in MealScenario.values) {
      testWidgets(
        '$mode $scenario empty pool recovers by public filter action',
        (tester) async {
          controller.changeScenario(scenario);
          final pool = controller.candidates.toList();
          final inactive = pool[0];
          final excluded = pool[1];
          await tester.runAsync(() async {
            for (final option in pool) {
              await repository.confirm(
                ConfirmationOperation(
                  operationId: 'yesterday-${option.id}',
                  confirmedAt: DateTime(2026, 10, 10, 23, 59).toUtc(),
                  period: option.periods.first,
                  option: option,
                ),
              );
            }
            await controller.setOptionActive(inactive.id, false);
            await controller.updatePreferences(
              MealPreferences(mode: mode, excludeYesterday: true),
            );
          });
          controller.excludeForSession(excluded.id);
          await mount(tester);
          expect(controller.availableCount, 0);
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('primary-action')))
                .onPressed,
            isNull,
          );
          await tap(tester, find.byKey(const Key('adjust-empty-conditions')));
          await tap(tester, sheetFilter);
          await tap(tester, apply);
          await waitForPreferences(tester);
          expect(controller.availableCount, pool.length - 2);
          expect(controller.sessionExclusions, {excluded.id});
          expect(
            controller.candidates.map((option) => option.id),
            isNot(contains(inactive.id)),
          );
          expect(
            controller.candidates.map((option) => option.id),
            isNot(contains(excluded.id)),
          );
          await tap(tester, find.byKey(const Key('primary-action')));
          expect(find.byKey(const Key('draw-stage')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
