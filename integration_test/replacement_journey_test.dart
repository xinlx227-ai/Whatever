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
    'Android replacement appends, retains session and retries exactly',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'replacement-android-',
      );
      final databasePath = '${directory.path}/journey.sqlite';
      var loseAcknowledgement = false;
      var repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
        onConfirmationPhase: (phase) {
          if (loseAcknowledgement &&
              phase == ConfirmationPhase.beforeAcknowledgement) {
            throw StateError('Lost acknowledgement');
          }
        },
      );
      await repository.saveCategory(name: '替换体验', scenario: MealScenario.cook);
      for (final name in ['香菇烧豆腐', '清炒丝瓜', '蒜蓉油麦菜', '番茄炖牛腩']) {
        final saved = await repository.saveOption(
          name: name,
          scenario: 'cook',
          category: '替换体验',
          periods: {MealPeriod.lunch},
        );
        expect(saved.changed, isTrue);
      }
      var controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 8, 12, 30),
      );
      await controller.initialize();
      await tester.pumpWidget(MealApp(controller: controller));
      await tester.pumpAndSettle();
      Finder key(String value) => find.byKey(ValueKey(value));
      List<String> ids() => controller.results.map((item) => item.id).toList();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> chooseReplacement(
        Finder finder, {
        bool animated = true,
      }) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.isDrawing, animated);
        expect(key('replacement-start'), findsNothing);
      }

      Future<void> openDuringAnimation(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(controller.isDrawing, isTrue);
      }

      Future<void> save() async {
        await tap(key('primary-action'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (controller.isSaving) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Save timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      await tap(key('decide-scenario-cook'));
      final category = controller
          .categoriesFor(MealScenario.cook)
          .singleWhere((item) => item.name == '替换体验');
      await tap(key('category-filter-button'));
      await tap(key('filter-category-${category.id}'));
      await tap(key('apply-category-filters'));
      await tap(key('cooking-count-3'));
      await tap(key('primary-action'));
      await tap(key('draw-next-dish'));
      await tap(key('draw-next-dish'));
      final original = ids();
      await tap(key('cooking-result-1'));
      await tap(key('replace-result-1'));
      await chooseReplacement(key('replacement-redraw'));
      expect(controller.hasPendingReplacement, isTrue);
      final sampled = controller.candidates[controller.selectedIndex!].id;
      expect(controller.canConfirm, isFalse);
      expect(controller.canReplace(0), isFalse);
      expect(find.byType(NavigationBar), findsNothing);
      await openDuringAnimation(key('draw-back'));
      await tester.pump(const Duration(seconds: 5));
      expect(controller.isDrawing, isTrue);
      expect(controller.candidates[controller.selectedIndex!].id, sampled);
      await tester.tap(find.text('继续抽取'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.hasPendingReplacement, isTrue);
      await tester.pumpAndSettle();
      expect(ids(), hasLength(3));
      expect(ids()[0], original[0]);
      expect(ids()[1], original[2]);
      expect(ids()[2], sampled);

      final excluded = ids()[0];
      final retained = ids().sublist(1);
      await tap(key('cooking-result-0'));
      await tap(key('replace-result-0'));
      // Excluding the outgoing option leaves one distinct replacement.
      await chooseReplacement(key('replacement-exclude'), animated: false);
      expect(controller.sessionExclusions, contains(excluded));
      await tester.pumpAndSettle();
      final finalMeal = ids();
      expect(finalMeal, isNot(contains(excluded)));
      expect(finalMeal.take(2), retained);
      expect(finalMeal.toSet(), hasLength(3));

      // Three remaining identities already occupy the entire meal.
      await tap(key('cooking-result-1'));
      await tap(key('replace-result-1'));
      for (final action in ['replacement-redraw', 'replacement-exclude']) {
        await tap(key(action));
        expect(key('replacement-shortage'), findsOneWidget);
        expect(ids(), finalMeal);
        expect(controller.hasPendingReplacement, isFalse);
        expect(controller.sessionExclusions, {excluded});
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(ids(), finalMeal);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('离开本次抽取？'), findsOneWidget);
      await tap(find.text('继续抽取'));
      expect(ids(), finalMeal);

      loseAcknowledgement = true;
      await save();
      expect(controller.hasRound, isTrue);
      expect(controller.canReplace(0), isFalse);
      expect(await repository.history(), hasLength(1));
      await save();
      expect(controller.hasRound, isFalse);
      expect(await repository.history(), hasLength(1));
      expect(
        (await repository.history()).single.options.map((item) => item.id),
        finalMeal,
      );
      loseAcknowledgement = false;
      expect(controller.sessionExclusions, {excluded});
      await tap(key('primary-action'));
      await tap(key('draw-next-dish'));
      final reducedMeal = [ids().last];
      await tap(key('cooking-result-0'));
      await tap(key('replace-result-0'));
      await chooseReplacement(key('replacement-redraw'));
      expect(ids(), reducedMeal);
      expect(controller.canConfirmRetained, isTrue);
      await openDuringAnimation(key('primary-action'));
      expect(find.text('确认已有的菜？'), findsOneWidget);
      await tap(find.text('确认这 1 道菜'));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (controller.isSaving) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Retained confirmation timed out');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(controller.hasRound, isFalse);
      expect(await repository.history(), hasLength(2));
      expect(
        (await repository.history()).first.options.map((item) => item.id),
        reducedMeal,
      );
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
      expect(controller.hasPendingReplacement, isFalse);
      expect(controller.hasRound, isFalse);
      expect(controller.sessionExclusions, isEmpty);
      expect(controller.history, hasLength(2));
      expect(
        controller.history.first.options.map((item) => item.id),
        reducedMeal,
      );
      expect(controller.history.last.options.map((item) => item.id), finalMeal);
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
