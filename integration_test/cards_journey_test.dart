import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android cards select, replace, retry and persist across scenarios',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('cards-android-');
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
      var controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 9, 12, 30),
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

      Future<void> idle() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (controller.isBusy) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Persistence timed out');
        }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      Future<void> reveal() async {
        final card = key('candidate-card-0');
        await tap(card);
        expect(controller.selectedCardIndex, 0);
        expect(controller.isDrawing, isFalse);
        await tap(card);
        expect(controller.result, isNotNull);
        expect(controller.isModeLocked, isTrue);
      }

      await tap(key('draw-mode-cards'));
      await idle();
      expect(controller.preferences.mode, DrawMode.cards);
      await tap(key('candidate-card-0'));
      final selection = controller.selectedCard!.id;
      await tap(find.text('选项库'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.selectedCard!.id, selection);
      expect(controller.hasRound, isFalse);
      await tap(key('candidate-card-0'));
      expect(controller.result!.id, selection);
      await tap(key('draw-mode-wheel'));
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.result!.id, selection);
      // Locked mode feedback is non-destructive and does not need confirmation.
      await tester.pumpAndSettle();
      await tap(key('replace-result-0'));
      await tap(key('replacement-exclude'));
      expect(controller.sessionExclusions, contains(selection));
      expect(controller.pendingReplacementIndex, 0);
      expect(controller.isDrawing, isFalse);
      await reveal();
      final replacement = controller.result!.id;
      expect(replacement, isNot(selection));
      loseAcknowledgement = true;
      await tap(key('primary-action'));
      await idle();
      expect(controller.hasRound, isTrue);
      expect(controller.result!.id, replacement);
      expect(await repository.history(), hasLength(1));
      loseAcknowledgement = false;
      await tap(key('primary-action'));
      await idle();
      expect(controller.hasRound, isFalse);
      expect(await repository.history(), hasLength(1));
      for (final scenario in [MealScenario.cook, MealScenario.restaurant]) {
        await tap(key('decide-scenario-${scenario.name}'));
        await reveal();
        await tap(key('primary-action'));
        await idle();
        expect(controller.hasRound, isFalse);
      }
      await tap(find.text('足迹'));
      expect(controller.history, hasLength(3));
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
      expect(controller.history, hasLength(3));
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.selectedCardIndex, isNull);
      expect(controller.sessionExclusions, isEmpty);
      controller.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
