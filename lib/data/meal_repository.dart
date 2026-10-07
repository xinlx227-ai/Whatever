import 'dart:async';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../domain/meal.dart';
import '../domain/meal_preferences.dart';

enum ConfirmationPhase { afterHeaderWritten, beforeAcknowledgement }

typedef ConfirmationFault = FutureOr<void> Function(ConfirmationPhase phase);

class MealRepository {
  MealRepository._(this._database, this._onConfirmationPhase);

  final Database _database;
  final ConfirmationFault? _onConfirmationPhase;
  final Random _idRandom = Random.secure();

  static Future<MealRepository> open({
    required DatabaseFactory factory,
    required String path,
    ConfirmationFault? onConfirmationPhase,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE options (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              art TEXT NOT NULL
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
          await _createPreferences(database);
          await _addLibraryMetadata(database);
          await _addScenarioMetadata(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createPreferences(database);
          }
          if (oldVersion < 3) {
            await _addLibraryMetadata(database);
          }
          if (oldVersion < 4) {
            await _addScenarioMetadata(database);
          }
        },
      ),
    );
    return MealRepository._(database, onConfirmationPhase);
  }

  static Future<void> _addScenarioMetadata(DatabaseExecutor database) async {
    await database.execute('ALTER TABLE options ADD COLUMN address TEXT');
    await database.execute('ALTER TABLE options ADD COLUMN notes TEXT');
    await database.execute('''
      CREATE TABLE option_categories (
        option_id TEXT NOT NULL REFERENCES options(id),
        category TEXT NOT NULL,
        PRIMARY KEY (option_id, category)
      )
    ''');
    await database.execute('''
      INSERT INTO option_categories (option_id, category)
      SELECT id, category FROM options
    ''');
    for (final seed in seedOptions) {
      final existing = await database.query(
        'options',
        where: 'id = ?',
        whereArgs: [seed.id],
      );
      if (existing.isNotEmpty && existing.single['is_builtin'] != 1) continue;
      if (existing.isEmpty) {
        final sameScenario = await database.query(
          'options',
          columns: ['name'],
          where: 'scenario = ?',
          whereArgs: [seed.scenario],
        );
        // Existing identities, including inactive and retained deleted options,
        // take precedence over newly introduced content with the same name.
        final normalizedSeedName = normalizedOptionName(seed.name);
        if (sameScenario.any(
          (row) =>
              normalizedOptionName(row['name']! as String) ==
              normalizedSeedName,
        )) {
          continue;
        }
        await database.insert('options', {
          'id': seed.id,
          'name': seed.name,
          'art': seed.art,
          'scenario': seed.scenario,
          'category': seed.category,
        });
      } else {
        // System content changes never replace display edits or stable identity.
        await database.update(
          'options',
          {'scenario': seed.scenario, 'category': seed.category},
          where: 'id = ?',
          whereArgs: [seed.id],
        );
      }
      await database.delete(
        'option_categories',
        where: 'option_id = ?',
        whereArgs: [seed.id],
      );
      for (final category in seed.categories) {
        await database.insert('option_categories', {
          'option_id': seed.id,
          'category': category,
        });
      }
      // Restaurant applicability belongs to the user once the option exists.
      if (existing.isEmpty || seed.scenario != MealScenario.restaurant.name) {
        await database.delete(
          'option_periods',
          where: 'option_id = ?',
          whereArgs: [seed.id],
        );
        for (final period in seed.periods) {
          await database.insert('option_periods', {
            'option_id': seed.id,
            'period': period.name,
          });
        }
      }
    }
  }

  static Future<void> _addLibraryMetadata(DatabaseExecutor database) async {
    for (final column in [
      "scenario TEXT NOT NULL DEFAULT 'eat'",
      "category TEXT NOT NULL DEFAULT '未分类'",
      'is_builtin INTEGER NOT NULL DEFAULT 1 CHECK (is_builtin IN (0, 1))',
      'is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))',
      'is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))',
      'image_path TEXT',
    ]) {
      await database.execute('ALTER TABLE options ADD COLUMN $column');
    }
  }

  static Future<void> _createPreferences(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        mode TEXT NOT NULL CHECK (mode IN ('wheel', 'cards')),
        exclude_yesterday INTEGER NOT NULL CHECK (exclude_yesterday IN (0, 1))
      )
    ''');
    await database.insert('preferences', {
      'id': 1,
      'mode': DrawMode.wheel.name,
      'exclude_yesterday': 0,
    });
  }

  Future<MealPreferences> preferences() async {
    final row = (await _database.query('preferences')).single;
    return MealPreferences(
      mode: DrawMode.values.byName(row['mode']! as String),
      excludeYesterday: row['exclude_yesterday'] == 1,
    );
  }

  Future<void> savePreferences(MealPreferences preferences) async {
    await _database.insert('preferences', {
      'id': 1,
      'mode': preferences.mode.name,
      'exclude_yesterday': preferences.excludeYesterday ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<FoodOption>> options() => _options(_database);

  Future<List<FoodOption>> _options(DatabaseExecutor executor) async {
    final rows = await executor.query('options', orderBy: 'rowid');
    final periods = await executor.query('option_periods');
    final categories = await executor.query('option_categories');
    return List.unmodifiable(
      rows.map(
        (row) => FoodOption(
          id: row['id']! as String,
          name: row['name']! as String,
          art: row['art']! as String,
          scenario: row['scenario']! as String,
          category: row['category']! as String,
          categories: Set.unmodifiable(
            categories
                .where((category) => category['option_id'] == row['id'])
                .map((category) => category['category']! as String),
          ),
          isBuiltIn: row['is_builtin'] == 1,
          isActive: row['is_active'] == 1,
          isDeleted: row['is_deleted'] == 1,
          imagePath: row['image_path'] as String?,
          address: row['address'] as String?,
          notes: row['notes'] as String?,
          periods: Set.unmodifiable(
            periods
                .where((period) => period['option_id'] == row['id'])
                .map(
                  (period) =>
                      MealPeriod.values.byName(period['period']! as String),
                ),
          ),
        ),
      ),
    );
  }

  Future<OptionMutationResult> saveOption({
    String? id,
    required String name,
    required Set<MealPeriod> periods,
    String category = '未分类',
    String scenario = 'eat',
    String? imagePath,
    String? address,
    String? notes,
    bool confirmRestore = false,
    bool confirmSameFood = false,
  }) => _database.transaction((transaction) async {
    final displayName = name.trim();
    final displayCategory = category.trim();
    if (displayName.isEmpty ||
        periods.isEmpty ||
        displayCategory.isEmpty ||
        !MealScenario.values.any((value) => value.name == scenario)) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '请填写名称、一个分类，并至少选择一个适用时段。',
      );
    }
    final options = await _options(transaction);
    FoodOption? original;
    if (id != null) {
      for (final option in options) {
        if (option.id == id) original = option;
      }
      if (original == null || original.isDeleted) {
        return const OptionMutationResult(
          OptionMutationStatus.invalid,
          message: '这个选项已不存在，请重新打开选项库。',
        );
      }
      if (original.scenario != scenario ||
          (original.isBuiltIn &&
              (original.category != displayCategory ||
                  (scenario != MealScenario.restaurant.name &&
                      !_samePeriods(original.periods, periods))))) {
        return OptionMutationResult(
          OptionMutationStatus.invalid,
          option: original,
          message: '内置餐食的分类和适用时段由系统维护。',
        );
      }
    }
    FoodOption? duplicate;
    final normalized = normalizedOptionName(displayName);
    for (final option in options) {
      if (option.id != id &&
          option.scenario == scenario &&
          normalizedOptionName(option.name) == normalized) {
        duplicate = option;
        break;
      }
    }
    if (duplicate != null) {
      if (id == null && duplicate.isDeleted && !duplicate.isBuiltIn) {
        if (!confirmRestore) {
          return OptionMutationResult(
            OptionMutationStatus.restorationRequired,
            option: duplicate,
            message: '已删除的选项中有同名餐食，是否恢复原选项？',
          );
        }
        original = duplicate;
      } else {
        return OptionMutationResult(
          OptionMutationStatus.duplicate,
          option: duplicate,
          message: duplicate.isActive && !duplicate.isDeleted
              ? '已有同名餐食，请查看已有选项。'
              : '已有同名餐食，可查看并重新启用或恢复原选项。',
        );
      }
    }
    if (id != null &&
        normalizedOptionName(original!.name) != normalized &&
        !confirmSameFood) {
      return OptionMutationResult(
        OptionMutationStatus.renameConfirmationRequired,
        option: original,
        message: '无法判断新名称是否还是同一种餐食，请确认后保存。',
      );
    }
    final option = FoodOption(
      id:
          original?.id ??
          'custom-${List.generate(16, (_) => _idRandom.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
      name: displayName,
      art:
          original?.art ??
          (scenario == MealScenario.restaurant.name ? 'storefront' : 'plate'),
      periods: Set.unmodifiable(periods),
      scenario: scenario,
      category: displayCategory,
      categories: original?.isBuiltIn == true
          ? original!.categories
          : {displayCategory},
      isBuiltIn: original?.isBuiltIn ?? false,
      isActive: original?.isDeleted == true ? true : original?.isActive ?? true,
      imagePath: imagePath ?? original?.imagePath,
      address: scenario == MealScenario.restaurant.name
          ? _optionalText(address, original?.address)
          : null,
      notes: scenario == MealScenario.restaurant.name
          ? _optionalText(notes, original?.notes)
          : null,
    );
    if (original != null && _sameOption(original, option)) {
      return OptionMutationResult(
        OptionMutationStatus.unchanged,
        option: original,
      );
    }
    final values = {
      'name': option.name,
      'art': option.art,
      'scenario': option.scenario,
      'category': option.category,
      'is_builtin': option.isBuiltIn ? 1 : 0,
      'is_active': option.isActive ? 1 : 0,
      'is_deleted': 0,
      'image_path': option.imagePath,
      'address': option.address,
      'notes': option.notes,
    };
    if (original == null) {
      await transaction.insert('options', {'id': option.id, ...values});
    } else {
      await transaction.update(
        'options',
        values,
        where: 'id = ?',
        whereArgs: [option.id],
      );
      await transaction.delete(
        'option_periods',
        where: 'option_id = ?',
        whereArgs: [option.id],
      );
    }
    await transaction.delete(
      'option_categories',
      where: 'option_id = ?',
      whereArgs: [option.id],
    );
    for (final category in option.categories) {
      await transaction.insert('option_categories', {
        'option_id': option.id,
        'category': category,
      });
    }
    for (final period in option.periods) {
      await transaction.insert('option_periods', {
        'option_id': option.id,
        'period': period.name,
      });
    }
    return OptionMutationResult(OptionMutationStatus.saved, option: option);
  });

  static String? _optionalText(String? value, String? original) => value == null
      ? original
      : value.trim().isEmpty
      ? null
      : value.trim();

  static bool _samePeriods(Set<MealPeriod> first, Set<MealPeriod> second) =>
      first.length == second.length && first.containsAll(second);

  static bool _sameOption(FoodOption first, FoodOption second) =>
      first.name == second.name &&
      first.category == second.category &&
      first.imagePath == second.imagePath &&
      first.address == second.address &&
      first.notes == second.notes &&
      first.isActive == second.isActive &&
      first.isDeleted == second.isDeleted &&
      _samePeriods(first.periods, second.periods);

  Future<OptionMutationResult> setOptionActive(String id, bool active) =>
      _changeStatus(id, active: active);

  Future<OptionMutationResult> deleteOption(String id) =>
      _changeStatus(id, delete: true);

  Future<OptionMutationResult> _changeStatus(
    String id, {
    bool? active,
    bool delete = false,
  }) => _database.transaction((transaction) async {
    final matches = (await _options(
      transaction,
    )).where((option) => option.id == id);
    if (matches.isEmpty) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '这个选项已不存在。',
      );
    }
    final option = matches.single;
    if (delete && option.isBuiltIn) {
      return OptionMutationResult(
        OptionMutationStatus.invalid,
        option: option,
        message: '内置餐食不能删除，可以停用。',
      );
    }
    if (!delete && option.isDeleted) {
      return OptionMutationResult(
        OptionMutationStatus.invalid,
        option: option,
        message: '请先恢复已删除的选项。',
      );
    }
    if ((delete && option.isDeleted) ||
        (!delete && option.isActive == active)) {
      return OptionMutationResult(
        OptionMutationStatus.unchanged,
        option: option,
      );
    }
    await transaction.update(
      'options',
      delete
          ? {'is_deleted': 1, 'is_active': 0}
          : {'is_active': active! ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return OptionMutationResult(
      OptionMutationStatus.saved,
      option: (await _options(
        transaction,
      )).firstWhere((option) => option.id == id),
    );
  });

  Future<List<HistoryEntry>> history() async {
    final optionsById = {
      for (final option in await options()) option.id: option,
    };
    final rows = await _database.rawQuery('''
      SELECT r.operation_id, r.confirmed_at, r.period, i.option_id
      FROM history_records r
      JOIN history_items i ON i.operation_id = r.operation_id
      ORDER BY r.confirmed_at DESC, r.rowid DESC, i.position ASC
    ''');
    return List.unmodifiable(
      rows.map(
        (row) => HistoryEntry(
          operationId: row['operation_id']! as String,
          confirmedAt: DateTime.fromMicrosecondsSinceEpoch(
            row['confirmed_at']! as int,
            isUtc: true,
          ),
          period: MealPeriod.values.byName(row['period']! as String),
          option: optionsById[row['option_id']]!,
        ),
      ),
    );
  }

  Future<void> confirm(ConfirmationOperation operation) async {
    if (operation.operationId.trim().isEmpty) {
      throw ArgumentError.value(operation.operationId, 'operationId');
    }
    final inserted = await _database.transaction((transaction) async {
      final existing = await transaction.query(
        'history_records',
        where: 'operation_id = ?',
        whereArgs: [operation.operationId],
      );
      if (existing.isNotEmpty) {
        final items = await transaction.query(
          'history_items',
          where: 'operation_id = ?',
          whereArgs: [operation.operationId],
          orderBy: 'position',
        );
        final record = existing.single;
        if (record['confirmed_at'] !=
                operation.confirmedAt.microsecondsSinceEpoch ||
            record['period'] != operation.period.name ||
            items.length != 1 ||
            items.single['position'] != 0 ||
            items.single['option_id'] != operation.option.id) {
          throw StateError('Confirmation operation payload does not match.');
        }
        return false;
      }

      final eligible = await transaction.query(
        'option_periods',
        where: 'option_id = ? AND period = ?',
        whereArgs: [operation.option.id, operation.period.name],
      );
      if (eligible.isEmpty) {
        throw StateError('The option is not eligible for this meal period.');
      }
      final active = await transaction.query(
        'options',
        where: 'id = ? AND is_active = 1 AND is_deleted = 0',
        whereArgs: [operation.option.id],
      );
      if (active.isEmpty) {
        throw StateError('The option is no longer active.');
      }
      await transaction.insert('history_records', {
        'operation_id': operation.operationId,
        'confirmed_at': operation.confirmedAt.microsecondsSinceEpoch,
        'period': operation.period.name,
      });
      await _onConfirmationPhase?.call(ConfirmationPhase.afterHeaderWritten);
      await transaction.insert('history_items', {
        'operation_id': operation.operationId,
        'position': 0,
        'option_id': operation.option.id,
      });
      return true;
    });
    if (inserted) {
      await _onConfirmationPhase?.call(ConfirmationPhase.beforeAcknowledgement);
    }
  }

  Future<void> close() => _database.close();
}
