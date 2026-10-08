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
import 'package:whatever/presentation/category_manager.dart';
import 'package:whatever/presentation/option_editor.dart';
import 'package:whatever/presentation/option_library.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-category-ui-');
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

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(430, 932),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> settleWrite(WidgetTester tester) async {
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (controller.isBusy) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Category write did not finish');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> saveCategory(WidgetTester tester) async {
    await tap(tester, find.byKey(const Key('save-category')));
    await settleWrite(tester);
  }

  void draw() {
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    expect(controller.hasRound, isTrue);
  }

  testWidgets('library entry scopes management but creation defaults to eat', (
    tester,
  ) async {
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: OptionLibrary(
            controller: controller,
            scenario: MealScenario.restaurant,
          ),
        ),
      ),
    );
    await tap(tester, find.byKey(const Key('manage-categories')));
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('categories-scenario-restaurant')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('火锅'), findsOneWidget);
    expect(find.text('家常菜'), findsNothing);
    await tap(tester, find.byKey(const Key('create-category')));
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('category-editor-scenario-eat')),
          )
          .selected,
      isTrue,
    );
    await tester.enterText(find.byKey(const Key('category-name')), '周末想吃的');
    await saveCategory(tester);
    expect(
      controller.categoriesFor(MealScenario.eat).map((value) => value.name),
      contains('周末想吃的'),
    );
    expect(
      controller
          .categoriesFor(MealScenario.restaurant)
          .map((value) => value.name),
      isNot(contains('周末想吃的')),
    );
    expect(find.text('周末想吃的'), findsNothing);
    await tap(tester, find.byKey(const Key('create-category')));
    await tap(tester, find.byKey(const Key('category-editor-scenario-cook')));
    await tester.enterText(find.byKey(const Key('category-name')), '周末想做的');
    await saveCategory(tester);
    expect(
      controller.categoriesFor(MealScenario.cook).map((value) => value.name),
      contains('周末想做的'),
    );
  });

  testWidgets(
    'built-ins and fallback can rename; canceled edits and no-op preserve round',
    (tester) async {
      final builtin = controller
          .categoriesFor(MealScenario.restaurant)
          .firstWhere((value) => !value.isFallback);
      final fallback = controller.fallbackCategory(MealScenario.restaurant);
      draw();
      final resultId = controller.result!.id;
      await mount(
        tester,
        CategoryManager(
          controller: controller,
          scenario: MealScenario.restaurant,
        ),
      );
      expect(
        find.byKey(ValueKey('delete-category-${builtin.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('delete-category-${fallback.id}')),
        findsNothing,
      );
      await tap(tester, find.byKey(ValueKey('rename-category-${builtin.id}')));
      expect(
        find.byKey(const Key('category-editor-scenario-eat')),
        findsNothing,
      );
      await tester.enterText(find.byKey(const Key('category-name')), '热热闹闹');
      await tap(tester, find.byTooltip('返回'));
      await tap(tester, find.text('取消'));
      expect(find.byKey(const Key('category-name')), findsOneWidget);
      await tap(tester, find.byTooltip('返回'));
      await tap(tester, find.text('放弃修改'));
      expect(controller.result!.id, resultId);
      expect(
        controller
            .categoriesFor(MealScenario.restaurant)
            .firstWhere((value) => value.id == builtin.id)
            .name,
        builtin.name,
      );
      await tap(tester, find.byKey(ValueKey('rename-category-${builtin.id}')));
      await saveCategory(tester);
      expect(controller.result!.id, resultId);
      await tap(tester, find.byKey(ValueKey('rename-category-${builtin.id}')));
      await tester.enterText(find.byKey(const Key('category-name')), '热热闹闹');
      await saveCategory(tester);
      expect(find.text('热热闹闹'), findsOneWidget);
      expect(controller.hasRound, isFalse);
      expect(
        controller.categoriesFor(MealScenario.eat).map((value) => value.name),
        isNot(contains('热热闹闹')),
      );
      await tap(tester, find.byKey(ValueKey('rename-category-${fallback.id}')));
      await tester.enterText(find.byKey(const Key('category-name')), '随心选');
      await saveCategory(tester);
      expect(controller.fallbackCategory(MealScenario.restaurant).name, '随心选');
      expect(
        find.byKey(ValueKey('delete-category-${fallback.id}')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'delete cancel keeps round; confirm moves options into renamed fallback',
    (tester) async {
      await tester.runAsync(
        () => controller.saveCategory(
          name: '特别的小店',
          scenario: MealScenario.restaurant,
        ),
      );
      final category = controller
          .categoriesFor(MealScenario.restaurant)
          .firstWhere((value) => value.name == '特别的小店');
      final fallback = controller.fallbackCategory(MealScenario.restaurant);
      await tester.runAsync(
        () => controller.saveCategory(
          id: fallback.id,
          name: '随心选',
          scenario: MealScenario.restaurant,
        ),
      );
      await tester.runAsync(
        () => controller.saveOption(
          name: '街角小馆',
          scenario: 'restaurant',
          category: category.name,
          periods: {MealPeriod.lunch},
        ),
      );
      final optionId = controller.options
          .firstWhere((value) => value.name == '街角小馆')
          .id;
      draw();
      final resultId = controller.result!.id;
      await mount(
        tester,
        CategoryManager(
          controller: controller,
          scenario: MealScenario.restaurant,
        ),
      );
      await tap(tester, find.byKey(ValueKey('delete-category-${category.id}')));
      expect(find.textContaining('会移到“随心选”'), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(controller.result!.id, resultId);
      expect(
        controller
            .categoriesFor(MealScenario.restaurant)
            .map((value) => value.id),
        contains(category.id),
      );
      await tap(tester, find.byKey(ValueKey('delete-category-${category.id}')));
      await tap(tester, find.text('删除分类'));
      await settleWrite(tester);
      expect(controller.hasRound, isFalse);
      final option = controller.options.firstWhere(
        (value) => value.id == optionId,
      );
      expect(option.categories, {'随心选'});
      expect(option.isDeleted, isFalse);
      expect(
        controller
            .categoriesFor(MealScenario.restaurant)
            .map((value) => value.id),
        isNot(contains(category.id)),
      );
      expect(
        controller.fallbackCategory(MealScenario.restaurant).id,
        fallback.id,
      );
    },
  );

  testWidgets(
    'editor reads renamed persisted categories and follows renames while open',
    (tester) async {
      final fallback = controller.fallbackCategory(MealScenario.eat);
      await tester.runAsync(
        () => controller.saveCategory(id: fallback.id, name: '随心选'),
      );
      await tester.runAsync(() => controller.saveCategory(name: '暖暖的一碗'));
      final custom = controller
          .categoriesFor(MealScenario.eat)
          .firstWhere((value) => value.name == '暖暖的一碗');
      await mount(tester, OptionEditor(controller: controller));
      final dropdown = find.byKey(const Key('option-category'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
        fallback.id,
      );
      await tap(tester, dropdown);
      await tap(tester, find.text('暖暖的一碗').last);
      await tester.runAsync(
        () => controller.saveCategory(id: custom.id, name: '热乎乎的一碗'),
      );
      await tester.pumpAndSettle();
      expect(find.text('热乎乎的一碗'), findsWidgets);
      expect(find.text('暖暖的一碗'), findsNothing);
      await tester.enterText(find.byKey(const Key('option-name')), '南瓜汤面');
      await tap(tester, find.byKey(const Key('save-option')));
      await settleWrite(tester);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!controller.options.any((value) => value.name == '南瓜汤面')) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Option did not finish saving');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        controller.options
            .firstWhere((value) => value.name == '南瓜汤面')
            .categories,
        {'热乎乎的一碗'},
      );
    },
  );

  testWidgets(
    'built-in editor shows renamed memberships and keeps category read-only',
    (tester) async {
      final category = controller
          .categoriesFor(MealScenario.cook)
          .firstWhere((value) => value.name == '家常菜');
      await tester.runAsync(
        () => controller.saveCategory(
          id: category.id,
          name: '家的味道',
          scenario: MealScenario.cook,
        ),
      );
      final option = controller.options.firstWhere(
        (value) =>
            value.scenario == 'cook' &&
            value.categories.contains('家的味道') &&
            value.categories.length > 1,
      );
      await mount(tester, OptionEditor(controller: controller, option: option));
      final dropdown = find.byKey(const Key('option-category'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged,
        isNull,
      );
      expect(find.textContaining('所属分类：'), findsOneWidget);
      expect(find.textContaining('家的味道'), findsWidgets);
    },
  );

  testWidgets('management and form wrap on small screens with large text', (
    tester,
  ) async {
    await mount(
      tester,
      CategoryManager(controller: controller),
      size: const Size(375, 700),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tap(tester, find.byKey(const Key('create-category')));
    expect(tester.takeException(), isNull);
    await tap(tester, find.byKey(const Key('save-category')));
    expect(find.text('请填写分类名称。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(700, 375);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-category')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
