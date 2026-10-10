import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/option_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android scenarios, independent browsing, restaurant edits and durable history',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'scenario-android-',
      );
      final path = '${directory.path}/journey.sqlite';
      var repository = await MealRepository.open(
        factory: databaseFactory,
        path: path,
      );
      var controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 7, 12),
      );
      await controller.initialize();
      await tester.pumpWidget(MealApp(controller: controller));
      await tester.pumpAndSettle();

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> waitFor(bool Function() complete) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!complete()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native action did not complete');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      Finder scenario(String page, MealScenario value) =>
          find.byKey(ValueKey('$page-scenario-${value.name}'));
      final action = find.byKey(const Key('primary-action'));
      await tap(find.byKey(const ValueKey('decide-period-lateNight')));
      await tap(find.text('选项库'));
      await tap(scenario('library', MealScenario.restaurant));
      expect(controller.scenario, MealScenario.eat);
      await tap(find.text('决定'));
      await tap(action);
      final original = controller.result;
      expect(find.byType(NavigationBar), findsNothing);
      expect(scenario('decide', MealScenario.cook), findsNothing);
      await tap(find.byKey(const Key('draw-back')));
      await tap(find.text('继续抽取'));
      expect(controller.scenario, MealScenario.eat);
      expect(controller.result, same(original));
      expect(controller.period, MealPeriod.lateNight);
      await tap(action);
      await waitFor(() => controller.history.length == 1 && !controller.isBusy);

      for (final value in [MealScenario.cook, MealScenario.restaurant]) {
        await tap(scenario('decide', value));
        expect(controller.period, MealPeriod.lateNight);
        await tap(action);
        expect(controller.result!.scenario, value.name);
        expect(controller.result!.periods, contains(MealPeriod.lateNight));
        final count = controller.history.length;
        await tap(action);
        await waitFor(
          () => controller.history.length == count + 1 && !controller.isBusy,
        );
      }

      await tap(find.text('选项库'));
      expect(
        tester
            .widget<ChoiceChip>(scenario('library', MealScenario.restaurant))
            .selected,
        isTrue,
      );
      await tap(find.byKey(const Key('create-option')));
      await tester.enterText(find.byKey(const Key('option-name')), 'S04街角餐厅');
      await tester.enterText(
        find.byKey(const Key('option-address')),
        '测试路 12 号',
      );
      await tester.enterText(
        find.byKey(const Key('option-notes')),
        '先电话确认营业时间',
      );
      await tap(find.widgetWithText(FilterChip, '夜宵'));
      await tap(find.byKey(const Key('save-option')));
      await waitFor(
        () =>
            find.byType(OptionEditor).evaluate().isEmpty && !controller.isBusy,
      );
      final custom = controller.options.singleWhere(
        (option) => option.name == 'S04街角餐厅',
      );
      expect(custom.periods, {MealPeriod.lunch, MealPeriod.lateNight});
      expect(custom.address, '测试路 12 号');
      expect(custom.notes, '先电话确认营业时间');
      for (final option in controller.libraryOptions(scenario: 'restaurant')) {
        if (option.id != custom.id) {
          await controller.setOptionActive(option.id, false);
        }
      }
      await tester.pumpAndSettle();
      await tap(find.text('决定'));
      await tap(action);
      expect(controller.result!.id, custom.id);
      await tap(action);
      await waitFor(() => controller.history.length == 4 && !controller.isBusy);
      await tap(find.text('足迹'));
      expect(find.text(custom.name), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactory,
        path: path,
      );
      controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 7, 6),
      );
      await controller.initialize();
      expect(controller.scenario, MealScenario.eat);
      expect(controller.period, MealPeriod.breakfast);
      expect(controller.hasRound, isFalse);
      expect(controller.history, hasLength(4));
      expect(controller.history.map((entry) => entry.option.scenario).toSet(), {
        'eat',
        'cook',
        'restaurant',
      });
      final restored = controller.options.singleWhere(
        (option) => option.id == custom.id,
      );
      expect(restored.address, custom.address);
      expect(restored.notes, custom.notes);
      expect(restored.periods, custom.periods);
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
