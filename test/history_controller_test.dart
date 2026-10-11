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

  Future<void> createController() async {
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: Random(13),
    );
    await controller.initialize();
  }

  Future<void> saveHistory({
    String id = 'past',
    MealScenario scenario = MealScenario.restaurant,
    DateTime? at,
    List<FoodOption>? options,
  }) async {
    final selected =
        options ??
        [
          controller.options.firstWhere(
            (option) =>
                option.scenario == scenario.name &&
                option.periods.contains(MealPeriod.lunch),
          ),
        ];
    await repository.confirm(
      ConfirmationOperation(
        operationId: id,
        confirmedAt: at ?? now.subtract(const Duration(days: 8)),
        period: MealPeriod.lunch,
        options: selected,
      ),
    );
    await controller.applyDataChange(changed: true);
  }

  Future<void> inspect(Future<void> Function(Database) action) async {
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/meal.sqlite',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await action(db);
    } finally {
      await db.close();
    }
  }

  FoodOption draw() {
    if (controller.preferences.mode == DrawMode.cards) {
      expect(controller.selectCard(0), isTrue);
    }
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    final result = controller.result!;
    if (controller.preferences.mode == DrawMode.cards &&
        !controller.isSingleTarget) {
      expect(controller.collectCard(), isTrue);
    }
    return result;
  }

  Future<void> configurePending(DrawMode mode) async {
    expect(
      await controller.updatePreferences(MealPreferences(mode: mode)),
      isTrue,
    );
    expect(controller.changeScenario(MealScenario.cook), isTrue);
    expect(controller.changeCookingCount(3), isTrue);
    draw();
    draw();
    expect(controller.beginReplacement(0, ReplacementChoice.exclude), isTrue);
    if (mode == DrawMode.cards) {
      expect(controller.selectCard(0), isTrue);
    }
    expect(controller.startDraw(), isTrue);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'whatever-history-controller-',
    );
    now = DateTime(2026, 10, 11, 12);
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    await createController();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  for (final mode in DrawMode.values) {
    test(
      '$mode deletion clears pending draw and lock, keeps exclusions',
      () async {
        await saveHistory();
        await configurePending(mode);
        final exclusions = controller.sessionExclusions;
        expect(exclusions, isNotEmpty);
        expect(controller.isDrawing, isTrue);
        expect(controller.hasPendingReplacement, isTrue);
        expect(controller.isModeLocked, isTrue);
        expect(controller.preferences.excludeYesterday, isFalse);
        expect(await controller.deleteHistory('past'), isTrue);
        expect(controller.history, isEmpty);
        expect(controller.hasRound, isFalse);
        expect(controller.hasPendingReplacement, isFalse);
        expect(controller.isDrawing, isFalse);
        expect(controller.isModeLocked, isFalse);
        expect(controller.hasConfirmationAttempt, isFalse);
        expect(controller.results, isEmpty);
        expect(controller.result, isNull);
        expect(controller.selectedIndex, isNull);
        expect(controller.selectedCardIndex, isNull);
        expect(controller.collectedResults, isEmpty);
        expect(controller.sessionExclusions, exclusions);
        expect(controller.scenario, MealScenario.cook);
        expect(controller.cookingCount, 3);
        expect(controller.period, MealPeriod.lunch);
        expect(controller.restartNotice, isNotNull);
        controller.finishDraw();
        expect(controller.results, isEmpty);
        expect(controller.takeRestartNotice(), isNotNull);
        expect(controller.takeRestartNotice(), isNull);
        expect(
          await controller.updatePreferences(
            MealPreferences(
              mode: mode == DrawMode.cards ? DrawMode.wheel : DrawMode.cards,
            ),
          ),
          isTrue,
        );
        expect(await repository.history(), isEmpty);
      },
    );

    test('$mode no-op and failed deletion preserve pending round', () async {
      await saveHistory();
      await configurePending(mode);
      final results = controller.results;
      final candidates = controller.candidates;
      final exclusions = controller.sessionExclusions;
      final selectedCardIndex = controller.selectedCardIndex;
      final selectedIndex = controller.selectedIndex;
      final shuffle = controller.cardDeckShuffleRevision;
      expect(await controller.deleteHistory('missing'), isFalse);
      await inspect(
        (db) => db.execute('''
        CREATE TRIGGER reject_history_delete
        BEFORE DELETE ON history_records
        BEGIN
          SELECT RAISE(ABORT, 'Injected history deletion failure');
        END
      '''),
      );
      await expectLater(
        controller.deleteHistory('past'),
        throwsA(isA<DatabaseException>()),
      );
      expect(controller.error, '足迹暂时无法删除，请重试。');
      expect(controller.results, same(results));
      expect(controller.candidates, same(candidates));
      expect(controller.sessionExclusions, exclusions);
      expect(controller.selectedCardIndex, selectedCardIndex);
      expect(controller.selectedIndex, selectedIndex);
      expect(controller.cardDeckShuffleRevision, shuffle);
      expect(controller.isDrawing, isTrue);
      expect(controller.hasPendingReplacement, isTrue);
      expect(controller.isModeLocked, isTrue);
      expect(controller.restartNotice, isNull);
      expect(controller.history.single.operationId, 'past');
      expect((await repository.history()).single.operationId, 'past');
      expect(controller.isBusy, isFalse);
      await inspect((db) => db.execute('DROP TRIGGER reject_history_delete'));
      expect(await controller.deleteHistory('past'), isTrue);
      expect(controller.error, isNull);
      expect(controller.hasRound, isFalse);
    });
  }

  test('deleting yesterday records rebuilds unique item eligibility', () async {
    final dishes = controller.options
        .where(
          (option) =>
              option.scenario == 'cook' &&
              option.periods.contains(MealPeriod.lunch),
        )
        .take(3)
        .toList();
    await saveHistory(options: dishes, at: DateTime(2026, 10, 10, 12));
    await saveHistory(
      id: 'shared-item',
      options: [dishes.first],
      at: DateTime(2026, 10, 10, 18),
    );
    expect(controller.changeScenario(MealScenario.cook), isTrue);
    expect(
      await controller.updatePreferences(
        const MealPreferences(excludeYesterday: true),
      ),
      isTrue,
    );
    bool eligible(FoodOption dish) =>
        controller.candidates.any((option) => option.id == dish.id);
    for (final dish in dishes) {
      expect(eligible(dish), isFalse);
    }
    draw();
    expect(await controller.deleteHistory('past'), isTrue);
    expect(controller.hasRound, isFalse);
    expect(eligible(dishes.first), isFalse);
    expect(eligible(dishes[1]), isTrue);
    expect(eligible(dishes[2]), isTrue);
    expect(await controller.deleteHistory('shared-item'), isTrue);
    expect(eligible(dishes.first), isTrue);
    expect(controller.history, isEmpty);
  });

  test(
    'viewing history and no-op after completed deletion preserve new round',
    () async {
      await saveHistory(scenario: MealScenario.eat, at: now);
      draw();
      final result = controller.result;
      expect(controller.history.single.options, hasLength(1));
      expect((await repository.history()).single.operationId, 'past');
      expect(controller.result, same(result));
      expect(controller.hasRound, isTrue);
      expect(await controller.deleteHistory('past'), isTrue);
      controller.takeRestartNotice();
      draw();
      final nextResult = controller.result;
      expect(await controller.deleteHistory('past'), isFalse);
      expect(controller.result, same(nextResult));
      expect(controller.hasRound, isTrue);
      expect(controller.restartNotice, isNull);
    },
  );

  for (final failConfirmation in [false, true]) {
    test(
      'deletion serializes behind confirmation failure=$failConfirmation',
      () async {
        await saveHistory();
        draw();
        final result = controller.result!;
        final entered = Completer<void>();
        final release = Completer<void>();
        fault = (phase) async {
          if (phase == ConfirmationPhase.afterHeaderWritten) {
            entered.complete();
            await release.future;
            if (failConfirmation) throw StateError('Injected save failure');
          }
        };
        final confirmation = controller.confirm();
        await entered.future;
        var deletionFinished = false;
        final deletion = controller.deleteHistory('past').then((deleted) {
          deletionFinished = true;
          return deleted;
        });
        expect(controller.isBusy, isTrue);
        expect(await controller.confirm(), isFalse);
        expect(controller.startDraw(), isFalse);
        expect(controller.abandon(), isFalse);
        expect(deletionFinished, isFalse);
        release.complete();
        expect(await confirmation, !failConfirmation);
        expect(await deletion, isTrue);
        expect(controller.hasRound, isFalse);
        expect(controller.hasConfirmationAttempt, isFalse);
        expect(controller.isBusy, isFalse);
        if (failConfirmation) {
          expect(controller.history, isEmpty);
          expect(controller.restartNotice, isNotNull);
        } else {
          expect(controller.history.single.option.id, result.id);
          expect(controller.restartNotice, isNull);
        }
        expect((await repository.history()).length, failConfirmation ? 0 : 1);
      },
    );
  }

  test(
    'queued deletion and library change share one reserved boundary',
    () async {
      await saveHistory();
      draw();
      final deletion = controller.deleteHistory('past');
      final duplicate = controller.deleteHistory('past');
      final category = controller.saveCategory(name: '删除后的分类');
      expect(controller.isBusy, isTrue);
      expect(controller.startDraw(), isFalse);
      expect(await controller.confirm(), isFalse);
      expect(await deletion, isTrue);
      expect(await duplicate, isFalse);
      expect((await category).changed, isTrue);
      expect(controller.history, isEmpty);
      expect(controller.hasRound, isFalse);
      expect(controller.isBusy, isFalse);
      expect(
        controller.categoriesFor(MealScenario.eat).map((value) => value.name),
        contains('删除后的分类'),
      );
      expect(await repository.history(), isEmpty);
    },
  );

  test(
    'refresh retry recovers a committed deletion without resetting a new round',
    () async {
      await saveHistory();
      await configurePending(DrawMode.cards);
      final exclusions = controller.sessionExclusions;
      await inspect(
        (db) => db.execute('ALTER TABLE options RENAME TO unavailable_options'),
      );
      expect(await controller.deleteHistory('past'), isTrue);
      expect(controller.history, isEmpty);
      expect(controller.needsDataRefresh, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.hasPendingReplacement, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.sessionExclusions, exclusions);
      expect(controller.canDraw, isFalse);

      await controller.retryDataRefresh();
      expect(controller.needsDataRefresh, isTrue);
      expect(controller.history, isEmpty);
      expect(controller.sessionExclusions, exclusions);
      await inspect(
        (db) => db.execute('ALTER TABLE unavailable_options RENAME TO options'),
      );
      await controller.retryDataRefresh();
      expect(controller.needsDataRefresh, isFalse);
      expect(controller.error, isNull);
      expect(controller.canDraw, isTrue);
      expect(controller.sessionExclusions, exclusions);
      expect(await repository.history(), isEmpty);

      controller.takeRestartNotice();
      draw();
      final results = controller.results;
      await controller.retryDataRefresh();
      expect(await controller.deleteHistory('past'), isFalse);
      expect(controller.results, same(results));
      expect(controller.hasRound, isTrue);
      expect(controller.restartNotice, isNull);
      expect(controller.sessionExclusions, exclusions);
    },
  );
}
