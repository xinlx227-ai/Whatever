import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-scenarios-');
    databasePath = path.join(directory.path, 'meal.sqlite');
  });

  tearDown(() async {
    await repository?.close();
    await directory.delete(recursive: true);
  });

  test(
    'fresh installation contains exactly the accepted scenario inventories',
    () async {
      final options = await (await open()).options();
      final expected = <String, Map<String, (Set<String>, Set<MealPeriod>)>>{};
      void group(
        String scenario,
        String names,
        String categories,
        Set<MealPeriod> periods,
      ) {
        final inventory = expected.putIfAbsent(scenario, () => {});
        for (final name in names.split('、')) {
          inventory[name] = (categories.split('、').toSet(), periods);
        }
      }

      const lunchDinner = {MealPeriod.lunch, MealPeriod.dinner};
      const lunchDinnerNight = {...lunchDinner, MealPeriod.lateNight};
      const breakfastLunch = {MealPeriod.breakfast, MealPeriod.lunch};
      const breakfastLunchDinner = {...breakfastLunch, MealPeriod.dinner};
      const breakfastDinnerNight = {
        MealPeriod.breakfast,
        MealPeriod.dinner,
        MealPeriod.lateNight,
      };
      const breakfastNight = {MealPeriod.breakfast, MealPeriod.lateNight};
      const dinnerNight = {MealPeriod.dinner, MealPeriod.lateNight};
      const allPeriods = {...MealPeriod.values};
      group('eat', '黄焖鸡米饭、宫保鸡丁盖饭、红烧肉盖饭', '盖饭套餐', lunchDinner);
      group('eat', '牛肉面、炸酱面、热干面、炒面', '面食', lunchDinnerNight);
      group('eat', '桂林米粉、螺蛳粉、酸辣粉', '粉类', lunchDinnerNight);
      group('eat', '水饺、锅贴、馄饨', '饺子馄饨', lunchDinnerNight);
      group('eat', '小笼包、煎饼果子、鸡蛋灌饼', '包点饼类', breakfastLunch);
      group('eat', '肉夹馍', '包点饼类', breakfastLunchDinner);
      group('eat', '皮蛋瘦肉粥、杂粮粥、小米粥、南瓜粥', '粥类', breakfastDinnerNight);
      group('eat', '蔬菜沙拉、鸡胸肉杂粮饭', '轻食', lunchDinner);
      group('eat', '金枪鱼三明治、鸡蛋蔬菜卷', '轻食', breakfastLunchDinner);
      group('eat', '汉堡套餐、披萨', '西式快餐', lunchDinner);
      group('eat', '炸鸡套餐', '西式快餐', lunchDinnerNight);
      group('eat', '豆浆、牛奶、豆奶、酸奶', '饮品', allPeriods);
      group('cook', '番茄炒蛋', '家常菜、快手菜、下饭菜', lunchDinner);
      group('cook', '土豆炖牛肉、红烧排骨、香菇滑鸡', '家常菜', lunchDinner);
      group('cook', '青椒炒蛋、酸辣土豆丝、蒜蓉西兰花、手撕包菜', '快手菜', lunchDinner);
      group('cook', '宫保鸡丁、鱼香肉丝、麻婆豆腐、回锅肉', '下饭菜', lunchDinner);
      group('cook', '拍黄瓜、凉拌木耳、小葱拌豆腐、凉拌三丝', '清爽小菜', lunchDinner);
      group('cook', '紫菜蛋花汤、冬瓜排骨汤、玉米排骨汤、菌菇豆腐汤', '汤羹', lunchDinner);
      group('cook', '鸡蛋羹', '汤羹', breakfastNight);
      group('cook', '鸡蛋饼', '主食、快手菜', breakfastNight);
      group('cook', '番茄鸡蛋面、青菜鸡蛋面、小米粥、南瓜粥', '主食', breakfastNight);
      group('restaurant', '海底捞、呷哺呷哺', '火锅', lunchDinnerNight);
      group('restaurant', '木屋烧烤、很久以前羊肉串', '烧烤', dinnerNight);
      group('restaurant', '西贝莜面村、外婆家', '中餐', lunchDinner);
      group('restaurant', '必胜客、萨莉亚', '西餐', lunchDinner);
      group('restaurant', '肯德基、麦当劳', '快餐', allPeriods);
      group('restaurant', '比格比萨、汉巴味德', '自助餐', lunchDinner);
      expect(options, hasLength(70));
      expect(options.map((option) => option.id).toSet(), hasLength(70));
      for (final scenario in MealScenario.values) {
        final pool = options
            .where((option) => option.scenario == scenario.name)
            .toList();
        expect(
          pool.map((option) => option.name).toSet(),
          expected[scenario.name]!.keys.toSet(),
        );
        expect(
          pool.length,
          {'eat': 32, 'cook': 26, 'restaurant': 12}[scenario.name],
        );
        for (final option in pool) {
          final approved = expected[scenario.name]![option.name]!;
          expect(option.categories, approved.$1, reason: option.name);
          expect(option.periods, approved.$2, reason: option.name);
          expect(option.categories, contains(option.category));
          expect(
            option.isBuiltIn && option.isActive && !option.isDeleted,
            isTrue,
          );
          expect(option.address, isNull);
          expect(option.notes, isNull);
        }
      }
      expect(
        {for (final option in options.take(8)) option.id: option.name},
        {
          'rice': '黄焖鸡米饭',
          'noodles': '牛肉面',
          'buns': '小笼包',
          'pancake': '煎饼果子',
          'porridge': '皮蛋瘦肉粥',
          'burger': '汉堡套餐',
          'soy-milk': '豆浆',
          'soy-beverage': '豆奶',
        },
      );
    },
  );

  test(
    'restaurant edits persist while builtin food memberships stay protected',
    () async {
      final opened = await open();
      var options = await opened.options();
      final restaurant = options.firstWhere((option) => option.name == '海底捞');
      final saved = await opened.saveOption(
        id: restaurant.id,
        name: '附近海底捞',
        scenario: 'restaurant',
        category: restaurant.category,
        periods: {MealPeriod.breakfast},
        address: '  新街 8 号  ',
        notes: '  提前预约  ',
        imagePath: '/owned/store.jpg',
        confirmSameFood: true,
      );
      expect(saved.changed, isTrue);
      await opened.setOptionActive(restaurant.id, false);
      final reopened = await reopen();
      options = await reopened.options();
      final edited = options.firstWhere((option) => option.id == restaurant.id);
      expect(edited.name, '附近海底捞');
      expect(edited.periods, {MealPeriod.breakfast});
      expect(edited.address, '新街 8 号');
      expect(edited.notes, '提前预约');
      expect(edited.imagePath, '/owned/store.jpg');
      expect(edited.isActive, isFalse);
      expect(
        (await reopened.saveOption(
          id: edited.id,
          name: edited.name,
          scenario: 'restaurant',
          category: '快餐',
          periods: edited.periods,
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await reopened.saveOption(
          id: edited.id,
          name: edited.name,
          scenario: 'restaurant',
          category: edited.category,
          periods: edited.periods,
        )).status,
        OptionMutationStatus.unchanged,
      );
      final cleared = await reopened.saveOption(
        id: edited.id,
        name: edited.name,
        scenario: 'restaurant',
        category: edited.category,
        periods: edited.periods,
        address: ' ',
        notes: '',
      );
      expect(cleared.changed, isTrue);
      expect(cleared.option!.address, isNull);
      expect(cleared.option!.notes, isNull);
      final dish = options.firstWhere((option) => option.name == '番茄炒蛋');
      expect(
        (await reopened.saveOption(
          id: dish.id,
          name: dish.name,
          scenario: 'cook',
          category: dish.category,
          periods: {MealPeriod.breakfast},
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await reopened.saveOption(
          id: dish.id,
          name: dish.name,
          scenario: 'cook',
          category: '快手菜',
          periods: dish.periods,
        )).status,
        OptionMutationStatus.invalid,
      );
      final renamed = await reopened.saveOption(
        id: dish.id,
        name: '自家番茄炒蛋',
        scenario: 'cook',
        category: dish.category,
        periods: dish.periods,
        confirmSameFood: true,
      );
      expect(renamed.changed, isTrue);
      expect(renamed.option!.categories, {'家常菜', '快手菜', '下饭菜'});
      final persisted = (await (await reopen()).options()).firstWhere(
        (option) => option.id == dish.id,
      );
      expect(persisted.categories, {'家常菜', '快手菜', '下饭菜'});
    },
  );

  test(
    'custom categories stay single and same names are independent per scenario',
    () async {
      final opened = await open();
      for (final scenario in MealScenario.values) {
        await opened.saveCategory(name: '私房推荐', scenario: scenario);
        await opened.saveCategory(name: '常用', scenario: scenario);
        final result = await opened.saveOption(
          name: '我的选择',
          scenario: scenario.name,
          category: '私房推荐',
          periods: {MealPeriod.lunch, MealPeriod.dinner},
        );
        expect(result.changed, isTrue);
        expect(result.option!.categories, {'私房推荐'});
        final changed = await opened.saveOption(
          id: result.option!.id,
          name: result.option!.name,
          scenario: scenario.name,
          category: '常用',
          periods: result.option!.periods,
        );
        expect(changed.option!.categories, {'常用'});
      }
      final options = await (await reopen()).options();
      expect(options.where((option) => !option.isBuiltIn), hasLength(3));
      expect(
        options
            .where((option) => !option.isBuiltIn)
            .every(
              (option) =>
                  option.categories.length == 1 && option.category == '常用',
            ),
        isTrue,
      );
      expect(
        (await repository!.saveOption(
          name: 'Missing period',
          scenario: 'restaurant',
          periods: {},
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await repository!.saveOption(
          name: 'Unknown scenario',
          scenario: 'unknown',
          periods: {MealPeriod.lunch},
        )).status,
        OptionMutationStatus.invalid,
      );
    },
  );

  test(
    'v3 upgrade preserves identities, user display edits, custom categories and history',
    () async {
      final timestamp = DateTime.utc(2026, 10, 6, 4);
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) async {
            await database.execute('''
            CREATE TABLE options (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, art TEXT NOT NULL,
              scenario TEXT NOT NULL DEFAULT 'eat', category TEXT NOT NULL DEFAULT '未分类',
              is_builtin INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1,
              is_deleted INTEGER NOT NULL DEFAULT 0, image_path TEXT
            )
          ''');
            await database.execute(
              'CREATE TABLE option_periods (option_id TEXT NOT NULL REFERENCES options(id), period TEXT NOT NULL, PRIMARY KEY (option_id, period))',
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
            for (final option in seedOptions.take(8)) {
              await database.insert('options', {
                'id': option.id,
                'name': option.id == 'rice' ? '私藏黄焖鸡' : option.name,
                'art': option.art,
                'category': option.id == 'rice' ? '米饭套餐' : '未分类',
                'is_active': option.id == 'rice' ? 0 : 1,
                'image_path': option.id == 'rice' ? '/owned/rice.jpg' : null,
              });
              for (final period in option.periods) {
                await database.insert('option_periods', {
                  'option_id': option.id,
                  'period': period.name,
                });
              }
            }
            await database.insert('options', {
              'id': 'custom-old',
              'name': '旧选项',
              'art': 'plate',
              'category': '米饭套餐',
              'is_builtin': 0,
              'is_active': 0,
              'is_deleted': 1,
              'image_path': '/owned/custom.jpg',
            });
            await database.insert('option_periods', {
              'option_id': 'custom-old',
              'period': 'dinner',
            });
            await database.insert('options', {
              'id': 'restaurant-haidilao',
              'name': '我的海底捞',
              'art': 'storefront',
              'scenario': 'restaurant',
              'category': '火锅',
              'is_active': 0,
            });
            await database.insert('option_periods', {
              'option_id': 'restaurant-haidilao',
              'period': 'breakfast',
            });
            for (final id in ['rice', 'custom-old', 'restaurant-haidilao']) {
              await database.insert('history_records', {
                'operation_id': 'old-$id',
                'confirmed_at': timestamp.microsecondsSinceEpoch,
                'period': id == 'rice'
                    ? 'lunch'
                    : id == 'custom-old'
                    ? 'dinner'
                    : 'breakfast',
              });
              await database.insert('history_items', {
                'operation_id': 'old-$id',
                'position': 0,
                'option_id': id,
              });
            }
          },
        ),
      );
      await legacy.close();
      final opened = await open();
      final options = await opened.options();
      expect(options, hasLength(71));
      final rice = options.firstWhere((option) => option.id == 'rice');
      expect(rice.name, '私藏黄焖鸡');
      expect(rice.imagePath, '/owned/rice.jpg');
      expect(rice.isActive, isFalse);
      expect(rice.category, '盖饭套餐');
      expect(rice.categories, {'盖饭套餐'});
      final custom = options.firstWhere((option) => option.id == 'custom-old');
      expect(custom.categories, {'米饭套餐'});
      expect(custom.periods, {MealPeriod.dinner});
      expect(custom.isDeleted, isTrue);
      expect(custom.imagePath, '/owned/custom.jpg');
      final restaurant = options.firstWhere(
        (option) => option.id == 'restaurant-haidilao',
      );
      expect(restaurant.name, '我的海底捞');
      expect(restaurant.periods, {MealPeriod.breakfast});
      expect(restaurant.isActive, isFalse);
      final preferences = await opened.preferences();
      expect(preferences.mode, DrawMode.cards);
      expect(preferences.excludeYesterday, isTrue);
      final history = await (await reopen()).history();
      expect(history, hasLength(3));
      expect(history.map((entry) => entry.option.id).toSet(), {
        'rice',
        'custom-old',
        'restaurant-haidilao',
      });
      expect(history.every((entry) => entry.confirmedAt == timestamp), isTrue);
      expect(
        history.firstWhere((entry) => entry.option.id == 'rice').option.name,
        '私藏黄焖鸡',
      );
      expect(
        history
            .firstWhere((entry) => entry.option.id == 'custom-old')
            .option
            .isDeleted,
        isTrue,
      );
      expect(
        history
            .firstWhere((entry) => entry.option.id == restaurant.id)
            .option
            .periods,
        {MealPeriod.breakfast},
      );
      final inspector = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        expect(await inspector.getVersion(), 8);
        expect(await inspector.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await inspector.close();
      }
    },
  );

  test(
    'v3 expansion keeps same-name identities without reactivation or duplicate seeds',
    () async {
      final now = DateTime(2026, 10, 7, 12);
      final yesterday = DateTime(2026, 10, 6, 12).toUtc();
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) async {
            await database.execute('''
            CREATE TABLE options (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, art TEXT NOT NULL,
              scenario TEXT NOT NULL DEFAULT 'eat', category TEXT NOT NULL DEFAULT '未分类',
              is_builtin INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1,
              is_deleted INTEGER NOT NULL DEFAULT 0, image_path TEXT
            )
          ''');
            await database.execute(
              'CREATE TABLE option_periods (option_id TEXT NOT NULL REFERENCES options(id), period TEXT NOT NULL, PRIMARY KEY (option_id, period))',
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
              'mode': 'wheel',
              'exclude_yesterday': 1,
            });
            for (final option in seedOptions.take(8)) {
              await database.insert('options', {
                'id': option.id,
                'name': option.id == 'rice' ? '披萨' : option.name,
                'art': option.art,
                'image_path': option.id == 'rice' ? '/owned/renamed.jpg' : null,
              });
              for (final period in option.periods) {
                await database.insert('option_periods', {
                  'option_id': option.id,
                  'period': period.name,
                });
              }
            }
            for (final row in [
              {
                'id': 'custom-active',
                'name': '  牛奶  ',
                'is_active': 1,
                'is_deleted': 0,
              },
              {
                'id': 'custom-inactive',
                'name': '红烧肉盖饭',
                'is_active': 0,
                'is_deleted': 0,
              },
              {
                'id': 'custom-deleted',
                'name': '酸奶',
                'is_active': 0,
                'is_deleted': 1,
              },
            ]) {
              final id = row['id']! as String;
              await database.insert('options', {
                ...row,
                'art': 'plate',
                'category': '我的分类',
                'is_builtin': 0,
                'image_path': '/owned/$id.jpg',
              });
              await database.insert('option_periods', {
                'option_id': id,
                'period': 'lunch',
              });
            }
            // A match in another pool must not suppress an eating seed.
            await database.insert('options', {
              'id': 'custom-cook',
              'name': '肉夹馍',
              'art': 'plate',
              'scenario': 'cook',
              'category': '自己的主食',
              'is_builtin': 0,
            });
            await database.insert('option_periods', {
              'option_id': 'custom-cook',
              'period': 'lunch',
            });
            for (final id in [
              'rice',
              'custom-active',
              'custom-inactive',
              'custom-deleted',
            ]) {
              await database.insert('history_records', {
                'operation_id': 'old-$id',
                'confirmed_at': yesterday.microsecondsSinceEpoch,
                'period': 'lunch',
              });
              await database.insert('history_items', {
                'operation_id': 'old-$id',
                'position': 0,
                'option_id': id,
              });
            }
          },
        ),
      );
      await legacy.close();
      final opened = await open();
      final options = await opened.options();
      final eating = options
          .where((option) => option.scenario == 'eat')
          .toList();
      expect(
        eating.map((option) => normalizedOptionName(option.name)).toSet(),
        hasLength(eating.length),
      );
      for (final pair in [
        ('牛奶', 'custom-active'),
        ('红烧肉盖饭', 'custom-inactive'),
        ('酸奶', 'custom-deleted'),
        ('披萨', 'rice'),
      ]) {
        expect(
          eating
              .singleWhere(
                (option) => normalizedOptionName(option.name) == pair.$1,
              )
              .id,
          pair.$2,
        );
      }
      expect(
        options.map((option) => option.id),
        isNot(
          anyOf(
            contains('eat-milk'),
            contains('eat-braised-pork-rice'),
            contains('eat-yogurt'),
            contains('eat-pizza'),
          ),
        ),
      );
      for (final id in ['custom-active', 'custom-inactive', 'custom-deleted']) {
        final option = options.singleWhere((option) => option.id == id);
        expect(option.categories, {'我的分类'});
        expect(option.periods, {MealPeriod.lunch});
        expect(option.imagePath, '/owned/$id.jpg');
        expect(option.isBuiltIn, isFalse);
        expect(option.isActive, id == 'custom-active');
        expect(option.isDeleted, id == 'custom-deleted');
      }
      final active = options.singleWhere(
        (option) => option.id == 'custom-active',
      );
      expect(active.name, '  牛奶  ');
      final rice = options.singleWhere((option) => option.id == 'rice');
      expect(rice.imagePath, '/owned/renamed.jpg');
      expect(rice.category, '盖饭套餐');
      expect(
        options.singleWhere((option) => option.id == 'eat-roujiamo').scenario,
        'eat',
      );
      expect(
        options.singleWhere((option) => option.id == 'custom-cook').scenario,
        'cook',
      );
      final inactive = options.singleWhere(
        (option) => option.id == 'custom-inactive',
      );
      expect(
        (await opened.saveOption(
          id: inactive.id,
          name: inactive.name,
          category: inactive.category,
          periods: inactive.periods,
        )).status,
        OptionMutationStatus.unchanged,
      );
      final controller = MealController(repository: opened, clock: () => now);
      try {
        await controller.initialize();
        expect(controller.history.map((entry) => entry.option.id).toSet(), {
          'rice',
          'custom-active',
          'custom-inactive',
          'custom-deleted',
        });
        expect(
          controller.candidates.map((option) => option.id),
          isNot(
            anyOf(
              contains('rice'),
              contains('custom-active'),
              contains('custom-inactive'),
              contains('custom-deleted'),
            ),
          ),
        );
        expect(
          await controller.updatePreferences(const MealPreferences()),
          isTrue,
        );
        expect(
          controller.candidates.map((option) => option.id),
          contains('custom-active'),
        );
        controller.excludeForSession('custom-active');
        expect(
          controller.candidates.where(
            (option) => normalizedOptionName(option.name) == '牛奶',
          ),
          isEmpty,
        );
      } finally {
        controller.dispose();
      }
      final reopened = await reopen();
      final history = await reopened.history();
      expect(history, hasLength(4));
      expect(
        history
            .singleWhere((entry) => entry.option.id == 'custom-deleted')
            .option
            .isDeleted,
        isTrue,
      );
      expect(
        (await reopened.options()).map((option) => option.id).toSet(),
        options.map((option) => option.id).toSet(),
      );
    },
  );
}
