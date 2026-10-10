import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late DateTime now;
  ConfirmationFault? fault;

  List<String> ids(Iterable<FoodOption> options) =>
      options.map((option) => option.id).toList();

  Future<void> configure(DrawMode mode, {int count = 3}) async {
    expect(controller.changeScenario(MealScenario.cook), isTrue);
    expect(controller.changeCookingCount(count), isTrue);
    expect(
      await controller.updatePreferences(MealPreferences(mode: mode)),
      isTrue,
    );
  }

  FoodOption draw({bool collect = true, int cardIndex = 0}) {
    if (controller.preferences.mode == DrawMode.cards) {
      expect(controller.selectCard(cardIndex), isTrue);
    }
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    final result = controller.result!;
    if (collect && controller.canCollectCard) {
      expect(controller.collectCard(), isTrue);
    }
    return result;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('first-restore-');
    now = DateTime(2026, 10, 10, 12);
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: Random(27),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'Cards collect and reopen preserve uniqueness and remaining fan order',
    () async {
      await configure(DrawMode.cards);
      final initial = ids(controller.cardDeck);
      final shuffle = controller.cardDeckShuffleRevision;
      final first = draw(collect: false, cardIndex: 2);
      expect(controller.collectedResults, isEmpty);
      expect(controller.canDraw, isFalse);
      expect(controller.selectCard(0), isFalse);
      expect(controller.focusResult(0), isFalse);
      expect(controller.canConfirm, isTrue);
      expect(ids(controller.cardDeck), initial.where((id) => id != first.id));
      expect(controller.collectCardResult(), isTrue);
      expect(controller.cardCentralResult, isNull);
      expect(controller.collectedCardResultIndexes, [0]);
      expect(controller.focusResult(0), isTrue);
      expect(controller.focusedResultIndex, 0);
      expect(controller.cardCentralResult, same(first));
      expect(controller.selectCard(0), isTrue);
      expect(controller.cancelCardSelection(), isTrue);
      expect(controller.selectedCard, isNull);
      expect(controller.cardCentralResult, same(first));
      expect(controller.collectCard(), isTrue);
      expect(ids(controller.results), [first.id]);
      expect(ids(controller.collectedResults), [first.id]);
      final second = draw(cardIndex: 1);
      final third = draw(collect: false, cardIndex: 3);
      expect(controller.cardDeckShuffleRevision, shuffle);
      expect(ids(controller.results), [first.id, second.id, third.id]);
      expect(ids(controller.collectedResults), [first.id, second.id]);
      expect(controller.canDraw, isFalse);
      expect(controller.requestedCount, 3);
      expect(await controller.confirm(), isTrue);
      expect(ids(controller.history.single.options), [
        first.id,
        second.id,
        third.id,
      ]);
      expect(controller.requestedCount, 3);
    },
  );

  for (final choice in ReplacementChoice.values) {
    test(
      'Cards $choice removes old row card then appends on collection',
      () async {
        await configure(DrawMode.cards);
        final original = [draw(), draw(), draw()];
        final shuffle = controller.cardDeckShuffleRevision;
        expect(controller.focusResult(1), isTrue);
        expect(controller.beginReplacement(1, choice), isTrue);
        final retained = [original.first.id, original.last.id];
        expect(ids(controller.results), retained);
        expect(ids(controller.collectedResults), retained);
        expect(controller.cardCentralResult, isNull);
        expect(controller.cardDeckShuffleRevision, shuffle + 1);
        expect(controller.focusResult(0), isFalse);
        expect(controller.beginReplacement(0, choice), isFalse);
        expect(
          ids(controller.cardDeck).toSet().intersection(retained.toSet()),
          isEmpty,
        );
        final cardIndex = choice == ReplacementChoice.redraw
            ? controller.cardDeck.indexWhere(
                (option) => option.id == original[1].id,
              )
            : 0;
        final replacement = draw(collect: false, cardIndex: cardIndex);
        expect(ids(controller.results), [...retained, replacement.id]);
        expect(ids(controller.collectedResults), retained);
        expect(controller.hasPendingReplacement, isFalse);
        expect(controller.collectCard(), isTrue);
        expect(ids(controller.collectedResults), [...retained, replacement.id]);
        expect(controller.collectedCardResultIndexes, [0, 1, 2]);
        if (choice == ReplacementChoice.redraw) {
          expect(replacement.id, original[1].id);
        } else {
          expect(controller.sessionExclusions, {original[1].id});
        }
        expect(await controller.confirm(), isTrue);
        expect(ids(controller.history.single.options), [
          ...retained,
          replacement.id,
        ]);
      },
    );
  }

  for (final mode in DrawMode.values) {
    for (final duringAnimation in [false, true]) {
      test('$mode retained confirmation during animation=$duringAnimation '
          'discards the unrevealed replacement', () async {
        await configure(mode);
        final original = [draw(), draw(), draw()];
        expect(
          controller.beginReplacement(1, ReplacementChoice.exclude),
          isTrue,
        );
        final retained = [original.first.id, original.last.id];
        final pool = ids(
          mode == DrawMode.cards ? controller.cardDeck : controller.candidates,
        );
        final shuffle = controller.cardDeckShuffleRevision;
        if (duringAnimation) {
          if (mode == DrawMode.cards) controller.selectCard(0);
          expect(controller.startDraw(), isTrue);
        }
        expect(controller.isDrawing, duringAnimation);
        expect(controller.canConfirm, isFalse);
        expect(await controller.confirm(), isFalse);
        expect(controller.canConfirmRetained, isTrue);
        // Inspecting the decision state and continuing leaves sampling intact.
        expect(
          ids(
            mode == DrawMode.cards
                ? controller.cardDeck
                : controller.candidates,
          ),
          pool,
        );
        expect(controller.cardDeckShuffleRevision, shuffle);
        expect(controller.hasPendingReplacement, isTrue);
        expect(await controller.confirmRetained(), isTrue);
        controller.finishDraw();
        expect(controller.isDrawing, isFalse);
        expect(controller.hasRound, isFalse);
        expect(controller.hasPendingReplacement, isFalse);
        expect(controller.results, isEmpty);
        expect(ids(controller.history.single.options), retained);
        expect(controller.sessionExclusions, {original[1].id});
        expect(controller.requestedCount, 3);
        expect(await controller.confirmRetained(), isFalse);
      });
    }

    for (final failure in [
      ConfirmationPhase.afterItemWritten,
      ConfirmationPhase.beforeAcknowledgement,
    ]) {
      test(
        '$mode retained $failure failure retries the reduced meal exactly once',
        () async {
          await configure(mode);
          final original = [draw(), draw(), draw()];
          expect(
            controller.beginReplacement(0, ReplacementChoice.exclude),
            isTrue,
          );
          if (mode == DrawMode.cards) controller.selectCard(0);
          expect(controller.startDraw(), isTrue);
          final retained = ids(original.skip(1));
          final savedAt = now.toUtc();
          fault = (phase) {
            if (phase == failure) {
              throw StateError('Injected confirmation failure');
            }
          };
          expect(await controller.confirmRetained(), isFalse);
          expect(controller.hasPendingReplacement, isFalse);
          expect(controller.isDrawing, isFalse);
          expect(controller.hasRound, isTrue);
          expect(controller.hasConfirmationAttempt, isTrue);
          expect(controller.canConfirmRetained, isFalse);
          expect(controller.canConfirm, isTrue);
          expect(controller.canDraw, isFalse);
          expect(controller.startDraw(), isFalse);
          expect(controller.focusResult(0), isFalse);
          expect(
            controller.beginReplacement(0, ReplacementChoice.redraw),
            isFalse,
          );
          controller.finishDraw();
          expect(ids(controller.results), retained);
          expect(
            await repository.history(),
            failure == ConfirmationPhase.beforeAcknowledgement
                ? hasLength(1)
                : isEmpty,
          );
          fault = null;
          now = now.add(const Duration(days: 1));
          expect(await controller.confirm(), isTrue);
          final history = await repository.history();
          expect(history, hasLength(1));
          expect(ids(history.single.options), retained);
          expect(history.single.confirmedAt, savedAt);
          expect(await controller.confirm(), isFalse);
        },
      );
    }

    test(
      '$mode pending replacement cannot confirm zero retained dishes',
      () async {
        await configure(mode, count: 1);
        draw();
        expect(
          controller.beginReplacement(0, ReplacementChoice.exclude),
          isTrue,
        );
        expect(controller.results, isEmpty);
        expect(controller.canConfirmRetained, isFalse);
        expect(await controller.confirmRetained(), isFalse);
        if (mode == DrawMode.cards) controller.selectCard(0);
        expect(controller.startDraw(), isTrue);
        expect(await controller.confirmRetained(), isFalse);
        expect(await controller.confirm(), isFalse);
        expect(await repository.history(), isEmpty);
        controller.finishDraw();
        expect(controller.canConfirm, isTrue);
        expect(await controller.confirm(), isTrue);
      },
    );
  }

  test(
    'retained confirmation reserves the atomic save boundary immediately',
    () async {
      await configure(DrawMode.cards);
      draw();
      draw();
      expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
      final retained = ids(controller.results);
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      final saving = controller.confirmRetained();
      await entered.future;
      expect(controller.isSaving, isTrue);
      expect(await controller.confirmRetained(), isFalse);
      expect(await controller.confirm(), isFalse);
      expect(controller.abandon(), isFalse);
      release.complete();
      expect(await saving, isTrue);
      expect(ids(controller.history.single.options), retained);
    },
  );
}
