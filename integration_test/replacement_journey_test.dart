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
  testWidgets('Android replacement preserves slots, session and exact retry', (
    tester,
  ) async {
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
    await tap(key('replace-result-1'));
    await tap(key('replacement-redraw'));
    expect(controller.pendingReplacementIndex, 1);
    expect(controller.isDrawing, isFalse);
    expect(controller.canConfirm, isFalse);
    expect(controller.canReplace(0), isFalse);
    await tap(find.text('选项库'));
    await tap(find.text('足迹'));
    await tap(find.text('决定'));
    expect(controller.pendingReplacementIndex, 1);
    await tap(key('replacement-start'));
    expect(ids(), hasLength(3));
    expect(ids()[0], original[0]);
    expect(ids()[2], original[2]);

    final excluded = ids()[0];
    final retained = ids().sublist(1);
    await tap(key('replace-result-0'));
    await tap(key('replacement-exclude'));
    expect(controller.sessionExclusions, contains(excluded));
    expect(controller.isDrawing, isFalse);
    await tap(key('replacement-start'));
    final finalMeal = ids();
    expect(finalMeal, isNot(contains(excluded)));
    expect(finalMeal.sublist(1), retained);
    expect(finalMeal.toSet(), hasLength(3));

    // Three remaining identities already occupy the entire meal.
    await tap(key('replace-result-1'));
    for (final action in ['replacement-redraw', 'replacement-exclude']) {
      await tap(key(action));
      expect(key('replacement-shortage'), findsOneWidget);
      expect(ids(), finalMeal);
      expect(controller.pendingReplacementIndex, isNull);
      expect(controller.sessionExclusions, {excluded});
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(ids(), finalMeal);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃后，这次未确认的选择不会记入足迹。'), findsOneWidget);
    await tap(find.text('继续这一餐'));
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
    await tap(key('draw-next-dish'));
    expect(ids().toSet(), finalMeal.toSet());
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
    expect(controller.pendingReplacementIndex, isNull);
    expect(controller.hasRound, isFalse);
    expect(controller.sessionExclusions, isEmpty);
    expect(controller.history, hasLength(1));
    expect(controller.history.single.options.map((item) => item.id), finalMeal);
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });
}
