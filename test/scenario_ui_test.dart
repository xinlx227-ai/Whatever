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
import 'package:whatever/presentation/option_editor.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-scenario-ui-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 7, 12, 30),
      random: Random(37),
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
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Finder scenario(String page, MealScenario value) =>
      find.byKey(ValueKey('$page-scenario-${value.name}'));

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(const Key('save-option'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(button));
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(OptionEditor).evaluate().isNotEmpty &&
        tester.widget<FilledButton>(button).onPressed == null &&
        find.byType(AlertDialog).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Restaurant editor did not finish saving');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('library remembers its own scenario without touching the round', (
    tester,
  ) async {
    await mount(tester);
    controller.startDraw();
    controller.finishDraw();
    await tester.pumpAndSettle();
    final chosen = controller.result;
    await tap(tester, find.text('选项库'));
    await tap(tester, scenario('library', MealScenario.restaurant));
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.scenario, MealScenario.eat);
    expect(controller.result, same(chosen));
    expect(find.text('肯德基'), findsOneWidget);
    expect(find.text('黄焖鸡米饭'), findsNothing);
    await tap(tester, find.text('决定'));
    expect(
      tester.widget<ChoiceChip>(scenario('decide', MealScenario.eat)).selected,
      isTrue,
    );
    expect(controller.result, same(chosen));
    await tap(tester, find.text('选项库'));
    expect(
      tester
          .widget<ChoiceChip>(scenario('library', MealScenario.restaurant))
          .selected,
      isTrue,
    );
    expect(controller.result, same(chosen));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scenario restart cancel retains result and shared meal period', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.byKey(const ValueKey('decide-period-lateNight')));
    controller.startDraw();
    controller.finishDraw();
    await tester.pumpAndSettle();
    final chosen = controller.result;
    await tap(tester, scenario('decide', MealScenario.cook));
    expect(find.text('换个场景？'), findsOneWidget);
    await tap(tester, find.text('继续这一餐'));
    expect(controller.scenario, MealScenario.eat);
    expect(controller.period, MealPeriod.lateNight);
    expect(controller.result, same(chosen));
    await tap(tester, scenario('decide', MealScenario.cook));
    await tap(tester, find.text('切换并重新开始'));
    expect(controller.scenario, MealScenario.cook);
    expect(controller.period, MealPeriod.lateNight);
    expect(controller.result, isNull);
    expect(find.text('今天，做点什么？'), findsOneWidget);
    await tap(tester, scenario('decide', MealScenario.restaurant));
    expect(controller.period, MealPeriod.lateNight);
    expect(find.text('今天，去哪儿吃？'), findsOneWidget);
    await tap(tester, scenario('decide', MealScenario.eat));
    expect(controller.period, MealPeriod.lateNight);
    expect(await tester.runAsync(repository.history), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait launch exposes the primary action above navigation', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(393, 851);
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 48);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();
    for (final value in MealScenario.values) {
      // Change the condition without scrolling; this remains the initial view.
      controller.changeScenario(value);
      await tester.pumpAndSettle();
      final navigationTop = tester.getRect(find.byType(NavigationBar)).top;
      for (final target in [
        find.byKey(const Key('primary-action')),
        find.text('一点小期待，一顿好好吃的饭'),
      ]) {
        final bounds = tester.getRect(target);
        expect(bounds.top, greaterThanOrEqualTo(48));
        expect(bounds.bottom, lessThanOrEqualTo(navigationTop));
        expect(target.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'restaurant creation saves fields and curated category to its page',
    (tester) async {
      await mount(tester);
      await tap(tester, find.text('选项库'));
      await tap(tester, scenario('library', MealScenario.restaurant));
      await tap(tester, find.byKey(const Key('create-option')));
      expect(find.text('添加喜欢的餐厅'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('option-name')), '街角小馆');
      await tester.enterText(
        find.byKey(const Key('option-address')),
        '春风路 8 号',
      );
      await tester.enterText(find.byKey(const Key('option-notes')), '周二休息');
      final category = scenarioCategories[MealScenario.restaurant]!.first;
      final dropdown = find.byKey(const Key('option-category'));
      await tap(tester, dropdown);
      await tap(tester, find.text(category).last);
      await tap(tester, find.widgetWithText(FilterChip, '晚餐'));
      await save(tester);
      expect(find.byType(OptionEditor), findsNothing);
      final restaurant = controller.options.singleWhere(
        (option) => option.name == '街角小馆',
      );
      expect(restaurant.scenario, 'restaurant');
      expect(restaurant.address, '春风路 8 号');
      expect(restaurant.notes, '周二休息');
      expect(restaurant.category, category);
      expect(restaurant.periods, {MealPeriod.lunch, MealPeriod.dinner});
      expect(controller.scenario, MealScenario.eat);
      final stored = await tester.runAsync(repository.options);
      expect(
        stored!.singleWhere((item) => item.id == restaurant.id).notes,
        '周二休息',
      );
      await tester.enterText(find.byKey(const Key('library-search')), '街角小馆');
      await tester.pumpAndSettle();
      expect(find.text('春风路 8 号'), findsOneWidget);
      expect(find.text('周二休息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'built-in restaurant fields and periods edit while category locks',
    (tester) async {
      await mount(tester);
      final original = controller.options.firstWhere(
        (option) => option.scenario == 'restaurant',
      );
      controller.startDraw();
      controller.finishDraw();
      await tap(tester, find.text('选项库'));
      await tap(tester, scenario('library', MealScenario.restaurant));
      expect(find.byKey(ValueKey('delete-${original.id}')), findsNothing);
      await tap(tester, find.byKey(ValueKey('edit-${original.id}')));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('option-category')),
            )
            .onChanged,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('option-address')), '附近门店');
      await tester.enterText(find.byKey(const Key('option-notes')), '二楼有座位');
      final dinner = find.widgetWithText(FilterChip, '晚餐');
      expect(tester.widget<FilterChip>(dinner).onSelected, isNotNull);
      final expectedPeriods = {...original.periods};
      if (!expectedPeriods.remove(MealPeriod.dinner)) {
        expectedPeriods.add(MealPeriod.dinner);
      }
      await tap(tester, dinner);
      await save(tester);
      final edited = controller.options.singleWhere(
        (food) => food.id == original.id,
      );
      expect(edited.address, '附近门店');
      expect(edited.notes, '二楼有座位');
      expect(edited.periods, expectedPeriods);
      expect(edited.categories, original.categories);
      expect(controller.result, isNull);
      expect(controller.restartNotice, isNotNull);
      expect(controller.scenario, MealScenario.eat);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restaurant duplicate preview shows the saved address and notes',
    (tester) async {
      await tester.runAsync(
        () => controller.saveOption(
          name: '街角小馆',
          scenario: 'restaurant',
          periods: {MealPeriod.lunch},
          address: '春风路 8 号',
          notes: '周二休息',
        ),
      );
      controller.startDraw();
      controller.finishDraw();
      final chosen = controller.result;
      await mount(tester);
      await tap(tester, find.text('选项库'));
      await tap(tester, scenario('library', MealScenario.restaurant));
      await tap(tester, find.byKey(const Key('create-option')));
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      await tester.enterText(find.byKey(const Key('option-name')), '街角小馆');
      await save(tester);
      expect(find.text('已有同名餐厅'), findsOneWidget);
      // The save flow awaits dialogs in the real async zone used for SQLite.
      await tester.runAsync(() async {
        await tester.tap(find.text('查看已有选项'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.text('返回表单'), findsOneWidget);
      expect(find.text('春风路 8 号'), findsOneWidget);
      expect(find.text('周二休息'), findsOneWidget);
      expect(controller.result, same(chosen));
      await tester.runAsync(() async {
        await tester.tap(find.text('返回表单'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.byType(OptionEditor), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('option-name')))
            .controller!
            .text,
        '街角小馆',
      );
      expect(controller.result, same(chosen));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cooking editor displays every curated membership as read-only', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('选项库'));
    await tap(tester, scenario('library', MealScenario.cook));
    for (final entry in {
      'cook-tomato-eggs': {'家常菜', '快手菜', '下饭菜'},
      'cook-egg-pancake': {'主食', '快手菜'},
    }.entries) {
      await tap(tester, find.byKey(ValueKey('edit-${entry.key}')));
      final memberships = find.byKey(const Key('option-category-memberships'));
      await tester.ensureVisible(memberships);
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(memberships).data!;
      for (final category in entry.value) {
        expect(text, contains(category));
      }
      expect(memberships.hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('option-category')),
            )
            .onChanged,
        isNull,
      );
      expect(
        controller.options
            .singleWhere((option) => option.id == entry.key)
            .categories,
        entry.value,
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(OptionEditor), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'scenario controls and restaurant editor at $size support large text',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await mount(tester);
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        for (final value in MealScenario.values) {
          await tap(tester, scenario('decide', value));
          expect(controller.scenario, value);
          expect(tester.takeException(), isNull);
        }
        await tap(tester, find.text('选项库'));
        for (final value in MealScenario.values) {
          await tap(tester, scenario('library', value));
          expect(tester.takeException(), isNull);
        }
        await tap(tester, find.byKey(const Key('create-option')));
        for (final target in [
          find.byKey(const Key('option-name')),
          find.byKey(const Key('option-address')),
          find.byKey(const Key('option-notes')),
          find.byKey(const Key('pick-option-image')),
          find.byKey(const Key('option-category')),
          for (final value in MealPeriod.values)
            find.widgetWithText(FilterChip, value.label),
          find.byKey(const Key('save-option')),
        ]) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(target);
          expect(
            bounds.top,
            greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
          );
          expect(bounds.bottom, lessThanOrEqualTo(size.height));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
          expect(target.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final value in [MealScenario.cook, MealScenario.restaurant]) {
    testWidgets(
      '${value.name} confirms one result with scenario history labels',
      (tester) async {
        await mount(tester);
        await tap(tester, scenario('decide', value));
        await tap(tester, find.byKey(const Key('primary-action')));
        expect(find.byKey(const Key('draw-result')), findsOneWidget);
        expect(controller.result!.scenario, value.name);
        expect(
          find.text(value == MealScenario.cook ? '就做这 1 道菜' : '就去这家'),
          findsOneWidget,
        );
        final chosen = controller.result!;
        final action = find.byKey(const Key('primary-action'));
        await tester.ensureVisible(action);
        await tester.runAsync(() => tester.tap(action));
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (controller.isSaving) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Scenario confirmation did not finish');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        await tap(tester, find.text('足迹'));
        expect(find.text(chosen.name), findsOneWidget);
        expect(find.text('12:30 · 午餐 · ${value.label}'), findsOneWidget);
        final entries = await tester.runAsync(repository.history);
        expect(entries, hasLength(1));
        expect(entries!.single.option.id, chosen.id);
        expect(entries.single.option.scenario, value.name);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
