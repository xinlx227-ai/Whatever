import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/local_recognition.dart';
import 'package:whatever/domain/meal.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  const recognition = LocalRecognition();
  const periods = {MealPeriod.lunch, MealPeriod.dinner};

  test(
    'unknown same-branch spelling rename retains explicit confirmation',
    () async {
      final created = await repository.saveOption(
        name: '街角小馆（东街店）',
        scenario: 'restaurant',
        periods: periods,
      );
      expect(created.succeeded, isTrue);
      final pending = await repository.saveOption(
        id: created.option!.id,
        name: '街角小館（东街店）',
        scenario: 'restaurant',
        periods: periods,
      );
      expect(pending.status, OptionMutationStatus.renameConfirmationRequired);
      final saved = await repository.saveOption(
        id: created.option!.id,
        name: '街角小館（东街店）',
        scenario: 'restaurant',
        periods: periods,
        confirmSameFood: true,
      );
      expect(saved.succeeded, isTrue);
      expect(saved.option!.id, created.option!.id);
    },
  );

  Future<void> reopen() async {
    await repository.close();
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
  }

  Future<Database> inspect() => databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  Future<FoodOption> legacyOption(
    String id,
    String name, {
    String scenario = 'eat',
    bool deleted = false,
    bool active = true,
    String? image,
  }) async {
    final database = await inspect();
    try {
      await database.insert('options', {
        'id': id,
        'name': name,
        'art': 'plate',
        'scenario': scenario,
        'category': '未分类',
        'is_builtin': 0,
        'is_active': active && !deleted ? 1 : 0,
        'is_deleted': deleted ? 1 : 0,
        'image_path': image,
      });
      await database.insert('option_categories', {
        'option_id': id,
        'category': '未分类',
      });
      for (final period in periods) {
        await database.insert('option_periods', {
          'option_id': id,
          'period': period.name,
        });
      }
    } finally {
      await database.close();
    }
    return (await repository.options()).singleWhere((value) => value.id == id);
  }

  Future<void> confirm(FoodOption option, String operationId) =>
      repository.confirm(
        ConfirmationOperation(
          operationId: operationId,
          confirmedAt: DateTime(2026, 10, 10, 12),
          period: MealPeriod.lunch,
          option: option,
        ),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-recognition-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
  });

  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  for (final names in [
    ('街角小馆（东街店）', '街角小馆（東街店）'),
    ('街角小馆（冬街店）', '街角小馆（东街店）'),
    ('街角小馆（莘莊店）', '街角小馆（莘庄店）'),
    ('肯德基（东街店）', 'KFC（東街店）'),
    ('肯德基（冬街店）', '肯德基（东街店）'),
    ('肯德基（冬街店）', '肯德基东街店'),
    ('肯德基（莘莊店）', '肯德基（莘庄店）'),
  ]) {
    test(
      'branch spelling correction requires confirmation: ${names.$1}',
      () async {
        final created = await repository.saveOption(
          name: names.$1,
          scenario: 'restaurant',
          periods: periods,
        );
        expect(created.succeeded, isTrue);
        final original = created.option!;
        await confirm(original, 'branch-spelling-history');
        final pending = await repository.saveOption(
          id: original.id,
          name: names.$2,
          scenario: 'restaurant',
          periods: periods,
        );
        expect(pending.status, OptionMutationStatus.renameConfirmationRequired);
        expect(
          (await repository.options())
              .singleWhere((value) => value.id == original.id)
              .name,
          original.name,
        );
        final saved = await repository.saveOption(
          id: original.id,
          name: names.$2,
          scenario: 'restaurant',
          periods: periods,
          confirmSameFood: true,
        );
        expect(saved.succeeded, isTrue);
        expect(saved.option!.id, original.id);
        expect(saved.option!.recognitionId, original.recognitionId);
        await reopen();
        final persisted = (await repository.options()).singleWhere(
          (value) => value.id == original.id,
        );
        expect(persisted.name, names.$2);
        expect(persisted.recognitionId, original.recognitionId);
        final history = (await repository.history()).single;
        expect(history.option.id, original.id);
        expect(history.option.name, names.$2);
        expect(history.operationId, 'branch-spelling-history');
        expect(history.confirmedAt, DateTime(2026, 10, 10, 12).toUtc());
        if (names.$2.contains('东街店') || names.$2.contains('東街店')) {
          for (final confirmSameFood in [false, true]) {
            final conflict = await repository.saveOption(
              id: original.id,
              name: '${names.$1.split('（').first}（西街店）',
              scenario: 'restaurant',
              periods: periods,
              confirmSameFood: confirmSameFood,
            );
            expect(conflict.status, OptionMutationStatus.invalid);
            expect((await repository.history()).single.option.name, names.$2);
          }
        }
      },
    );
  }

  test(
    'explicit different branch remains invalid after confirmation',
    () async {
      final created = await repository.saveOption(
        name: '街角小馆（东街店）',
        scenario: 'restaurant',
        periods: periods,
      );
      for (final confirmSameFood in [false, true]) {
        final result = await repository.saveOption(
          id: created.option!.id,
          name: '街角小馆（西街店）',
          scenario: 'restaurant',
          periods: periods,
          confirmSameFood: confirmSameFood,
        );
        expect(result.status, OptionMutationStatus.invalid);
      }
    },
  );

  test(
    'ambiguous soy wording offers both protected options without hard blocking',
    () async {
      final result = await repository.saveOption(name: '豆乳', periods: periods);
      expect(result.status, OptionMutationStatus.uncertainDuplicate);
      expect(result.matches.map((value) => value.id).toSet(), {
        'soy-milk',
        'soy-beverage',
      });
      expect(result.option, isNull);
      final added = await repository.saveOption(
        name: '豆乳',
        periods: periods,
        allowUncertainDuplicate: true,
      );
      expect(added.changed, isTrue);
      expect(added.option!.recognitionId, isNull);
      expect(added.option!.category, '未分类');
    },
  );

  test(
    'confirmed aliases block active and inactive identities without overrides',
    () async {
      final original = (await repository.options()).singleWhere(
        (value) => value.id == 'noodles',
      );
      for (final name in ['牛肉面微辣', '牛肉面加蛋', '牛肉面少油']) {
        final result = await repository.saveOption(
          name: name,
          periods: periods,
          allowUncertainDuplicate: true,
          confirmRestore: true,
        );
        expect(result.status, OptionMutationStatus.duplicate);
        expect(result.matches.map((value) => value.id), [original.id]);
        expect(result.changed, isFalse);
      }
      await repository.setOptionActive(original.id, false);
      final result = await repository.saveOption(
        name: '牛肉面少油',
        periods: periods,
      );
      expect(result.status, OptionMutationStatus.duplicate);
      expect(result.option!.isActive, isFalse);
      expect(
        (await repository.options()).where((value) => value.id == original.id),
        hasLength(1),
      );
    },
  );

  test(
    'unknown rename asks, known identity persists, history uses updated display',
    () async {
      final original = (await repository.options()).singleWhere(
        (value) => value.id == 'noodles',
      );
      await confirm(original, 'rename-history');
      final prompt = await repository.saveOption(
        id: original.id,
        name: '  妈妈拿手餐  ',
        category: original.category,
        periods: original.periods,
      );
      expect(prompt.status, OptionMutationStatus.renameConfirmationRequired);
      final renamed = await repository.saveOption(
        id: original.id,
        name: '  妈妈拿手餐  ',
        category: original.category,
        periods: original.periods,
        confirmSameFood: true,
      );
      expect(renamed.option!.name, '妈妈拿手餐');
      expect(renamed.option!.recognitionId, original.recognitionId);
      final uncertainAfterRename = await repository.saveOption(
        name: '牛肉面豪华版',
        periods: periods,
      );
      expect(
        uncertainAfterRename.status,
        OptionMutationStatus.uncertainDuplicate,
      );
      expect(uncertainAfterRename.matches.single.id, original.id);
      await reopen();
      final history = (await repository.history()).single;
      expect(history.option.id, original.id);
      expect(history.option.name, '妈妈拿手餐');
      expect(history.operationId, 'rename-history');
      expect(history.confirmedAt, DateTime(2026, 10, 10, 12).toUtc());
      expect(
        (await repository.saveOption(name: '牛肉面加蛋', periods: periods)).status,
        OptionMutationStatus.duplicate,
      );
      final noOp = await repository.saveOption(
        id: original.id,
        name: '妈妈拿手餐',
        category: original.category,
        periods: original.periods,
      );
      expect(noOp.status, OptionMutationStatus.unchanged);
    },
  );

  test(
    'clear identity changes remain invalid after same-food confirmation',
    () async {
      final original = (await repository.options()).singleWhere(
        (value) => value.id == 'noodles',
      );
      for (final name in ['鸡肉面', '番茄鸡蛋汤', '番茄鸡蛋盖饭']) {
        final result = await repository.saveOption(
          id: original.id,
          name: name,
          category: original.category,
          periods: original.periods,
          confirmSameFood: true,
          allowUncertainDuplicate: true,
        );
        expect(result.status, OptionMutationStatus.invalid, reason: name);
      }
      expect(
        (await repository.options())
            .singleWhere((value) => value.id == original.id)
            .name,
        original.name,
      );
    },
  );

  test(
    'unrecognized old display names are not retained as per-option aliases',
    () async {
      final created = await repository.saveOption(
        name: 'My Dish',
        periods: periods,
      );
      final renamed = await repository.saveOption(
        id: created.option!.id,
        name: 'Family Dish',
        periods: periods,
        confirmSameFood: true,
      );
      expect(renamed.status, OptionMutationStatus.saved);
      await reopen();
      final recreated = await repository.saveOption(
        name: 'My Dish',
        periods: periods,
      );
      expect(recreated.status, OptionMutationStatus.saved);
      expect(recreated.option!.id, isNot(created.option!.id));
    },
  );

  test(
    'uncertain duplicates allow creation only after explicit override',
    () async {
      final prompt = await repository.saveOption(
        name: '牛肉面豪华版',
        periods: periods,
      );
      expect(prompt.status, OptionMutationStatus.uncertainDuplicate);
      expect(prompt.matches.map((value) => value.id), contains('noodles'));
      expect(prompt.changed, isFalse);
      final result = await repository.saveOption(
        name: '牛肉面豪华版',
        periods: periods,
        allowUncertainDuplicate: true,
      );
      expect(result.status, OptionMutationStatus.saved);
      expect(result.option!.recognitionId, isNull);
    },
  );

  test(
    'legacy collisions expose all matches and mixed live/deleted matches block restoration',
    () async {
      await legacyOption('legacy-alias', '牛肉面少油', deleted: true);
      final result = await repository.saveOption(
        name: '牛肉面加蛋',
        periods: periods,
        confirmRestore: true,
        restoreOptionId: 'legacy-alias',
      );
      expect(result.status, OptionMutationStatus.duplicate);
      expect(result.option, isNull);
      expect(result.matches.map((value) => value.id).toSet(), {
        'noodles',
        'legacy-alias',
      });
      expect(
        (await repository.options())
            .singleWhere((value) => value.id == 'legacy-alias')
            .isDeleted,
        isTrue,
      );
      final original = (await repository.options()).singleWhere(
        (value) => value.id == 'noodles',
      );
      final noOp = await repository.saveOption(
        id: original.id,
        name: original.name,
        category: original.category,
        periods: original.periods,
      );
      expect(noOp.status, OptionMutationStatus.unchanged);
    },
  );

  test(
    'multiple deleted identities require selection and restore saves the submitted form',
    () async {
      final first = await legacyOption(
        'deleted-first',
        '番茄炒蛋',
        image: 'old-image.jpg',
      );
      final second = await legacyOption('deleted-second', '西红柿炒蛋');
      await confirm(first, 'first-history');
      await confirm(second, 'second-history');
      await repository.deleteOption(first.id);
      await repository.deleteOption(second.id);
      final prompt = await repository.saveOption(
        name: '西红柿炒鸡蛋',
        periods: {MealPeriod.breakfast},
        confirmRestore: true,
      );
      expect(prompt.status, OptionMutationStatus.restorationRequired);
      expect(prompt.option, isNull);
      expect(prompt.matches.map((value) => value.id).toSet(), {
        first.id,
        second.id,
      });
      final wrongTarget = await repository.saveOption(
        name: '西红柿炒鸡蛋',
        periods: periods,
        confirmRestore: true,
        restoreOptionId: 'missing',
      );
      expect(wrongTarget.status, OptionMutationStatus.restorationRequired);
      final result = await repository.saveOption(
        name: '  西红柿炒鸡蛋  ',
        periods: {MealPeriod.breakfast},
        category: '轻食',
        confirmRestore: true,
        restoreOptionId: first.id,
      );
      expect(result.status, OptionMutationStatus.saved);
      expect(result.option!.id, first.id);
      expect(result.option!.isActive, isTrue);
      expect(result.option!.isDeleted, isFalse);
      expect(result.option!.name, '西红柿炒鸡蛋');
      expect(result.option!.category, '轻食');
      expect(result.option!.periods, {MealPeriod.breakfast});
      expect(result.option!.imagePath, 'old-image.jpg');
      await reopen();
      final history = await repository.history();
      expect(
        history
            .singleWhere((value) => value.operationId == 'first-history')
            .option
            .name,
        '西红柿炒鸡蛋',
      );
      expect(
        history
            .singleWhere((value) => value.operationId == 'second-history')
            .option
            .isDeleted,
        isTrue,
      );
    },
  );

  test(
    'restaurant address conflicts guide explicit branches; restore can clear address and notes',
    () async {
      final created = await repository.saveOption(
        name: '街角小馆',
        scenario: 'restaurant',
        address: '东街 1 号',
        notes: '靠窗',
        imagePath: 'restaurant.jpg',
        periods: periods,
      );
      final conflict = await repository.saveOption(
        name: '街角小馆',
        scenario: 'restaurant',
        address: '西街 2 号',
        periods: periods,
      );
      expect(conflict.status, OptionMutationStatus.duplicate);
      expect(conflict.message, contains('分店'));
      expect(conflict.message, contains('东街店'));
      await repository.deleteOption(created.option!.id);
      final restored = await repository.saveOption(
        name: '街角小馆',
        scenario: 'restaurant',
        address: '',
        notes: '',
        category: '中餐',
        periods: {MealPeriod.breakfast},
        confirmRestore: true,
      );
      expect(restored.option!.id, created.option!.id);
      expect(restored.option!.address, isNull);
      expect(restored.option!.notes, isNull);
      expect(restored.option!.imagePath, 'restaurant.jpg');
      expect(
        (await repository.saveOption(
          name: '街角小馆（东街店）',
          scenario: 'restaurant',
          periods: periods,
        )).status,
        OptionMutationStatus.saved,
      );
    },
  );

  test(
    'classification follows stable category IDs and manual choices win',
    () async {
      final category = (await repository.categories()).singleWhere(
        (value) => value.id == 'builtin-category-eat-1',
      );
      await repository.saveCategory(id: category.id, name: '面条类');
      final inferred = await repository.saveOption(
        name: '鸡肉面',
        periods: periods,
      );
      expect(inferred.option!.category, '面条类');
      final manual = await repository.saveOption(
        name: '番茄鸡蛋汤',
        periods: periods,
        category: '轻食',
      );
      expect(manual.option!.category, '轻食');
      expect(
        (await repository.saveOption(
          name: 'My  Unknown Dish',
          periods: periods,
        )).option!.name,
        'My  Unknown Dish',
      );
      expect(
        (await repository.saveOption(
          name: 'x',
          periods: periods,
          scenario: 'invalid',
        )).status,
        OptionMutationStatus.invalid,
      );
    },
  );

  test(
    'v7 migration preserves explicit built-in restaurant branches and history',
    () async {
      final original = (await repository.options()).singleWhere(
        (value) => value.id == 'restaurant-kfc',
      );
      await confirm(original, 'branch-history');
      await repository.close();
      final database = await inspect();
      try {
        await database.execute(
          'ALTER TABLE options DROP COLUMN recognition_id',
        );
        await database.update(
          'options',
          {'name': '肯德基（东街店）'},
          where: 'id = ?',
          whereArgs: [original.id],
        );
        await database.execute('DROP TABLE online_recognition_requests');
        await database.execute('DROP TABLE online_recognition_settings');
        await database.setVersion(7);
      } finally {
        await database.close();
      }
      repository = await MealRepository.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final migrated = (await repository.options()).singleWhere(
        (value) => value.id == original.id,
      );
      expect(migrated.name, '肯德基（东街店）');
      expect(
        migrated.recognitionId,
        recognition.identity('KFC（东街店）', 'restaurant'),
      );
      final brand = await repository.saveOption(
        name: 'KFC',
        scenario: 'restaurant',
        periods: periods,
      );
      expect(brand.status, OptionMutationStatus.saved);
      expect(brand.option!.id, isNot(original.id));
      final sameBranch = await repository.saveOption(
        name: 'KFC（东街店）',
        scenario: 'restaurant',
        periods: periods,
        allowUncertainDuplicate: true,
      );
      expect(sameBranch.status, OptionMutationStatus.duplicate);
      expect(sameBranch.matches.map((value) => value.id), [original.id]);
      await reopen();
      final history = (await repository.history()).single;
      expect(history.operationId, 'branch-history');
      expect(history.option.id, original.id);
      expect(history.option.name, '肯德基（东街店）');
      expect(history.confirmedAt, DateTime(2026, 10, 10, 12).toUtc());
    },
  );

  test(
    'v7 migration backfills identities while retaining aliases, statuses, edits, and history',
    () async {
      final alias = await legacyOption('legacy-tomato', '西红柿炒蛋');
      await legacyOption('legacy-tomato-other', '番茄炒蛋', deleted: true);
      await confirm(alias, 'legacy-record');
      await repository.setOptionActive(alias.id, false);
      await repository.close();
      final database = await inspect();
      try {
        // Reconstruct the v7 schema with representative legacy user data.
        await database.execute(
          'ALTER TABLE options DROP COLUMN recognition_id',
        );
        await database.update(
          'options',
          {'name': '私房面'},
          where: 'id = ?',
          whereArgs: ['noodles'],
        );
        await database.update(
          'options',
          {'name': '鸡肉面'},
          where: 'id = ?',
          whereArgs: ['rice'],
        );
        await database.execute('DROP TABLE online_recognition_requests');
        await database.execute('DROP TABLE online_recognition_settings');
        await database.execute('PRAGMA user_version = 7');
      } finally {
        await database.close();
      }
      repository = await MealRepository.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final options = await repository.options();
      final migrated = options.singleWhere((value) => value.id == alias.id);
      expect(migrated.name, '西红柿炒蛋');
      expect(migrated.isActive, isFalse);
      expect(migrated.recognitionId, recognition.identity('番茄炒蛋', 'eat'));
      expect(
        options
            .singleWhere((value) => value.id == 'legacy-tomato-other')
            .isDeleted,
        isTrue,
      );
      expect(options.singleWhere((value) => value.id == 'noodles').name, '私房面');
      expect(
        options.singleWhere((value) => value.id == 'noodles').recognitionId,
        recognition.identity('牛肉面', 'eat'),
      );
      expect(
        options.singleWhere((value) => value.id == 'rice').recognitionId,
        recognition.identity('黄焖鸡米饭', 'eat'),
      );
      expect((await repository.history()).single.option.id, alias.id);
      expect((await repository.history()).single.operationId, 'legacy-record');
      final collision = await repository.saveOption(
        name: '西红柿炒鸡蛋',
        periods: periods,
      );
      expect(collision.status, OptionMutationStatus.duplicate);
      expect(collision.matches.map((value) => value.id).toSet(), {
        'legacy-tomato',
        'legacy-tomato-other',
      });
      await reopen();
      expect(
        (await repository.options()).map((value) => value.id).toList(),
        options.map((value) => value.id).toList(),
      );
    },
  );
}
