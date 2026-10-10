import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android cooking batches, shortage and atomic retry survive reopening',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'cooking-android-',
      );
      final databasePath = '${directory.path}/journey.sqlite';
      var failItem = false;
      var loseAcknowledgement = false;
      var writtenItems = 0;
      var repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
        onConfirmationPhase: (phase) {
          if (phase == ConfirmationPhase.afterHeaderWritten) writtenItems = 0;
          if (phase == ConfirmationPhase.afterItemWritten) {
            writtenItems++;
            if (failItem && writtenItems == 2) {
              throw StateError('Second item failed');
            }
          }
          if (phase == ConfirmationPhase.beforeAcknowledgement &&
              loseAcknowledgement) {
            throw StateError('Lost acknowledgement');
          }
        },
      );
      var controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 8, 12, 30),
      );
      await controller.initialize();
      await tester.pumpWidget(MealApp(controller: controller));
      await tester.pumpAndSettle();

      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tap(key('primary-action'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (controller.isSaving) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Confirmation timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      // Retain a legacy-shaped single-option confirmation beside new meals.
      await tap(key('primary-action'));
      await save();
      await tap(key('decide-scenario-cook'));
      await tap(key('cooking-count-3'));
      await tap(key('primary-action'));
      await tap(key('draw-next-dish'));
      final firstMeal = controller.results.map((item) => item.id).toList();
      expect(firstMeal.toSet(), hasLength(2));
      expect(find.text('就做这 2 道菜'), findsOneWidget);
      expect(key('cooking-count-2'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tap(key('restart-round'));
      await tap(find.text('继续抽取'));
      expect(controller.cookingCount, 3);
      expect(controller.results.map((item) => item.id), firstMeal);

      failItem = true;
      await save();
      expect(find.text('重试保存'), findsOneWidget);
      expect((await repository.history()), hasLength(1));
      expect(controller.results.map((item) => item.id), firstMeal);
      failItem = false;
      await save();
      expect((await repository.history()), hasLength(2));
      expect(
        (await repository.history()).first.options.map((item) => item.id),
        firstMeal,
      );

      await tap(key('primary-action'));
      await tap(key('draw-next-dish'));
      loseAcknowledgement = true;
      await save();
      expect((await repository.history()), hasLength(3));
      expect(controller.results, hasLength(2));
      expect(
        tester.widget<OutlinedButton>(key('draw-next-dish')).onPressed,
        isNull,
      );
      await save();
      expect((await repository.history()), hasLength(3));
      expect(controller.hasRound, isFalse);
      loseAcknowledgement = false;

      final soup = controller
          .categoriesFor(MealScenario.cook)
          .singleWhere((item) => item.name == '汤羹');
      await tap(key('category-filter-button'));
      await tap(key('filter-category-${soup.id}'));
      await tap(key('apply-category-filters'));
      await tap(key('cooking-count-custom'));
      await tester.enterText(key('custom-cooking-count-input'), '10');
      await tap(key('apply-custom-cooking-count'));
      final available = controller.availableCount;
      expect(available, inInclusiveRange(1, 9));
      await tap(key('primary-action'));
      await tap(find.text('调整筛选条件'));
      await tap(key('apply-category-filters'));
      await tap(key('primary-action'));
      await tap(find.text('改为 $available 道'));
      expect(controller.hasRound, isFalse);
      for (var index = 0; index < available; index++) {
        await tap(key(index == 0 ? 'primary-action' : 'draw-next-dish'));
      }
      expect(
        controller.results.every((item) => item.categories.contains('汤羹')),
        isTrue,
      );
      expect(
        controller.results.map((item) => item.id).toSet(),
        hasLength(available),
      );
      await save();
      await tap(find.text('足迹'));
      final entries = await repository.history();
      expect(entries, hasLength(4));
      for (final entry in entries) {
        expect(key('history-${entry.operationId}'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
      );
      controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 8, 12, 30),
      );
      await controller.initialize();
      expect(controller.cookingCount, 1);
      expect(controller.hasRound, isFalse);
      expect(controller.history, hasLength(4));
      expect(
        controller.history.map(
          (entry) => entry.options.map((item) => item.id).join(','),
        ),
        entries.map((entry) => entry.options.map((item) => item.id).join(',')),
      );
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
