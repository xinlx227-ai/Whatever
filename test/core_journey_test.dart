import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

class IndexRandom implements Random {
  int index = 0;
  final bounds = <int>[];

  @override
  int nextInt(int max) {
    bounds.add(max);
    return index % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  late MealController controller;
  late IndexRandom random;
  late DateTime now;
  ConfirmationFault? fault;

  Future<void> reopen() async {
    controller.dispose();
    await repository.close();
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: random,
    );
    await controller.initialize();
  }

  Future<void> expectStoredCounts(int records, int items) async {
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final headers = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM history_records',
      );
      final details = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM history_items',
      );
      expect(headers.single['count'], records);
      expect(details.single['count'], items);
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await database.close();
    }
  }

  void draw() {
    expect(controller.startDraw(), isTrue);
    expect(controller.result, isNull);
    expect(controller.isDrawing, isTrue);
    controller.finishDraw();
    expect(controller.result, isNotNull);
    expect(controller.isDrawing, isFalse);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-meal-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    random = IndexRandom();
    now = DateTime(2026, 10, 6, 12, 30);
    fault = null;
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      clock: () => now,
      random: random,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('one explicit draw and confirmation survives reopening', () async {
    expect(controller.period, MealPeriod.lunch);
    expect(controller.options.length, 70);
    expect(controller.history, isEmpty);
    expect(controller.error, isNull);
    draw();
    final selected = controller.result!;
    expect(await controller.confirm(), isTrue);
    expect(controller.result, isNull);
    expect(controller.hasRound, isFalse);
    expect(controller.history.single.option.id, selected.id);
    expect(controller.history.single.confirmedAt, now.toUtc());
    expect(controller.history.single.period, MealPeriod.lunch);
    final operationId = controller.history.single.operationId;
    expect(operationId, isNotEmpty);
    expect(await controller.confirm(), isFalse);
    await expectStoredCounts(1, 1);
    await reopen();
    expect(controller.history.single.operationId, operationId);
    expect(controller.history.single.option.name, selected.name);
    expect(controller.history.single.confirmedAt, now.toUtc());
    expect(controller.hasRound, isFalse);
  });

  test(
    'unconfirmed results and abandoned rounds never become history',
    () async {
      draw();
      expect(controller.abandon(), isTrue);
      expect(controller.hasRound, isFalse);
      draw();
      await reopen();
      expect(controller.result, isNull);
      expect(controller.history, isEmpty);
      await expectStoredCounts(0, 0);
    },
  );

  test(
    'a write failure after the header rolls back and retains retry payload',
    () async {
      var failOnce = true;
      fault = (phase) {
        if (phase == ConfirmationPhase.afterHeaderWritten && failOnce) {
          failOnce = false;
          throw StateError('Injected write failure');
        }
      };
      draw();
      final selected = controller.result;
      final confirmationTime = now;
      expect(await controller.confirm(), isFalse);
      expect(controller.error, isNotEmpty);
      expect(controller.result, same(selected));
      expect(controller.history, isEmpty);
      expect(controller.isSaving, isFalse);
      await expectStoredCounts(0, 0);
      now = now.add(const Duration(hours: 8));
      expect(await controller.confirm(), isTrue);
      expect(controller.history.single.confirmedAt, confirmationTime.toUtc());
      expect(controller.history.single.period, MealPeriod.lunch);
      expect(controller.history.single.option.id, selected!.id);
      expect(controller.error, isNull);
      await expectStoredCounts(1, 1);
    },
  );

  test(
    'missed acknowledgement retries the committed operation exactly once',
    () async {
      var acknowledgementCalls = 0;
      fault = (phase) {
        if (phase == ConfirmationPhase.beforeAcknowledgement) {
          acknowledgementCalls++;
          throw StateError('Injected lost acknowledgement');
        }
      };
      draw();
      final selected = controller.result;
      final confirmationTime = now;
      expect(await controller.confirm(), isFalse);
      expect(controller.result, same(selected));
      expect(controller.error, isNotEmpty);
      final committed = (await repository.history()).single;
      expect(controller.history.single.operationId, committed.operationId);
      await expectStoredCounts(1, 1);
      now = now.add(const Duration(days: 1));
      expect(await controller.confirm(), isTrue);
      expect(acknowledgementCalls, 1);
      expect(controller.history.single.operationId, committed.operationId);
      expect(controller.history.single.confirmedAt, confirmationTime.toUtc());
      expect(controller.result, isNull);
      await expectStoredCounts(1, 1);
      await reopen();
      expect(controller.history.single.operationId, committed.operationId);
    },
  );

  for (final changePeriod in [false, true]) {
    test(
      'missed acknowledgement stays visible after ${changePeriod ? 'changing period' : 'abandoning'}',
      () async {
        fault = (phase) {
          if (phase == ConfirmationPhase.beforeAcknowledgement) {
            throw StateError('Injected lost acknowledgement');
          }
        };
        draw();
        final selected = controller.result!;
        expect(await controller.confirm(), isFalse);
        expect(controller.result, same(selected));
        expect(controller.error, '暂时无法确认保存结果，请重试，不会重复记录。');
        final saved = controller.history.single;
        expect(saved.option.id, selected.id);
        expect(saved.confirmedAt, now.toUtc());
        expect(
          changePeriod
              ? controller.changePeriod(MealPeriod.dinner)
              : controller.abandon(),
          isTrue,
        );
        expect(controller.hasRound, isFalse);
        expect(controller.history.single.operationId, saved.operationId);
        expect(await controller.confirm(), isFalse);
        await expectStoredCounts(1, 1);
        await reopen();
        expect(controller.history.single.operationId, saved.operationId);
      },
    );
  }

  test(
    'saving rejects repeated confirmation and changes to the round',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      draw();
      final selected = controller.result;
      final first = controller.confirm();
      await entered.future;
      expect(controller.isSaving, isTrue);
      expect(await controller.confirm(), isFalse);
      expect(controller.startDraw(), isFalse);
      expect(controller.abandon(), isFalse);
      expect(controller.changePeriod(MealPeriod.dinner), isFalse);
      expect(controller.changeScenario(MealScenario.cook), isFalse);
      expect(controller.scenario, MealScenario.eat);
      expect(controller.result, same(selected));
      expect(controller.period, MealPeriod.lunch);
      release.complete();
      expect(await first, isTrue);
      expect(controller.isSaving, isFalse);
      expect(await controller.confirm(), isFalse);
      await expectStoredCounts(1, 1);
    },
  );

  test('drawing reveals only on completion and blocks another start', () async {
    expect(controller.startDraw(), isTrue);
    final index = controller.selectedIndex;
    expect(controller.result, isNull);
    expect(controller.startDraw(), isFalse);
    expect(await controller.confirm(), isFalse);
    controller.finishDraw();
    expect(controller.result!.id, controller.candidates[index!].id);
    expect(controller.startDraw(), isFalse);
    controller.finishDraw();
    await expectStoredCounts(0, 0);
  });

  test(
    'every eligible option is selectable from the complete period pool',
    () async {
      final accepted = <MealPeriod, List<String>>{
        for (final period in MealPeriod.values)
          period: seedOptions
              .where(
                (option) =>
                    option.scenario == 'eat' && option.periods.contains(period),
              )
              .map((option) => option.id)
              .toList(),
      };
      for (final entry in accepted.entries) {
        expect(controller.changePeriod(entry.key), isTrue);
        expect(controller.candidates.map((option) => option.id), entry.value);
        final seen = <String>{};
        for (var index = 0; index < entry.value.length; index++) {
          random.index = index;
          draw();
          seen.add(controller.result!.id);
          expect(random.bounds.last, entry.value.length);
          expect(controller.selectedIndex, index);
          expect(controller.abandon(), isTrue);
        }
        expect(seen, entry.value.toSet());
      }
      await expectStoredCounts(0, 0);
    },
  );

  test(
    'fresh launch uses exact time boundaries and manual selection persists',
    () async {
      final boundaries = <(int, int, MealPeriod)>[
        (4, 59, MealPeriod.lateNight),
        (5, 0, MealPeriod.breakfast),
        (10, 59, MealPeriod.breakfast),
        (11, 0, MealPeriod.lunch),
        (15, 59, MealPeriod.lunch),
        (16, 0, MealPeriod.dinner),
        (20, 59, MealPeriod.dinner),
        (21, 0, MealPeriod.lateNight),
        (0, 0, MealPeriod.lateNight),
      ];
      for (final (hour, minute, expected) in boundaries) {
        now = DateTime(2026, 10, 6, hour, minute);
        await reopen();
        expect(controller.period, expected);
      }
      expect(controller.changePeriod(MealPeriod.breakfast), isTrue);
      now = DateTime(2026, 10, 6, 19);
      draw();
      expect(controller.period, MealPeriod.breakfast);
      expect(controller.changePeriod(MealPeriod.dinner), isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.result, isNull);
      expect(controller.period, MealPeriod.dinner);
    },
  );

  test(
    'an operation ID cannot be reused with different saved contents',
    () async {
      draw();
      expect(await controller.confirm(), isTrue);
      final saved = controller.history.single;
      final retry = ConfirmationOperation(
        operationId: saved.operationId,
        confirmedAt: saved.confirmedAt,
        period: saved.period,
        option: saved.option,
      );
      await repository.confirm(retry);
      await repository.confirm(
        ConfirmationOperation(
          operationId: saved.operationId,
          confirmedAt: saved.confirmedAt.toLocal(),
          period: saved.period,
          option: saved.option,
        ),
      );
      final alternative = controller.candidates.firstWhere(
        (option) => option.id != saved.option.id,
      );
      for (final changed in [
        ConfirmationOperation(
          operationId: saved.operationId,
          confirmedAt: saved.confirmedAt,
          period: saved.period,
          option: alternative,
        ),
        ConfirmationOperation(
          operationId: saved.operationId,
          confirmedAt: saved.confirmedAt.add(const Duration(minutes: 1)),
          period: saved.period,
          option: saved.option,
        ),
        ConfirmationOperation(
          operationId: saved.operationId,
          confirmedAt: saved.confirmedAt,
          period: MealPeriod.dinner,
          option: saved.option,
        ),
      ]) {
        await expectLater(repository.confirm(changed), throwsStateError);
      }
      await expectStoredCounts(1, 1);
    },
  );

  test(
    'multiple confirmations have distinct IDs and newest-first history',
    () async {
      draw();
      expect(await controller.confirm(), isTrue);
      final first = controller.history.single;
      now = now.add(const Duration(microseconds: 1));
      random.index = 1;
      draw();
      expect(await controller.confirm(), isTrue);
      expect(controller.history.length, 2);
      expect(controller.history.first.confirmedAt, now.toUtc());
      expect(controller.history.last.operationId, first.operationId);
      expect(controller.history.first.operationId, isNot(first.operationId));
      await expectStoredCounts(2, 2);
      await reopen();
      expect(controller.history.length, 2);
      expect(controller.history.first.confirmedAt, now.toUtc());
    },
  );

  test(
    'session exclusions survive abandon, confirmation and period changes only',
    () async {
      expect(controller.excludeForSession('soy-milk'), isTrue);
      expect(controller.excludeForSession('missing'), isFalse);
      draw();
      expect(controller.isModeLocked, isTrue);
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains('soy-milk')),
      );
      expect(controller.abandon(), isTrue);
      expect(controller.isModeLocked, isFalse);
      controller.changePeriod(MealPeriod.dinner);
      draw();
      expect(await controller.confirm(), isTrue);
      expect(controller.sessionExclusions, {'soy-milk'});
      draw();
      await reopen();
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.sessionExclusions, isEmpty);
      expect(controller.period, MealPeriod.lunch);
      expect(controller.history, hasLength(1));
    },
  );

  test(
    'mode is locked by drawing and preferences alone survive fresh launch',
    () async {
      const preference = MealPreferences(
        mode: DrawMode.cards,
        excludeYesterday: true,
      );
      expect(await controller.updatePreferences(preference), isTrue);
      expect(controller.startDraw(), isTrue);
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isFalse,
      );
      controller.finishDraw();
      controller.changePeriod(MealPeriod.lateNight);
      now = DateTime(2026, 10, 7, 7);
      await reopen();
      expect(controller.preferences.mode, DrawMode.cards);
      expect(controller.preferences.excludeYesterday, isTrue);
      expect(controller.period, MealPeriod.breakfast);
      expect(controller.hasRound, isFalse);
      expect(
        await controller.updatePreferences(const MealPreferences()),
        isTrue,
      );
      await reopen();
      expect(controller.preferences.mode, DrawMode.wheel);
      expect(controller.preferences.excludeYesterday, isFalse);
    },
  );

  test(
    'yesterday scope freezes at draw and refreshes after midnight abandonment',
    () async {
      now = DateTime(2026, 10, 5, 12);
      draw();
      final oldOption = controller.result!;
      expect(await controller.confirm(), isTrue);
      now = DateTime(2026, 10, 6, 23, 59);
      expect(
        await controller.updatePreferences(
          const MealPreferences(excludeYesterday: true),
        ),
        isTrue,
      );
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains(oldOption.id)),
      );
      draw();
      final frozen = controller.candidates.map((option) => option.id).toList();
      now = DateTime(2026, 10, 7, 0, 1);
      expect(controller.candidates.map((option) => option.id), frozen);
      expect(controller.period, MealPeriod.lunch);
      controller.abandon();
      expect(
        controller.candidates.map((option) => option.id),
        contains(oldOption.id),
      );
    },
  );

  test(
    'committed mutations invalidate but canceled and unchanged edits preserve',
    () async {
      controller.excludeForSession('soy-milk');
      draw();
      final chosen = controller.result;
      await controller.applyDataChange(changed: false);
      expect(controller.result, same(chosen));
      expect(controller.isModeLocked, isTrue);
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.update(
        'options',
        {'name': '更新后的餐食'},
        where: 'id = ?',
        whereArgs: [chosen!.id],
      );
      await controller.applyDataChange(changed: true);
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.sessionExclusions, {'soy-milk'});
      expect(
        controller.options.firstWhere((option) => option.id == chosen.id).name,
        '更新后的餐食',
      );
      expect(controller.takeRestartNotice(), isNotNull);
      expect(controller.takeRestartNotice(), isNull);
      expect(controller.history, isEmpty);
    },
  );

  test(
    'history deletion refreshes yesterday eligibility and invalidates a round',
    () async {
      now = DateTime(2026, 10, 5, 12);
      draw();
      final saved = controller.result!;
      await controller.confirm();
      now = DateTime(2026, 10, 6, 12);
      await controller.updatePreferences(
        const MealPreferences(excludeYesterday: true),
      );
      draw();
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.transaction((transaction) async {
        await transaction.delete('history_items');
        await transaction.delete('history_records');
      });
      await controller.applyDataChange(changed: true);
      expect(controller.hasRound, isFalse);
      expect(controller.history, isEmpty);
      expect(
        controller.candidates.map((option) => option.id),
        contains(saved.id),
      );
    },
  );

  test(
    'unreadable mutated data stays blocked with feedback until refreshed',
    () async {
      draw();
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.execute(
        'ALTER TABLE options RENAME TO unavailable_options',
      );
      await controller.applyDataChange(changed: true);
      expect(controller.hasRound, isFalse);
      expect(controller.candidates, isEmpty);
      expect(controller.error, contains('重新打开'));
      controller.changePeriod(MealPeriod.dinner);
      controller.abandon();
      await controller.updatePreferences(
        const MealPreferences(excludeYesterday: true),
      );
      expect(controller.startDraw(), isFalse);
      expect(controller.error, contains('重新打开'));
      await database.execute(
        'ALTER TABLE unavailable_options RENAME TO options',
      );
      await controller.applyDataChange(changed: true);
      expect(controller.error, isNull);
      draw();
    },
  );

  test(
    'invalidation waits for in-flight confirmation without duplicating history',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      draw();
      final saving = controller.confirm();
      await entered.future;
      final invalidation = controller.applyDataChange(changed: true);
      expect(controller.startDraw(), isFalse);
      expect(controller.abandon(), isFalse);
      release.complete();
      expect(await saving, isTrue);
      await invalidation;
      expect(controller.isBusy, isFalse);
      expect(controller.hasRound, isFalse);
      await expectStoredCounts(1, 1);
    },
  );
}
