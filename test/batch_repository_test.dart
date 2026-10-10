import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  late List<FoodOption> dishes;
  late List<FoodOption> options;
  ConfirmationFault? fault;
  final timestamp = DateTime.utc(2026, 10, 8, 4, 30);

  Future<MealRepository> open() => MealRepository.open(
    factory: databaseFactoryFfi,
    path: databasePath,
    onConfirmationPhase: (phase) => fault?.call(phase),
  );

  Future<void> reopen() async {
    await repository.close();
    repository = await open();
  }

  Future<void> inspect(Future<void> Function(Database database) verify) async {
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await verify(database);
    } finally {
      await database.close();
    }
  }

  Future<void> expectStoredCounts(int records, int items) =>
      inspect((db) async {
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM history_records',
          )).single['n'],
          records,
        );
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM history_items',
          )).single['n'],
          items,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(await db.getVersion(), 7);
      });

  ConfirmationOperation operation(
    List<FoodOption> selected, {
    String id = 'batch',
    DateTime? at,
    MealPeriod period = MealPeriod.lunch,
  }) => ConfirmationOperation(
    operationId: id,
    confirmedAt: at ?? timestamp,
    period: period,
    options: selected,
  );

  FoodOption withScenario(FoodOption option, String scenario) => FoodOption(
    id: option.id,
    name: option.name,
    art: option.art,
    periods: option.periods,
    scenario: scenario,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-batch-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    fault = null;
    repository = await open();
    options = await repository.options();
    dishes = options
        .where(
          (option) =>
              option.scenario == 'cook' &&
              option.periods.contains(MealPeriod.lunch),
        )
        .toList();
  });

  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('operation and history copy and protect their ordered options', () {
    final source = dishes.take(3).toList();
    final pending = operation(source);
    final history = HistoryEntry(
      operationId: pending.operationId,
      confirmedAt: pending.confirmedAt,
      period: pending.period,
      options: source,
    );
    source.clear();
    expect(pending.options, dishes.take(3));
    expect(history.options, dishes.take(3));
    expect(() => pending.options.clear(), throwsUnsupportedError);
    expect(() => history.options.add(dishes.last), throwsUnsupportedError);
    expect(pending.option, same(dishes.first));
    expect(history.option, same(dishes.first));
    final single = ConfirmationOperation(
      operationId: 'single',
      confirmedAt: timestamp,
      period: MealPeriod.lunch,
      option: dishes.first,
    );
    expect(single.options, [dishes.first]);
    expect(
      () => ConfirmationOperation(
        operationId: 'invalid',
        confirmedAt: timestamp,
        period: MealPeriod.lunch,
        option: dishes.first,
        options: dishes,
      ),
      throwsArgumentError,
    );
  });

  for (final count in [1, 2, 3, 10]) {
    test('$count dishes write one ordered meal and survive reopen', () async {
      final selected = dishes.take(count).toList().reversed.toList();
      final pending = operation(selected);
      await repository.confirm(pending);
      await expectStoredCounts(1, count);
      await inspect((db) async {
        final rows = await db.query('history_items', orderBy: 'position');
        expect(
          rows.map((row) => row['position']),
          List.generate(count, (i) => i),
        );
        expect(rows.map((row) => row['option_id']), selected.map((o) => o.id));
      });
      await reopen();
      final saved = (await repository.history()).single;
      expect(saved.operationId, pending.operationId);
      expect(saved.confirmedAt, timestamp);
      expect(saved.period, MealPeriod.lunch);
      expect(saved.options.map((o) => o.id), selected.map((o) => o.id));
      await repository.confirm(pending);
      await expectStoredCounts(1, count);
    });
  }

  for (final failureItem in [1, 2]) {
    test(
      'failure after item $failureItem rolls back the entire meal',
      () async {
        var written = 0;
        fault = (phase) {
          if (phase == ConfirmationPhase.afterItemWritten &&
              ++written == failureItem) {
            throw StateError('Injected partial batch failure');
          }
        };
        final pending = operation(dishes.take(3).toList());
        await expectLater(repository.confirm(pending), throwsStateError);
        expect(written, failureItem);
        expect(await repository.history(), isEmpty);
        await expectStoredCounts(0, 0);
        await reopen();
        fault = null;
        await repository.confirm(pending);
        await expectStoredCounts(1, 3);
        expect((await repository.history()).single.confirmedAt, timestamp);
      },
    );
  }

  test('lost batch acknowledgement retries once after reopening', () async {
    var acknowledgements = 0;
    fault = (phase) {
      if (phase == ConfirmationPhase.beforeAcknowledgement) {
        acknowledgements++;
        throw StateError('Injected lost acknowledgement');
      }
    };
    final selected = dishes.take(3).toList();
    final pending = operation(selected);
    await expectLater(repository.confirm(pending), throwsStateError);
    await expectStoredCounts(1, 3);
    expect((await repository.history()).single.options, hasLength(3));
    await reopen();
    await repository.confirm(pending);
    await repository.confirm(pending);
    expect(acknowledgements, 1);
    await expectStoredCounts(1, 3);
    expect(
      (await repository.history()).single.options.map((o) => o.id),
      selected.map((o) => o.id),
    );
  });

  test('retry compares count, order, each identity, time and period', () async {
    final selected = dishes.take(3).toList();
    await repository.confirm(operation(selected));
    final mismatches = [
      operation(selected.reversed.toList()),
      operation(selected.take(2).toList()),
      operation([...selected, dishes[3]]),
      operation([selected[0], dishes[3], selected[2]]),
      operation(selected, at: timestamp.add(const Duration(microseconds: 1))),
      operation(selected, period: MealPeriod.dinner),
      operation(selected.map((o) => withScenario(o, 'restaurant')).toList()),
    ];
    for (final mismatch in mismatches) {
      await expectLater(
        repository.confirm(mismatch),
        throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
      );
    }
    await repository.confirm(operation(selected, at: timestamp.toLocal()));
    await expectStoredCounts(1, 3);
  });

  test(
    'committed retry acknowledges original eligibility after changes',
    () async {
      final created = await repository.saveOption(
        name: '自定义配菜',
        scenario: 'cook',
        periods: {MealPeriod.lunch},
      );
      final pending = operation([dishes[0], dishes[1], created.option!]);
      await repository.confirm(pending);
      await repository.setOptionActive(dishes[0].id, false);
      await repository.deleteOption(created.option!.id);
      await inspect((db) async {
        await db.delete(
          'option_periods',
          where: 'option_id = ?',
          whereArgs: [dishes[1].id],
        );
      });
      await reopen();
      await repository.confirm(pending);
      final saved = (await repository.history()).single;
      expect(saved.options.first.isActive, isFalse);
      expect(saved.options.last.isDeleted, isTrue);
      await expectStoredCounts(1, 3);
    },
  );

  test('legacy single rows coexist with grouped batch history', () async {
    final eating = options.firstWhere((o) => o.scenario == 'eat');
    await inspect((db) async {
      await db.transaction((tx) async {
        await tx.insert('history_records', {
          'operation_id': 'legacy-single',
          'confirmed_at': timestamp.microsecondsSinceEpoch,
          'period': 'lunch',
        });
        await tx.insert('history_items', {
          'operation_id': 'legacy-single',
          'position': 0,
          'option_id': eating.id,
        });
      });
    });
    await reopen();
    expect((await repository.history()).single.option.id, eating.id);
    await repository.confirm(operation(dishes.take(3).toList()));
    final restaurant = options.firstWhere(
      (o) => o.scenario == 'restaurant' && o.periods.contains(MealPeriod.lunch),
    );
    await repository.confirm(
      ConfirmationOperation(
        operationId: 'restaurant-single',
        confirmedAt: timestamp.add(const Duration(minutes: 1)),
        period: MealPeriod.lunch,
        option: restaurant,
      ),
    );
    await reopen();
    final history = await repository.history();
    expect(history.map((entry) => entry.operationId), [
      'restaurant-single',
      'batch',
      'legacy-single',
    ]);
    expect(history.map((entry) => entry.options.length), [1, 3, 1]);
    expect(history.last.option.id, eating.id);
    await expectStoredCounts(3, 5);
  });

  test('invalid batch shapes never write history', () async {
    final eating = options.where((o) => o.scenario == 'eat').take(2).toList();
    final restaurants = options
        .where((o) => o.scenario == 'restaurant')
        .take(2)
        .toList();
    for (final invalid in [
      operation([]),
      operation(dishes.take(11).toList()),
      operation([dishes[0], dishes[0]]),
      operation([dishes[0], eating[0]]),
      operation(eating),
      operation(restaurants),
      operation([dishes[0]], id: ' '),
      operation([withScenario(dishes[0], 'unknown')]),
    ]) {
      await expectLater(repository.confirm(invalid), throwsArgumentError);
      await expectStoredCounts(0, 0);
    }
  });

  test(
    'every item must be durably active, present, and period eligible',
    () async {
      final staleInactive = dishes[1];
      await repository.setOptionActive(staleInactive.id, false);
      final created = await repository.saveOption(
        name: '待删除配菜',
        scenario: 'cook',
        periods: {MealPeriod.lunch},
      );
      await repository.deleteOption(created.option!.id);
      final breakfastOnly = options.firstWhere(
        (o) => o.scenario == 'cook' && !o.periods.contains(MealPeriod.lunch),
      );
      final eating = options.firstWhere((o) => o.scenario == 'eat');
      final nonexistent = FoodOption(
        id: 'missing',
        name: 'Missing',
        art: 'plate',
        scenario: 'cook',
        periods: {MealPeriod.lunch},
      );
      for (final invalidItem in [
        staleInactive,
        created.option!,
        breakfastOnly,
        nonexistent,
        withScenario(eating, 'cook'),
      ]) {
        await expectLater(
          repository.confirm(operation([dishes[0], invalidItem])),
          throwsStateError,
        );
        await expectStoredCounts(0, 0);
      }
    },
  );
}
