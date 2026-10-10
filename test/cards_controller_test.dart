import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

class CardShuffleRandom implements Random {
  final bounds = <int>[];
  final choices = <int>[];
  final Random seeded = Random(9);

  @override
  int nextInt(int max) {
    bounds.add(max);
    return choices.isEmpty ? seeded.nextInt(max) : choices.removeAt(0);
  }

  @override
  bool nextBool() => seeded.nextBool();

  @override
  double nextDouble() => seeded.nextDouble();
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late CardShuffleRandom random;
  late DateTime now;
  ConfirmationFault? fault;

  Future<void> createController() async {
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: random,
    );
    await controller.initialize();
  }

  List<String> ids(Iterable<FoodOption> options) =>
      options.map((option) => option.id).toList();

  FoodOption reveal(int index) {
    final chosen = controller.cardDeck[index];
    expect(controller.selectCard(index), isTrue);
    expect(controller.revealSelectedCard(), isTrue);
    controller.finishDraw();
    expect(controller.result, same(chosen));
    return chosen;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cards-controller-');
    random = CardShuffleRandom();
    now = DateTime(2026, 10, 9, 12);
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    await createController();
    expect(
      await controller.updatePreferences(
        const MealPreferences(mode: DrawMode.cards),
      ),
      isTrue,
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('all identities remain reachable and reveal uses the selected card', () {
    final deck = controller.cardDeck;
    expect(ids(deck).toSet(), ids(controller.candidates).toSet());
    expect(ids(deck).toSet(), hasLength(deck.length));
    final shuffleCalls = random.bounds.length;
    for (var index = 0; index < deck.length; index++) {
      expect(controller.selectCard(index), isTrue);
      expect(controller.selectedCard, same(deck[index]));
      expect(controller.cardDeck, same(deck));
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.results, isEmpty);
    }
    expect(controller.cancelCardSelection(), isTrue);
    expect(controller.selectedCard, isNull);
    expect(controller.cardDeck, same(deck));
    expect(controller.startDraw(), isFalse);
    expect(controller.selectCard(deck.length), isFalse);
    expect(controller.selectCard(-1), isFalse);
    expect(controller.selectCard(deck.length - 1), isTrue);
    expect(controller.revealSelectedCard(), isTrue);
    expect(controller.hasRound, isTrue);
    expect(controller.isModeLocked, isTrue);
    expect(controller.selectCard(0), isFalse);
    expect(controller.cancelCardSelection(), isFalse);
    expect(controller.canConfirm, isFalse);
    controller.finishDraw();
    expect(controller.results.single, same(deck.last));
    expect(controller.selectedIndex, deck.length - 1);
    expect(controller.canConfirm, isTrue);
    expect(random.bounds, hasLength(shuffleCalls));
    controller.finishDraw();
    expect(controller.results, hasLength(1));
  });

  test(
    'uniform shuffle choices cover every permutation of a three-card pool',
    () {
      final keep = controller.candidates.take(3).toList();
      for (final option in controller.candidates.skip(3).toList()) {
        expect(controller.excludeForSession(option.id), isTrue);
      }
      final permutations = <String>{};
      final occurrences = <String, int>{};
      for (var first = 0; first < 3; first++) {
        for (var second = 0; second < 2; second++) {
          controller.abandon();
          random.choices.addAll([first, second]);
          final deck = controller.cardDeck;
          expect(random.choices, isEmpty);
          permutations.add(ids(deck).join(','));
          for (var slot = 0; slot < 3; slot++) {
            final key = '$slot:${deck[slot].id}';
            occurrences[key] = (occurrences[key] ?? 0) + 1;
          }
        }
      }
      expect(permutations, hasLength(6));
      for (var slot = 0; slot < 3; slot++) {
        for (final option in keep) {
          expect(occurrences['$slot:${option.id}'], 2);
        }
      }
    },
  );

  for (final scenario in MealScenario.values) {
    test(
      'target-one $scenario cards confirm the selected identity to history',
      () async {
        expect(controller.changeScenario(scenario), isTrue);
        final chosen = reveal(controller.cardDeck.length - 1);
        expect(controller.isSingleTarget, isTrue);
        expect(await controller.confirm(), isTrue);
        expect(controller.hasRound, isFalse);
        expect(controller.selectedCard, isNull);
        expect(controller.history.single.option.id, chosen.id);
        expect(controller.history.single.option.scenario, scenario.name);
        expect(controller.preferences.cardTutorialDismissed, isFalse);
      },
    );
  }

  for (final choice in ReplacementChoice.values) {
    test(
      '$choice reshuffles then replaces the same slot after explicit reveal',
      () async {
        final outgoing = reveal(0);
        final oldDeck = controller.cardDeck;
        expect(controller.beginReplacement(0, choice), isTrue);
        expect(controller.results.single, same(outgoing));
        expect(controller.result, isNull);
        expect(controller.pendingReplacementIndex, 0);
        expect(controller.selectedCard, isNull);
        expect(controller.cardDeck, isNot(same(oldDeck)));
        expect(controller.isDrawing, isFalse);
        expect(controller.startDraw(), isFalse);
        expect(controller.canConfirm, isFalse);
        expect(await controller.confirm(), isFalse);
        expect(controller.beginReplacement(0, choice), isFalse);
        expect(
          controller.cardDeck.any((option) => option.id == outgoing.id),
          choice == ReplacementChoice.redraw,
        );
        final index = choice == ReplacementChoice.redraw
            ? controller.cardDeck.indexWhere(
                (option) => option.id == outgoing.id,
              )
            : controller.cardDeck.length - 1;
        final replacement = reveal(index);
        expect(controller.results.single, same(replacement));
        expect(controller.pendingReplacementIndex, isNull);
        expect(await controller.confirm(), isTrue);
        expect(controller.history.single.option.id, replacement.id);
        if (choice == ReplacementChoice.exclude) {
          expect(controller.sessionExclusions, contains(outgoing.id));
          expect(ids(controller.cardDeck), isNot(contains(outgoing.id)));
        } else {
          expect(replacement.id, outgoing.id);
        }
      },
    );
  }

  test('no alternative preserves revealed result, deck and exclusions', () {
    for (final option in controller.candidates.skip(1).toList()) {
      controller.excludeForSession(option.id);
    }
    final outgoing = reveal(0);
    final deck = controller.cardDeck;
    final exclusions = controller.sessionExclusions;
    for (final choice in ReplacementChoice.values) {
      expect(controller.beginReplacement(0, choice), isFalse);
      expect(controller.result, same(outgoing));
      expect(controller.results.single, same(outgoing));
      expect(controller.cardDeck, same(deck));
      expect(controller.sessionExclusions, exclusions);
      expect(controller.canConfirm, isTrue);
    }
  });

  test(
    'multi-target classification preserves requested count and Wheel flow',
    () async {
      controller.changeScenario(MealScenario.cook);
      controller.changeCookingCount(3);
      expect(controller.requestedCount, 3);
      expect(controller.isSingleTarget, isFalse);
      expect(controller.isCardFlowSupported, isFalse);
      expect(controller.cardDeck, isEmpty);
      expect(controller.selectCard(0), isFalse);
      expect(controller.startDraw(), isFalse);
      expect(controller.canDraw, isFalse);
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isTrue,
      );
      expect(controller.requestedCount, 3);
      expect(controller.startDraw(), isTrue);
      controller.finishDraw();
      expect(controller.results, hasLength(1));
      expect(controller.isSingleTarget, isFalse);
      expect(controller.canDraw, isTrue);
      expect(controller.canConfirm, isTrue);
    },
  );

  test(
    'mode changes are allowed before reveal and forbidden after it',
    () async {
      controller.selectCard(0);
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isTrue,
      );
      expect(controller.selectedCard, isNull);
      expect(controller.cardDeck, isEmpty);
      expect(
        await controller.updatePreferences(
          const MealPreferences(mode: DrawMode.cards),
        ),
        isTrue,
      );
      reveal(0);
      final result = controller.result;
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isFalse,
      );
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.result, same(result));
    },
  );

  test(
    'no-op conditions/data preserve selection, actual changes clear the deck',
    () async {
      var deck = controller.cardDeck;
      controller.selectCard(0);
      expect(controller.changePeriod(controller.period), isTrue);
      expect(controller.changeScenario(controller.scenario), isTrue);
      expect(controller.changeCategoryFilters({}), isTrue);
      await controller.applyDataChange(changed: false);
      expect(controller.cardDeck, same(deck));
      expect(controller.selectedCard, same(deck[0]));
      await controller.applyDataChange(changed: true);
      expect(controller.selectedCard, isNull);
      expect(controller.cardDeck, isNot(same(deck)));
      deck = controller.cardDeck;
      controller.selectCard(0);
      controller.changePeriod(MealPeriod.dinner);
      expect(controller.selectedCard, isNull);
      expect(controller.cardDeck, isNot(same(deck)));
      deck = controller.cardDeck;
      controller.selectCard(0);
      controller.changeCategoryFilters({
        controller.categoriesFor(controller.scenario).first.id,
      });
      expect(controller.selectedCard, isNull);
      expect(controller.cardDeck, isNot(same(deck)));
      controller.abandon();
      controller.changeScenario(MealScenario.cook);
      controller.selectCard(0);
      controller.changeCookingCount(2);
      expect(controller.selectedCard, isNull);
      expect(controller.cardDeck, isEmpty);
    },
  );

  test(
    'save failure keeps the chosen identity and retries create one history record',
    () async {
      final chosen = reveal(0);
      var acknowledgements = 0;
      fault = (phase) {
        if (phase == ConfirmationPhase.beforeAcknowledgement &&
            acknowledgements++ == 0) {
          throw StateError('Injected missed acknowledgement');
        }
      };
      expect(await controller.confirm(), isFalse);
      expect(controller.results.single, same(chosen));
      expect(controller.hasRound, isTrue);
      expect(controller.preferences.cardTutorialDismissed, isFalse);
      expect(controller.selectCard(1), isFalse);
      expect(controller.beginReplacement(0, ReplacementChoice.redraw), isFalse);
      expect(await controller.confirm(), isTrue);
      expect(controller.history, hasLength(1));
      expect(controller.history.single.option.id, chosen.id);
      expect(await controller.dismissCardTutorial(), isTrue);
      controller.dispose();
      await createController();
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.selectedCard, isNull);
    },
  );

  test(
    'an empty unstarted fan recovers newly eligible cards after midnight',
    () async {
      final option = controller.candidates.first;
      for (final other in controller.candidates.where(
        (o) => o.id != option.id,
      )) {
        controller.excludeForSession(other.id);
      }
      await repository.confirm(
        ConfirmationOperation(
          operationId: 'yesterday-only-candidate',
          confirmedAt: DateTime(2026, 10, 8, 12),
          period: controller.period,
          option: option,
        ),
      );
      await controller.applyDataChange(changed: true);
      await controller.updatePreferences(
        const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
      );
      expect(controller.cardDeck, isEmpty);
      now = DateTime(2026, 10, 10, 0, 1);
      expect(controller.cardDeck.map((o) => o.id), [option.id]);
      expect(controller.hasRound, isFalse);
      reveal(0);
    },
  );

  for (final selectSaved in [true, false]) {
    test(
      'midnight rechecks first-flip scope with selected saved=$selectSaved',
      () async {
        final saved = controller.candidates.first;
        await repository.confirm(
          ConfirmationOperation(
            operationId: 'saved-before-midnight',
            confirmedAt: now,
            period: controller.period,
            option: saved,
          ),
        );
        await controller.applyDataChange(changed: true);
        expect(
          await controller.updatePreferences(
            const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
          ),
          isTrue,
        );
        final deck = controller.cardDeck;
        final selected = selectSaved
            ? saved
            : deck.firstWhere((option) => option.id != saved.id);
        controller.selectCard(
          deck.indexWhere((option) => option.id == selected.id),
        );
        now = DateTime(2026, 10, 10, 0, 1);
        expect(controller.revealSelectedCard(), !selectSaved);
        if (selectSaved) {
          expect(controller.hasRound, isFalse);
          expect(controller.selectedCard, isNull);
          expect(controller.error, contains('重新选'));
          expect(ids(controller.cardDeck), isNot(contains(saved.id)));
        } else {
          expect(
            ids(controller.cardDeck),
            ids(deck).where((id) => id != saved.id).toList(),
          );
          controller.finishDraw();
          expect(controller.result!.id, selected.id);
          expect(ids(controller.candidates), isNot(contains(saved.id)));
        }
      },
    );
  }

  test(
    'failed tutorial write preserves round and can retry independently',
    () async {
      final selected = reveal(0);
      final database = await databaseFactoryFfi.openDatabase(
        '${directory.path}/meal.sqlite',
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await database.execute('''
        CREATE TRIGGER fail_tutorial BEFORE UPDATE ON preferences
        WHEN NEW.card_tutorial_dismissed = 1
        BEGIN SELECT RAISE(ABORT, 'Injected tutorial failure'); END
      ''');
        expect(await controller.dismissCardTutorial(), isFalse);
        expect(controller.preferences.cardTutorialDismissed, isFalse);
        expect(controller.results.single, same(selected));
        expect(controller.canConfirm, isTrue);
        await database.execute('DROP TRIGGER fail_tutorial');
        expect(await controller.dismissCardTutorial(), isTrue);
        expect(controller.preferences.cardTutorialDismissed, isTrue);
        expect(controller.results.single, same(selected));
        expect(controller.isModeLocked, isTrue);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'Skip is independent of an in-flight confirmation and survives stale preferences',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final chosen = reveal(0);
      fault = (phase) async {
        if (phase == ConfirmationPhase.beforeAcknowledgement) {
          entered.complete();
          await release.future;
        }
      };
      final saving = controller.confirm();
      await entered.future;
      expect(controller.isSaving, isTrue);
      expect(await controller.dismissCardTutorial(), isTrue);
      expect(controller.results.single, same(chosen));
      expect(controller.hasRound, isTrue);
      release.complete();
      expect(await saving, isTrue);
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isTrue,
      );
      expect(controller.preferences.cardTutorialDismissed, isTrue);
      expect((await repository.preferences()).cardTutorialDismissed, isTrue);
    },
  );
}
