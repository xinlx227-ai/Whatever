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
    'full-screen scenarios, Cards collection and retained native save retry',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'first-restore-native-',
      );
      final databasePath = '${directory.path}/meal.sqlite';
      var failAcknowledgement = false;
      var repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
        onConfirmationPhase: (phase) {
          if (failAcknowledgement &&
              phase == ConfirmationPhase.beforeAcknowledgement) {
            throw StateError('Simulated missed acknowledgement');
          }
        },
      );
      var model = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 10, 12),
      );
      await model.initialize();
      await tester.pumpWidget(MealApp(controller: model));
      await tester.pumpAndSettle();
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> idle() async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (model.isBusy) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Save timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await idle();
      }

      Future<void> reveal() async {
        await tap(key('candidate-card-0'));
        expect(model.selectedCardIndex, 0);
        await tap(key('candidate-card-0'));
        expect(model.result, isNotNull);
      }

      for (final mode in DrawMode.values) {
        await tap(key('draw-mode-${mode.name}'));
        for (final scenario in MealScenario.values) {
          await tap(key('decide-scenario-${scenario.name}'));
          if (scenario == MealScenario.cook) await tap(key('cooking-count-3'));
          await tap(key('primary-action'));
          expect(key('draw-stage'), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
          if (mode == DrawMode.cards) await reveal();
          if (scenario == MealScenario.cook) {
            if (mode == DrawMode.cards) {
              await tap(key('collect-central-card'));
              await reveal();
            } else {
              await tap(key('draw-next-dish'));
            }
            final retained = model.results.first.id;
            await tap(key('replace-result-1'));
            await tester.ensureVisible(key('replacement-exclude'));
            await tester.tap(key('replacement-exclude'));
            await tester.pump(const Duration(milliseconds: 100));
            if (mode == DrawMode.cards) await tester.pumpAndSettle();
            expect(model.results, hasLength(1));
            expect(model.hasPendingReplacement, isTrue);
            expect(key('replacement-start'), findsNothing);
            if (mode == DrawMode.wheel) expect(model.isDrawing, isTrue);
            final selected = model.selectedIndex;
            await tester.ensureVisible(key('primary-action'));
            await tester.pump();
            await tester.tap(key('primary-action'));
            await tester.pumpAndSettle();
            expect(find.text('正在替换一道菜，要继续抽取，还是直接确认已有的 1 道菜？'), findsOneWidget);
            await tester.pump(const Duration(seconds: 5));
            expect(model.selectedIndex, selected);
            await tester.tap(find.text('继续抽取'));
            await tester.pump(const Duration(milliseconds: 100));
            expect(model.hasPendingReplacement, isTrue);
            expect(model.selectedIndex, selected);
            await tester.ensureVisible(key('primary-action'));
            await tester.pump();
            await tester.tap(key('primary-action'));
            await tester.pumpAndSettle();
            failAcknowledgement = true;
            await tap(find.text('确认这 1 道菜'));
            expect(model.hasConfirmationAttempt, isTrue);
            expect(model.hasPendingReplacement, isFalse);
            expect(model.results.single.id, retained);
            final count = (await repository.history()).length;
            failAcknowledgement = false;
            await tap(key('primary-action'));
            expect((await repository.history()).length, count);
          } else {
            await tap(key('draw-back'));
            await tap(find.text('继续抽取'));
            await tap(key('primary-action'));
          }
          expect(key('draw-stage'), findsNothing);
          expect(model.hasRound, isFalse);
          expect(tester.takeException(), isNull);
        }
      }
      expect(await repository.history(), hasLength(6));
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactory,
        path: databasePath,
      );
      model = MealController(repository: repository);
      await model.initialize();
      expect(model.history, hasLength(6));
      expect(model.preferences.mode, DrawMode.cards);
      expect(model.sessionExclusions, isEmpty);
      expect(model.results, isEmpty);
      model.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
