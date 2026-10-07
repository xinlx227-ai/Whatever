import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android personal option from creation to retained history and restoration',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'library-android-',
      );
      final databasePath = p.join(directory.path, 'journey.sqlite');
      var repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
      );
      var controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 6, 12),
      );
      await controller.initialize();
      // Public maintenance actions make the new food the only eligible option.
      for (final food in controller.options) {
        await controller.setOptionActive(food.id, false);
      }
      await tester.pumpWidget(MealApp(controller: controller));
      await tester.pumpAndSettle();
      Future<void> waitFor(bool Function() complete) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!complete()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native action did not complete');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.text('选项库'));
      await tap(find.byKey(const Key('create-option')));
      await tester.enterText(find.byKey(const Key('option-name')), '  家常番茄面  ');
      await tap(find.byKey(const Key('save-option')));
      await waitFor(
        () => controller.libraryOptions().isNotEmpty && !controller.isBusy,
      );
      final food = controller.libraryOptions().single;
      expect(food.name, '家常番茄面');
      expect(food.category, '未分类');
      expect(food.periods, {MealPeriod.lunch});
      await tap(find.text('决定'));
      await tap(find.byKey(const Key('primary-action')));
      expect(controller.result!.id, food.id);
      await tap(find.byKey(const Key('primary-action')));
      await waitFor(() => controller.history.isNotEmpty && !controller.isBusy);
      expect(controller.history.single.option.id, food.id);
      await tap(find.text('选项库'));
      await tap(find.byKey(ValueKey('toggle-${food.id}')));
      await waitFor(() => controller.candidates.isEmpty && !controller.isBusy);
      expect(controller.candidates, isEmpty);
      await tap(find.widgetWithText(ChoiceChip, '已停用'));
      await tester.enterText(find.byKey(const Key('library-search')), '家常');
      await tester.pumpAndSettle();
      await tap(find.byKey(ValueKey('delete-${food.id}')));
      await tap(find.text('取消'));
      expect(
        controller
            .libraryOptions(status: LibraryStatus.inactive)
            .map((food) => food.id),
        contains(food.id),
      );
      await tap(find.byKey(ValueKey('delete-${food.id}')));
      await tap(find.text('删除选项'));
      await waitFor(
        () =>
            controller.options
                .firstWhere((item) => item.id == food.id)
                .isDeleted &&
            !controller.isBusy,
      );
      expect(
        controller
            .libraryOptions(status: LibraryStatus.all)
            .map((food) => food.id),
        isNot(contains(food.id)),
      );
      await tap(find.text('足迹'));
      expect(find.text('家常番茄面'), findsOneWidget);
      await tap(find.text('选项库'));
      await tap(find.byKey(const Key('create-option')));
      await tester.enterText(find.byKey(const Key('option-name')), '家常番茄面');
      await tap(find.byKey(const Key('save-option')));
      await waitFor(() => find.text('恢复原来的选项？').evaluate().isNotEmpty);
      expect(find.text('恢复原来的选项？'), findsOneWidget);
      await tap(find.text('恢复并保存'));
      await waitFor(
        () => controller.libraryOptions().isNotEmpty && !controller.isBusy,
      );
      expect(controller.libraryOptions().single.id, food.id);
      expect(controller.history.single.option.id, food.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
      );
      controller = MealController(repository: repository);
      await controller.initialize();
      expect(controller.libraryOptions().single.id, food.id);
      expect(controller.history.single.option.name, '家常番茄面');
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
