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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-categories-');
    databasePath = path.join(directory.path, 'meal.sqlite');
  });

  tearDown(() async {
    await repository?.close();
    repository = null;
    await directory.delete(recursive: true);
  });

  test(
    'category registry retains stable scenario identities after reopen',
    () async {
      final opened = await open();
      final categories = await opened.categories();
      expect(categories, hasLength(24));
      expect(categories.map((category) => category.id).toSet(), hasLength(24));
      expect(categories.every((category) => category.isBuiltIn), isTrue);
      expect(categories.any((category) => category.name == '全部'), isFalse);
      for (final scenario in MealScenario.values) {
        final scoped = categories.where(
          (category) => category.scenario == scenario,
        );
        expect(
          scoped.map((category) => category.name).toList(),
          scenarioCategories[scenario],
        );
        expect(scoped.where((category) => category.isFallback), hasLength(1));
      }
      final reopened = await reopen();
      expect(
        (await reopened.categories()).map((category) => category.id).toList(),
        categories.map((category) => category.id).toList(),
      );
    },
  );

  test(
    'category validation is normalized and scenario scoped with no-op saves',
    () async {
      final opened = await open();
      expect((await opened.saveCategory(name: '  Ａ  ')).changed, isTrue);
      final custom = (await opened.categories()).singleWhere(
        (category) => category.name == 'Ａ',
      );
      expect(custom.scenario, MealScenario.eat);
      expect(custom.isBuiltIn, isFalse);
      expect(
        (await opened.saveCategory(id: custom.id, name: ' Ａ ')).status,
        OptionMutationStatus.unchanged,
      );
      expect(
        (await opened.saveCategory(name: 'a')).status,
        OptionMutationStatus.duplicate,
      );
      expect(
        (await opened.saveCategory(
          name: 'a',
          scenario: MealScenario.cook,
        )).changed,
        isTrue,
      );
      expect(
        (await opened.saveCategory(name: ' 全部 ')).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await opened.saveCategory(id: custom.id, name: '全部')).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await opened.saveCategory(name: ' ')).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await opened.saveCategory(id: custom.id, name: '面食')).status,
        OptionMutationStatus.duplicate,
      );
      expect(
        (await opened.saveCategory(id: 'missing', name: '新分类')).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await opened.deleteCategory('missing')).status,
        OptionMutationStatus.invalid,
      );
      final reopened = await reopen();
      expect(
        (await reopened.categories())
            .singleWhere((category) => category.id == custom.id)
            .name,
        'Ａ',
      );
    },
  );

  test(
    'renaming built-ins updates all memberships and preserves read-only classification',
    () async {
      final opened = await open();
      final before = (await opened.options()).singleWhere(
        (option) => option.id == 'cook-tomato-eggs',
      );
      await opened.confirm(
        ConfirmationOperation(
          operationId: 'builtin-meal',
          confirmedAt: DateTime.utc(2026, 10, 7),
          period: MealPeriod.lunch,
          option: before,
        ),
      );
      final categories = await opened.categories();
      final home = categories.singleWhere(
        (category) =>
            category.scenario == MealScenario.cook && category.name == '家常菜',
      );
      final quick = categories.singleWhere(
        (category) =>
            category.scenario == MealScenario.cook && category.name == '快手菜',
      );
      expect(
        (await opened.saveCategory(id: home.id, name: '我的家常')).changed,
        isTrue,
      );
      expect(
        (await opened.saveCategory(id: quick.id, name: '快速料理')).changed,
        isTrue,
      );
      expect(
        (await opened.deleteCategory(home.id)).status,
        OptionMutationStatus.invalid,
      );
      final reopened = await reopen();
      final tomato = (await reopened.options()).singleWhere(
        (option) => option.id == before.id,
      );
      expect(tomato.category, '我的家常');
      expect(tomato.categories, {'我的家常', '快速料理', '下饭菜'});
      expect(
        (await reopened.options())
            .singleWhere((option) => option.id == 'cook-egg-pancake')
            .categories,
        {'主食', '快速料理'},
      );
      expect(
        (await reopened.history()).single.option.categories,
        tomato.categories,
      );
      expect(
        (await reopened.saveOption(
          id: tomato.id,
          name: tomato.name,
          scenario: tomato.scenario,
          category: tomato.category,
          periods: tomato.periods,
        )).status,
        OptionMutationStatus.unchanged,
      );
      expect(
        (await reopened.saveOption(
          id: tomato.id,
          name: tomato.name,
          scenario: tomato.scenario,
          category: '快速料理',
          periods: tomato.periods,
        )).status,
        OptionMutationStatus.invalid,
      );
    },
  );

  test(
    'custom deletion moves active, inactive and deleted options to renamed fallback with history',
    () async {
      final opened = await open();
      for (final scenario in [MealScenario.eat, MealScenario.cook]) {
        await opened.saveCategory(name: '私房', scenario: scenario);
      }
      final categories = await opened.categories();
      final custom = categories.singleWhere(
        (category) =>
            category.scenario == MealScenario.eat && category.name == '私房',
      );
      final fallback = categories.singleWhere(
        (category) =>
            category.scenario == MealScenario.eat && category.isFallback,
      );
      final created = <FoodOption>[];
      for (final name in ['在用', '停用', '已删']) {
        final result = await opened.saveOption(
          name: name,
          category: '私房',
          periods: {MealPeriod.lunch},
          imagePath: '/owned/$name.jpg',
        );
        created.add(result.option!);
      }
      final other = (await opened.saveOption(
        name: '另一场景',
        scenario: 'cook',
        category: '私房',
        periods: {MealPeriod.lunch},
      )).option!;
      await opened.confirm(
        ConfirmationOperation(
          operationId: 'custom-meal',
          confirmedAt: DateTime.utc(2026, 10, 7),
          period: MealPeriod.lunch,
          option: created.last,
        ),
      );
      await opened.setOptionActive(created[1].id, false);
      await opened.deleteOption(created.last.id);
      expect(
        (await opened.saveCategory(id: custom.id, name: '常用')).changed,
        isTrue,
      );
      expect(
        (await opened.options())
            .where((option) => created.any((value) => value.id == option.id))
            .every(
              (option) =>
                  option.categories.length == 1 && option.category == '常用',
            ),
        isTrue,
      );
      expect(
        (await opened.saveCategory(id: fallback.id, name: '其他餐食')).changed,
        isTrue,
      );
      expect((await opened.deleteCategory(custom.id)).changed, isTrue);
      expect(
        (await opened.deleteCategory(fallback.id)).status,
        OptionMutationStatus.invalid,
      );
      final reopened = await reopen();
      final options = await reopened.options();
      for (var index = 0; index < created.length; index++) {
        final option = options.singleWhere(
          (option) => option.id == created[index].id,
        );
        expect(option.category, '其他餐食');
        expect(option.categories, {'其他餐食'});
        expect(option.isActive, index == 0);
        expect(option.isDeleted, index == 2);
        expect(option.imagePath, created[index].imagePath);
      }
      expect(
        options.singleWhere((option) => option.id == other.id).category,
        '私房',
      );
      expect(
        (await reopened.categories()).any(
          (category) => category.id == custom.id,
        ),
        isFalse,
      );
      final history = (await reopened.history()).single;
      expect(history.operationId, 'custom-meal');
      expect(history.option.id, created.last.id);
      expect(history.option.isDeleted, isTrue);
      expect(history.option.category, '其他餐食');
      final defaulted = await reopened.saveOption(
        name: '新餐食',
        periods: {MealPeriod.dinner},
      );
      expect(defaulted.option!.category, '其他餐食');
      expect(
        (await reopened.saveOption(
          name: '失效分类',
          category: '常用',
          periods: {MealPeriod.lunch},
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await reopened.saveOption(
          name: '全部分类',
          category: '全部',
          periods: {MealPeriod.lunch},
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await reopened.saveOption(
          name: '跨场景分类',
          category: '私房',
          periods: {MealPeriod.lunch},
        )).status,
        OptionMutationStatus.invalid,
      );
      final restored = await reopened.saveOption(
        name: created.last.name,
        periods: created.last.periods,
        confirmRestore: true,
      );
      expect(restored.option!.id, created.last.id);
      expect(restored.option!.categories, {'其他餐食'});
    },
  );

  test(
    'failed membership update rolls back registry and primary category rename',
    () async {
      final opened = await open();
      final category = (await opened.categories()).singleWhere(
        (category) =>
            category.scenario == MealScenario.cook && category.name == '家常菜',
      );
      final inspector = await inspect();
      try {
        await inspector.execute('''
        CREATE TRIGGER reject_category_rename BEFORE UPDATE ON option_categories
        BEGIN SELECT RAISE(ABORT, 'Injected category mutation failure'); END
      ''');
        await expectLater(
          opened.saveCategory(id: category.id, name: '新家常'),
          throwsA(isA<DatabaseException>()),
        );
      } finally {
        await inspector.close();
      }
      final reopened = await reopen();
      expect(
        (await reopened.categories())
            .singleWhere((value) => value.id == category.id)
            .name,
        '家常菜',
      );
      final tomato = (await reopened.options()).singleWhere(
        (option) => option.id == 'cook-tomato-eggs',
      );
      expect(tomato.category, '家常菜');
      expect(tomato.categories, {'家常菜', '快手菜', '下饭菜'});
    },
  );

  test(
    'v4 migration preserves exact memberships, user edits, deletions and history',
    () async {
      final timestamp = DateTime.utc(2026, 10, 6, 4);
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) async {
            await database.execute('''
          CREATE TABLE options (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, art TEXT NOT NULL,
            scenario TEXT NOT NULL, category TEXT NOT NULL,
            is_builtin INTEGER NOT NULL, is_active INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL, image_path TEXT, address TEXT, notes TEXT
          )
        ''');
            await database.execute(
              'CREATE TABLE option_periods (option_id TEXT NOT NULL REFERENCES options(id), period TEXT NOT NULL, PRIMARY KEY (option_id, period))',
            );
            await database.execute(
              'CREATE TABLE option_categories (option_id TEXT NOT NULL REFERENCES options(id), category TEXT NOT NULL, PRIMARY KEY (option_id, category))',
            );
            await database.execute(
              'CREATE TABLE history_records (operation_id TEXT PRIMARY KEY, confirmed_at INTEGER NOT NULL, period TEXT NOT NULL)',
            );
            await database.execute(
              'CREATE TABLE history_items (operation_id TEXT NOT NULL REFERENCES history_records(operation_id), position INTEGER NOT NULL, option_id TEXT NOT NULL REFERENCES options(id), PRIMARY KEY (operation_id, position))',
            );
            await database.execute(
              'CREATE TABLE preferences (id INTEGER PRIMARY KEY, mode TEXT NOT NULL, exclude_yesterday INTEGER NOT NULL)',
            );
            await database.insert('preferences', {
              'id': 1,
              'mode': 'cards',
              'exclude_yesterday': 1,
            });
            for (final entry in [
              (
                'cook-tomato-eggs',
                '我家番茄炒蛋',
                'cook',
                '家常菜',
                true,
                false,
                false,
                {'家常菜', '快手菜', '下饭菜', '旧标签'},
              ),
              (
                'custom-deleted',
                '旧餐厅',
                'restaurant',
                '私房',
                false,
                false,
                true,
                {'私房'},
              ),
              ('custom-eat', '私人午餐', 'eat', '私房', false, true, false, {'私房'}),
            ]) {
              await database.insert('options', {
                'id': entry.$1,
                'name': entry.$2,
                'art': 'plate',
                'scenario': entry.$3,
                'category': entry.$4,
                'is_builtin': entry.$5 ? 1 : 0,
                'is_active': entry.$6 ? 1 : 0,
                'is_deleted': entry.$7 ? 1 : 0,
                'image_path': '/owned/${entry.$1}.jpg',
                'address': '旧地址',
                'notes': '旧备注',
              });
              await database.insert('option_periods', {
                'option_id': entry.$1,
                'period': 'breakfast',
              });
              for (final category in entry.$8) {
                await database.insert('option_categories', {
                  'option_id': entry.$1,
                  'category': category,
                });
              }
              await database.insert('history_records', {
                'operation_id': 'old-${entry.$1}',
                'confirmed_at': timestamp.microsecondsSinceEpoch,
                'period': 'breakfast',
              });
              await database.insert('history_items', {
                'operation_id': 'old-${entry.$1}',
                'position': 0,
                'option_id': entry.$1,
              });
            }
          },
        ),
      );
      final beforeOptions = await legacy.query('options');
      final beforeMemberships = await legacy.query('option_categories');
      await legacy.close();
      final opened = await open();
      final categories = await opened.categories();
      expect(
        categories.where((category) => category.name == '私房'),
        hasLength(2),
      );
      expect(
        categories.singleWhere((category) => category.name == '旧标签').isBuiltIn,
        isFalse,
      );
      final inspector = await inspect();
      try {
        expect(await inspector.getVersion(), 9);
        expect(
          await inspector.query(
            'options',
            columns: beforeOptions.first.keys.toList(),
          ),
          beforeOptions,
        );
        expect(await inspector.query('option_categories'), beforeMemberships);
        expect(await inspector.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await inspector.close();
      }
      final reopened = await reopen();
      expect((await reopened.options()), hasLength(3));
      expect(
        (await reopened.options())
            .singleWhere((option) => option.id == 'cook-tomato-eggs')
            .recognitionId,
        isNotNull,
      );
      expect(
        (await reopened.options())
            .singleWhere((option) => option.id == 'cook-tomato-eggs')
            .categories,
        {'家常菜', '快手菜', '下饭菜', '旧标签'},
      );
      final preferences = await reopened.preferences();
      expect(preferences.mode, DrawMode.cards);
      expect(preferences.excludeYesterday, isTrue);
      final history = await reopened.history();
      expect(history, hasLength(3));
      expect(history.every((entry) => entry.confirmedAt == timestamp), isTrue);
      expect(
        history
            .singleWhere((entry) => entry.option.id == 'custom-deleted')
            .option
            .isDeleted,
        isTrue,
      );
      expect(
        history
            .singleWhere((entry) => entry.option.id == 'cook-tomato-eggs')
            .option
            .name,
        '我家番茄炒蛋',
      );
      expect(
        (await reopened.categories()).map((category) => category.id).toList(),
        categories.map((category) => category.id).toList(),
      );
    },
  );
}
