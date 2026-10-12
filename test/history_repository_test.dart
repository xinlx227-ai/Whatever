import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  late List<FoodOption> dishes;
  final timestamp = DateTime.utc(2026, 10, 11, 4);

  Future<MealRepository> open() =>
      MealRepository.open(factory: databaseFactoryFfi, path: databasePath);

  Future<void> inspect(Future<void> Function(Database) action) async {
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await action(database);
    } finally {
      await database.close();
    }
  }

  Future<void> reopen() async {
    await repository.close();
    repository = await open();
  }

  Future<void> save(String id, List<FoodOption> options, {int minutes = 0}) =>
      repository.confirm(
        ConfirmationOperation(
          operationId: id,
          confirmedAt: timestamp.add(Duration(minutes: minutes)),
          period: MealPeriod.lunch,
          options: options,
        ),
      );

  Future<void> expectStoredCounts(int records, int items) =>
      inspect((db) async {
        expect(await db.query('history_records'), hasLength(records));
        expect(await db.query('history_items'), hasLength(items));
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(await db.getVersion(), 9);
      });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-history-');
    databasePath = '${directory.path}/meal.sqlite';
    repository = await open();
    dishes = (await repository.options())
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

  for (final count in [1, 3, 10]) {
    test('delete complete $count item record persists after reopen', () async {
      final retained = dishes.take(2).toList().reversed.toList();
      await save('older', retained);
      await save('removed', dishes.take(count).toList(), minutes: 1);
      await save('newer', [dishes.last], minutes: 2);
      expect(await repository.deleteHistory('removed'), isTrue);
      await expectStoredCounts(2, 3);
      await reopen();
      final history = await repository.history();
      expect(history.map((entry) => entry.operationId), ['newer', 'older']);
      expect(
        history.last.options.map((option) => option.id),
        retained.map((option) => option.id),
      );
      expect(history.last.confirmedAt, timestamp);
      expect(history.last.period, MealPeriod.lunch);
      expect(await repository.deleteHistory('removed'), isFalse);
      await expectStoredCounts(2, 3);
    });
  }

  test(
    'missing operation is a no-op and treats IDs as literal values',
    () async {
      await save('saved', dishes.take(3).toList());
      for (final id in ['missing', '', "saved' OR 1 = 1 --"]) {
        expect(await repository.deleteHistory(id), isFalse);
      }
      await reopen();
      expect((await repository.history()).single.operationId, 'saved');
      await expectStoredCounts(1, 3);
    },
  );

  for (final failedTable in ['history_items', 'history_records']) {
    test('$failedTable deletion failure rolls back the whole record', () async {
      final selected = dishes.take(3).toList().reversed.toList();
      await save('failed', selected);
      await inspect(
        (db) => db.execute('''
        CREATE TRIGGER reject_history_delete
        BEFORE DELETE ON $failedTable
        WHEN OLD.operation_id = 'failed'
        BEGIN
          SELECT RAISE(ABORT, 'Injected history deletion failure');
        END
      '''),
      );
      await expectLater(
        repository.deleteHistory('failed'),
        throwsA(isA<DatabaseException>()),
      );
      await reopen();
      final saved = (await repository.history()).single;
      expect(saved.operationId, 'failed');
      expect(
        saved.options.map((option) => option.id),
        selected.map((option) => option.id),
      );
      await expectStoredCounts(1, 3);
      await inspect((db) => db.execute('DROP TRIGGER reject_history_delete'));
      expect(await repository.deleteHistory('failed'), isTrue);
      await expectStoredCounts(0, 0);
    });
  }

  test(
    'deleting final history reference retains renamed deleted option',
    () async {
      final created = (await repository.saveOption(
        name: '个人配菜甲',
        scenario: 'cook',
        periods: {MealPeriod.lunch},
        imagePath: 'retained-image.png',
      )).option!;
      await save('custom-meal', [dishes.first, created]);
      final renamed = await repository.saveOption(
        id: created.id,
        name: '个人配菜乙',
        scenario: 'cook',
        periods: {MealPeriod.lunch},
        imagePath: created.imagePath,
        confirmSameFood: true,
      );
      expect(renamed.changed, isTrue);
      expect((await repository.deleteOption(created.id)).changed, isTrue);
      await reopen();
      final referenced = (await repository.history()).single.options.last;
      expect(referenced.id, created.id);
      expect(referenced.name, '个人配菜乙');
      expect(referenced.imagePath, 'retained-image.png');
      expect(referenced.isDeleted, isTrue);
      expect(await repository.deleteHistory('custom-meal'), isTrue);
      await reopen();
      final retained = (await repository.options()).singleWhere(
        (option) => option.id == created.id,
      );
      expect(retained.name, referenced.name);
      expect(retained.imagePath, referenced.imagePath);
      expect(retained.isDeleted, isTrue);
      expect(retained.periods, referenced.periods);
      expect(retained.categories, referenced.categories);
      await expectStoredCounts(0, 0);
    },
  );
}
