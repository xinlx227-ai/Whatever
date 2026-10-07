import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  MealRepository? repository;

  Future<MealRepository> open() async {
    final opened = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    repository = opened;
    return opened;
  }

  Future<MealRepository> reopen() async {
    await repository?.close();
    repository = null;
    return open();
  }

  Future<Database> inspect() => databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  void expectPreferences(
    MealPreferences actual, {
    DrawMode mode = DrawMode.wheel,
    bool excludeYesterday = false,
  }) {
    expect(actual.mode, mode);
    expect(actual.excludeYesterday, excludeYesterday);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-preferences-');
    databasePath = path.join(directory.path, 'meal.sqlite');
  });

  tearDown(() async {
    await repository?.close();
    repository = null;
    await directory.delete(recursive: true);
  });

  test(
    'first installation defaults to Wheel with yesterday filtering off',
    () async {
      final opened = await open();
      expectPreferences(await opened.preferences());
      expectPreferences(await (await reopen()).preferences());
      expect((await repository!.options()).length, seedOptions.length);
      expect(await repository!.history(), isEmpty);
    },
  );

  test(
    'both preferences survive reopening and can return to defaults',
    () async {
      await open();
      for (final mode in DrawMode.values) {
        for (final excludeYesterday in [true, false]) {
          await repository!.savePreferences(
            MealPreferences(mode: mode, excludeYesterday: excludeYesterday),
          );
          expectPreferences(
            await (await reopen()).preferences(),
            mode: mode,
            excludeYesterday: excludeYesterday,
          );
        }
      }
      await repository!.savePreferences(const MealPreferences());
      expectPreferences(await (await reopen()).preferences());
      final database = await inspect();
      try {
        expect(await database.query('preferences'), hasLength(1));
      } finally {
        await database.close();
      }
    },
  );

  test(
    'a failed SQLite preference write preserves the entire previous pair',
    () async {
      final opened = await open();
      final database = await inspect();
      try {
        await database.execute('''
        CREATE TRIGGER fail_preferences AFTER INSERT ON preferences
        WHEN NEW.mode = 'cards'
        BEGIN
          SELECT RAISE(ABORT, 'Injected preference write failure');
        END
      ''');
        await expectLater(
          opened.savePreferences(
            const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
          ),
          throwsA(isA<DatabaseException>()),
        );
        expectPreferences(await opened.preferences());
        expectPreferences(await (await reopen()).preferences());
        await database.execute('DROP TRIGGER fail_preferences');
        await repository!.savePreferences(
          const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
        );
        expectPreferences(
          await (await reopen()).preferences(),
          mode: DrawMode.cards,
          excludeYesterday: true,
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'v1 migration preserves library and confirmed history with idempotent retries',
    () async {
      const legacyOption = FoodOption(
        id: 'legacy-noodles',
        name: '自选牛肉面',
        art: 'noodle',
        periods: {MealPeriod.lunch, MealPeriod.dinner},
      );
      final operation = ConfirmationOperation(
        operationId: 'confirmed-before-upgrade',
        confirmedAt: DateTime.utc(2026, 10, 5, 4, 30),
        period: MealPeriod.lunch,
        option: legacyOption,
      );
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE options (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, art TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE option_periods (
              option_id TEXT NOT NULL REFERENCES options(id),
              period TEXT NOT NULL,
              PRIMARY KEY (option_id, period)
            )
          ''');
            await database.execute('''
            CREATE TABLE history_records (
              operation_id TEXT PRIMARY KEY,
              confirmed_at INTEGER NOT NULL,
              period TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE history_items (
              operation_id TEXT NOT NULL REFERENCES history_records(operation_id),
              position INTEGER NOT NULL CHECK (position >= 0),
              option_id TEXT NOT NULL REFERENCES options(id),
              PRIMARY KEY (operation_id, position),
              UNIQUE (operation_id, option_id)
            )
          ''');
            for (final option in [legacyOption, seedOptions.first]) {
              await database.insert('options', {
                'id': option.id,
                'name': option.name,
                'art': option.art,
              });
              for (final period in option.periods) {
                await database.insert('option_periods', {
                  'option_id': option.id,
                  'period': period.name,
                });
              }
            }
            await database.insert('history_records', {
              'operation_id': operation.operationId,
              'confirmed_at': operation.confirmedAt.microsecondsSinceEpoch,
              'period': operation.period.name,
            });
            await database.insert('history_items', {
              'operation_id': operation.operationId,
              'position': 0,
              'option_id': legacyOption.id,
            });
          },
        ),
      );
      await legacy.close();

      final upgraded = await open();
      expectPreferences(await upgraded.preferences());
      final options = await upgraded.options();
      expect(options.map((option) => option.id), [
        legacyOption.id,
        ...seedOptions.map((option) => option.id),
      ]);
      expect(options.first.name, legacyOption.name);
      expect(options.first.art, legacyOption.art);
      expect(options.first.periods, legacyOption.periods);

      await upgraded.confirm(operation);
      await upgraded.confirm(operation);
      await expectLater(
        upgraded.confirm(
          ConfirmationOperation(
            operationId: operation.operationId,
            confirmedAt: operation.confirmedAt,
            period: operation.period,
            option: options.last,
          ),
        ),
        throwsStateError,
      );
      await upgraded.savePreferences(
        const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
      );
      final reopened = await reopen();
      expectPreferences(
        await reopened.preferences(),
        mode: DrawMode.cards,
        excludeYesterday: true,
      );
      final history = (await reopened.history()).single;
      expect(history.operationId, operation.operationId);
      expect(history.confirmedAt, operation.confirmedAt);
      expect(history.period, operation.period);
      expect(history.option.id, legacyOption.id);
      expect(history.option.name, legacyOption.name);
      expect(history.option.art, legacyOption.art);
      expect(history.option.periods, legacyOption.periods);
      final database = await inspect();
      try {
        expect(await database.getVersion(), 4);
        expect(await database.query('history_records'), hasLength(1));
        expect(await database.query('history_items'), hasLength(1));
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await database.close();
      }
    },
  );
}
