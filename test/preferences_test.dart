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
    bool cardTutorialDismissed = false,
    bool cardCollectionTutorialDismissed = false,
  }) {
    expect(actual.mode, mode);
    expect(actual.excludeYesterday, excludeYesterday);
    expect(actual.cardTutorialDismissed, cardTutorialDismissed);
    expect(
      actual.cardCollectionTutorialDismissed,
      cardCollectionTutorialDismissed,
    );
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
        expect(await database.getVersion(), 8);
        expect(await database.query('history_records'), hasLength(1));
        expect(await database.query('history_items'), hasLength(1));
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'v5 upgrade preserves preferences, edited identities and saved history',
    () async {
      final opened = await open();
      await opened.savePreferences(
        const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
      );
      final option = (await opened.options()).first;
      await opened.confirm(
        ConfirmationOperation(
          operationId: 'v5-confirmed',
          confirmedAt: DateTime(2026, 10, 9, 8),
          period: option.periods.first,
          option: option,
        ),
      );
      await opened.close();
      repository = null;
      final legacy = await inspect();
      try {
        await legacy.execute(
          'ALTER TABLE preferences DROP COLUMN card_collection_tutorial_dismissed',
        );
        await legacy.execute(
          'ALTER TABLE preferences DROP COLUMN card_tutorial_dismissed',
        );
        await legacy.execute('ALTER TABLE options DROP COLUMN recognition_id');
        await legacy.setVersion(5);
        await legacy.update(
          'options',
          {'name': '保留旧版编辑'},
          where: 'id = ?',
          whereArgs: [option.id],
        );
      } finally {
        await legacy.close();
      }
      final upgraded = await open();
      expectPreferences(
        await upgraded.preferences(),
        mode: DrawMode.cards,
        excludeYesterday: true,
      );
      expect((await upgraded.history()).single.option.id, option.id);
      expect((await upgraded.history()).single.option.name, '保留旧版编辑');
      await upgraded.dismissCardTutorial();
      await upgraded.savePreferences(const MealPreferences());
      expectPreferences(
        await (await reopen()).preferences(),
        cardTutorialDismissed: true,
      );
    },
  );

  for (final baseDismissed in [false, true]) {
    test(
      'v6 migration preserves base tutorial=$baseDismissed and all saved data',
      () async {
        final opened = await open();
        await opened.savePreferences(
          MealPreferences(
            mode: DrawMode.cards,
            excludeYesterday: true,
            cardTutorialDismissed: baseDismissed,
          ),
        );
        final changed = await opened.saveOption(
          name: '保留自选菜品',
          scenario: 'cook',
          periods: {MealPeriod.lunch},
        );
        final existingDish = (await opened.options()).firstWhere(
          (option) =>
              option.scenario == MealScenario.cook.name &&
              option.id != changed.option!.id &&
              option.periods.contains(MealPeriod.lunch),
        );
        await opened.confirm(
          ConfirmationOperation(
            operationId: 'v6-saved-meal',
            confirmedAt: DateTime(2026, 10, 10, 12),
            period: MealPeriod.lunch,
            options: [existingDish, changed.option!],
          ),
        );
        await opened.close();
        repository = null;
        final before = <String, List<Map<String, Object?>>>{};
        final legacy = await inspect();
        try {
          await legacy.execute(
            'ALTER TABLE options DROP COLUMN recognition_id',
          );
          for (final table in [
            'options',
            'option_periods',
            'option_categories',
            'categories',
            'history_records',
            'history_items',
          ]) {
            before[table] = await legacy.query(table, orderBy: 'rowid');
          }
          await legacy.execute(
            'ALTER TABLE preferences DROP COLUMN card_collection_tutorial_dismissed',
          );
          await legacy.setVersion(6);
        } finally {
          await legacy.close();
        }
        final upgraded = await open();
        expectPreferences(
          await upgraded.preferences(),
          mode: DrawMode.cards,
          excludeYesterday: true,
          cardTutorialDismissed: baseDismissed,
        );
        final database = await inspect();
        try {
          expect(await database.getVersion(), 8);
          for (final entry in before.entries) {
            expect(
              await database.query(
                entry.key,
                columns: entry.value.firstOrNull?.keys.toList(),
                orderBy: 'rowid',
              ),
              entry.value,
            );
          }
          expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await database.close();
        }
        final stale = await upgraded.preferences();
        await upgraded.dismissCardTutorial();
        expect(
          (await upgraded.preferences()).cardCollectionTutorialDismissed,
          isFalse,
        );
        await Future.wait([
          upgraded.dismissCardTutorial(includeCollection: true),
          upgraded.savePreferences(stale),
        ]);
        await upgraded.savePreferences(const MealPreferences());
        expectPreferences(
          await (await reopen()).preferences(),
          cardTutorialDismissed: true,
          cardCollectionTutorialDismissed: true,
        );
      },
    );
  }

  test(
    'new default art follows category identity and remains stable after edits',
    () async {
      final opened = await open();
      final categories = await opened.categories();
      final hotpot = categories.firstWhere(
        (category) => category.id == 'builtin-category-restaurant-0',
      );
      await opened.saveCategory(id: hotpot.id, name: '更名后的火锅');
      final created = await opened.saveOption(
        name: '自选火锅店',
        periods: {MealPeriod.lunch},
        scenario: MealScenario.restaurant.name,
        category: '更名后的火锅',
      );
      expect(created.changed, isTrue);
      expect(created.option!.art, 'shop-hotpot');
      final edited = await opened.saveOption(
        id: created.option!.id,
        name: '自选火锅店',
        periods: {MealPeriod.lunch},
        scenario: MealScenario.restaurant.name,
        category: '西餐',
      );
      expect(edited.option!.art, 'shop-hotpot');
      final food = await opened.saveOption(
        name: '自选面食',
        periods: {MealPeriod.lunch},
        category: '面食',
      );
      expect(food.option!.art, 'noodle');
      final unknown = await opened.saveOption(
        name: '自选未知菜',
        periods: {MealPeriod.lunch},
      );
      expect(unknown.option!.art, 'plate');
      final unknownShop = await opened.saveOption(
        name: '自选未知店',
        periods: {MealPeriod.lunch},
        scenario: MealScenario.restaurant.name,
      );
      expect(unknownShop.option!.art, 'storefront');
      expect(
        (await (await reopen()).options())
            .firstWhere((option) => option.id == created.option!.id)
            .art,
        'shop-hotpot',
      );
    },
  );
}
