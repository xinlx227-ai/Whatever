import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/category_manager.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/option_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android category management, filtering, history and persistence',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'category-android-',
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
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
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
            fail('Native category action did not complete');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      Future<void> saveCategory(String name) async {
        await tester.enterText(find.byKey(const Key('category-name')), name);
        await tap(find.byKey(const Key('save-category')));
        await waitFor(
          () =>
              find.byKey(const Key('category-name')).evaluate().isEmpty &&
              !controller.isBusy,
        );
      }

      await tap(find.text('选项库'));
      await tap(find.byKey(const Key('manage-categories')));
      await tap(find.byKey(const Key('create-category')));
      await saveCategory('S05周末灵感');
      final category = controller
          .categoriesFor(MealScenario.eat)
          .singleWhere((value) => value.name == 'S05周末灵感');
      await tap(find.byTooltip('返回'));
      await tap(find.byKey(const Key('create-option')));
      await tester.enterText(find.byKey(const Key('option-name')), 'S05南瓜汤面');
      await tap(find.byKey(const Key('option-category')));
      await tap(find.text('S05周末灵感').last);
      await tap(find.byKey(const Key('save-option')));
      await waitFor(
        () =>
            find.byType(OptionEditor).evaluate().isEmpty && !controller.isBusy,
      );
      final custom = controller.options.singleWhere(
        (value) => value.name == 'S05南瓜汤面',
      );
      expect(custom.categories, {'S05周末灵感'});

      await tap(find.byKey(const Key('manage-categories')));
      await tap(find.byKey(ValueKey('rename-category-${category.id}')));
      await saveCategory('S05暖暖一碗');
      final fallback = controller.fallbackCategory(MealScenario.eat);
      await tap(find.byKey(ValueKey('rename-category-${fallback.id}')));
      await saveCategory('S05随心选');
      await tap(find.byTooltip('返回'));
      await tap(find.text('决定'));
      await tap(find.byKey(const Key('category-filter-button')));
      await tap(find.byKey(ValueKey('filter-category-${category.id}')));
      await tap(find.byKey(const Key('apply-category-filters')));
      expect(controller.candidates.map((value) => value.id), [custom.id]);
      final action = find.byKey(const Key('primary-action'));
      await tap(action);
      expect(controller.result!.id, custom.id);
      await tap(action);
      await waitFor(() => controller.history.length == 1 && !controller.isBusy);

      await tap(find.text('选项库'));
      await tap(find.byKey(const Key('manage-categories')));
      await tap(find.byKey(ValueKey('delete-category-${category.id}')));
      expect(find.textContaining('会移到“S05随心选”'), findsOneWidget);
      await tap(find.text('取消'));
      expect(
        controller.categoriesFor(MealScenario.eat).map((value) => value.id),
        contains(category.id),
      );
      await tap(find.byKey(ValueKey('delete-category-${category.id}')));
      await tap(find.text('删除分类'));
      await waitFor(
        () =>
            !controller.isBusy &&
            !controller
                .categoriesFor(MealScenario.eat)
                .any((value) => value.id == category.id),
      );
      expect(
        controller.options
            .singleWhere((value) => value.id == custom.id)
            .categories,
        {'S05随心选'},
      );
      await tap(find.byTooltip('返回'));
      await tap(find.text('决定'));
      expect(controller.selectedCategoryIds, {fallback.id});
      expect(controller.candidates.map((value) => value.id), [custom.id]);
      await tap(action);
      expect(controller.result!.id, custom.id);
      await tap(action);
      await waitFor(() => controller.history.length == 2 && !controller.isBusy);
      await tap(find.text('足迹'));
      expect(find.text(custom.name), findsNWidgets(2));
      expect(find.byType(CategoryManager), findsNothing);
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
        clock: () => DateTime(2026, 10, 7, 12),
      );
      await controller.initialize();
      expect(controller.history, hasLength(2));
      expect(controller.history.map((entry) => entry.option.id).toSet(), {
        custom.id,
      });
      expect(
        controller.options
            .singleWhere((value) => value.id == custom.id)
            .categories,
        {'S05随心选'},
      );
      expect(controller.fallbackCategory(MealScenario.eat).id, fallback.id);
      expect(controller.fallbackCategory(MealScenario.eat).name, 'S05随心选');
      expect(
        controller.categoriesFor(MealScenario.eat).map((value) => value.id),
        isNot(contains(category.id)),
      );
      expect(controller.selectedCategoryIds, isEmpty);
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
