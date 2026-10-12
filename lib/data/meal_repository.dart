import 'dart:async';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../domain/local_recognition.dart';
import '../domain/meal.dart';
import '../domain/meal_preferences.dart';
import '../domain/online_recognition_settings.dart';

enum ConfirmationPhase {
  afterHeaderWritten,
  afterItemWritten,
  beforeAcknowledgement,
}

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
        version: 9,
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
          await _addCategoryRegistry(database);
          await _addCardTutorialPreference(database);
          await _addCardCollectionTutorialPreference(database);
          await _addRecognitionIdentity(database);
          await _addOnlineRecognition(database);
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
          if (oldVersion < 5) {
            await _addCategoryRegistry(database);
          }
          if (oldVersion < 6) {
            await _addCardTutorialPreference(database);
          }
          if (oldVersion < 7) {
            await _addCardCollectionTutorialPreference(database);
          }
          if (oldVersion < 8) {
            await _addRecognitionIdentity(database);
          }
          if (oldVersion < 9) {
            await _addOnlineRecognition(database);
          }
        },
      ),
    );
    return MealRepository._(database, onConfirmationPhase);
  }

  static Future<void> _addOnlineRecognition(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE online_recognition_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        consent_asked INTEGER NOT NULL CHECK (consent_asked IN (0, 1)),
        consent_granted INTEGER NOT NULL CHECK (consent_granted IN (0, 1)),
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1))
      )
    ''');
    await database.insert('online_recognition_settings', {
      'id': 1,
      'consent_asked': 0,
      'consent_granted': 0,
      'enabled': 0,
    });
    await database.execute('''
      CREATE TABLE online_recognition_requests (
        id INTEGER PRIMARY KEY,
        reserved_at INTEGER NOT NULL,
        calendar_day TEXT NOT NULL
      )
    ''');
  }

  Future<OnlineRecognitionSettings> onlineRecognitionSettings() async {
    final row = (await _database.query('online_recognition_settings')).single;
    return OnlineRecognitionSettings(
      consentAsked: row['consent_asked'] == 1,
      consentGranted: row['consent_granted'] == 1,
      enabled: row['enabled'] == 1,
    );
  }

  Future<void> saveOnlineRecognitionSettings(
    OnlineRecognitionSettings settings,
  ) async {
    await _database.update('online_recognition_settings', {
      'consent_asked': settings.consentAsked ? 1 : 0,
      'consent_granted': settings.consentGranted ? 1 : 0,
      'enabled': settings.enabled && settings.consentGranted ? 1 : 0,
    }, where: 'id = 1');
  }

  // Reserve before dispatch, so failures and process restarts cannot refund a
  // sent request. Consent and request freshness are checked by the coordinator.
  Future<bool> reserveOnlineRecognitionRequest(DateTime now) =>
      _database.transaction((transaction) async {
        final local = now.toLocal();
        final calendarDay =
            '${local.year}-${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')}';
        final reservedAt = now.microsecondsSinceEpoch;
        final minuteStart = now
            .subtract(const Duration(minutes: 1))
            .microsecondsSinceEpoch;
        // Keep the previous day's reservations across midnight while they
        // still count toward the rolling minute; retain today's daily count.
        await transaction.delete(
          'online_recognition_requests',
          where: 'calendar_day != ? AND reserved_at <= ?',
          whereArgs: [calendarDay, minuteStart],
        );
        final rows = await transaction.query('online_recognition_requests');
        final daily = rows.where((row) => row['calendar_day'] == calendarDay);
        final recent = rows.where(
          (row) => (row['reserved_at']! as int) > minuteStart,
        );
        if (daily.length >= 30 || recent.length >= 6) return false;
        await transaction.insert('online_recognition_requests', {
          'reserved_at': reservedAt,
          'calendar_day': calendarDay,
        });
        return true;
      });

  static Future<void> _addRecognitionIdentity(DatabaseExecutor database) async {
    await database.execute(
      'ALTER TABLE options ADD COLUMN recognition_id TEXT',
    );
    const recognition = LocalRecognition();
    final rows = await database.query('options');
    for (final row in rows) {
      final scenario = row['scenario']! as String;
      final displayIdentity = recognition.identity(
        row['name']! as String,
        scenario,
      );
      String? identity;
      // Built-in IDs are stronger identity evidence than legacy display edits,
      // including names an earlier version accepted as a different dish.
      if (row['is_builtin'] == 1) {
        final seed = seedOptions
            .where((value) => value.id == row['id'])
            .firstOrNull;
        if (seed != null && seed.scenario == scenario) {
          identity = recognition.identity(seed.name, scenario);
          // A recognized explicit branch of the same brand refines a legacy
          // restaurant identity; treating it as the brand would merge places.
          if (scenario == MealScenario.restaurant.name &&
              identity != null &&
              displayIdentity != null &&
              displayIdentity.startsWith('$identity#branch:')) {
            identity = displayIdentity;
          }
        }
      }
      identity ??= displayIdentity;
      if (identity != null) {
        await database.update(
          'options',
          {'recognition_id': identity},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<void> _addCategoryRegistry(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        scenario TEXT NOT NULL CHECK (scenario IN ('eat', 'cook', 'restaurant')),
        is_builtin INTEGER NOT NULL CHECK (is_builtin IN (0, 1)),
        is_fallback INTEGER NOT NULL CHECK (is_fallback IN (0, 1)),
        CHECK (is_fallback = 0 OR is_builtin = 1),
        UNIQUE (scenario, name)
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX scenario_fallback
      ON categories (scenario) WHERE is_fallback = 1
    ''');
    for (final scenario in MealScenario.values) {
      final names = scenarioCategories[scenario]!;
      for (var index = 0; index < names.length; index++) {
        final name = names[index];
        final fallback = name == '未分类';
        await database.insert('categories', {
          'id':
              'builtin-category-${scenario.name}-${fallback ? 'fallback' : index}',
          'name': name,
          'scenario': scenario.name,
          'is_builtin': 1,
          'is_fallback': fallback ? 1 : 0,
        });
      }
    }
    // Keep every legacy label, including memberships retained for history.
    final labels = await database.rawQuery('''
      SELECT scenario, category FROM options
      UNION
      SELECT o.scenario, c.category FROM option_categories c
      JOIN options o ON o.id = c.option_id
    ''');
    for (var index = 0; index < labels.length; index++) {
      final row = labels[index];
      await database.insert('categories', {
        'id': 'legacy-category-$index',
        'name': row['category'],
        'scenario': row['scenario'],
        'is_builtin': 0,
        'is_fallback': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
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
      cardTutorialDismissed: row['card_tutorial_dismissed'] == 1,
      cardCollectionTutorialDismissed:
          row['card_collection_tutorial_dismissed'] == 1,
    );
  }

  static Future<void> _addCardTutorialPreference(DatabaseExecutor database) =>
      database.execute('''
    ALTER TABLE preferences ADD COLUMN card_tutorial_dismissed
      INTEGER NOT NULL DEFAULT 0 CHECK (card_tutorial_dismissed IN (0, 1))
  ''');

  static Future<void> _addCardCollectionTutorialPreference(
    DatabaseExecutor database,
  ) => database.execute('''
    ALTER TABLE preferences ADD COLUMN card_collection_tutorial_dismissed
      INTEGER NOT NULL DEFAULT 0
      CHECK (card_collection_tutorial_dismissed IN (0, 1))
  ''');

  Future<void> dismissCardTutorial({bool includeCollection = false}) async {
    await _database.update(
      'preferences',
      {
        'card_tutorial_dismissed': 1,
        if (includeCollection) 'card_collection_tutorial_dismissed': 1,
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<void> savePreferences(
    MealPreferences preferences,
  ) => _database.transaction((transaction) async {
    final existing = (await transaction.query('preferences')).single;
    await transaction.insert('preferences', {
      'id': 1,
      'mode': preferences.mode.name,
      'exclude_yesterday': preferences.excludeYesterday ? 1 : 0,
      // Dismissal is permanent, including when an older UI snapshot is saved.
      'card_tutorial_dismissed':
          preferences.cardTutorialDismissed ||
              existing['card_tutorial_dismissed'] == 1
          ? 1
          : 0,
      'card_collection_tutorial_dismissed':
          preferences.cardCollectionTutorialDismissed ||
              existing['card_collection_tutorial_dismissed'] == 1
          ? 1
          : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<List<FoodOption>> options() => _options(_database);

  Future<List<MealCategory>> categories() => _categories(_database);

  Future<List<MealCategory>> _categories(DatabaseExecutor executor) async {
    final rows = await executor.query('categories', orderBy: 'rowid');
    return List.unmodifiable(
      rows.map(
        (row) => MealCategory(
          id: row['id']! as String,
          name: row['name']! as String,
          scenario: MealScenario.values.byName(row['scenario']! as String),
          isBuiltIn: row['is_builtin'] == 1,
          isFallback: row['is_fallback'] == 1,
        ),
      ),
    );
  }

  Future<OptionMutationResult> saveCategory({
    String? id,
    required String name,
    MealScenario scenario = MealScenario.eat,
  }) => _database.transaction((transaction) async {
    final displayName = name.trim();
    final normalized = normalizedOptionName(displayName);
    if (normalized.isEmpty || normalized == normalizedOptionName('全部')) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '请填写分类名称，全部仅用于筛选。',
      );
    }
    final registered = await _categories(transaction);
    MealCategory? original;
    if (id != null) {
      for (final category in registered) {
        if (category.id == id) original = category;
      }
      if (original == null) {
        return const OptionMutationResult(
          OptionMutationStatus.invalid,
          message: '这个分类已不存在，请重新打开分类管理。',
        );
      }
    }
    final targetScenario = original?.scenario ?? scenario;
    if (original?.name == displayName) {
      return const OptionMutationResult(OptionMutationStatus.unchanged);
    }
    if (registered.any(
      (category) =>
          category.id != id &&
          category.scenario == targetScenario &&
          normalizedOptionName(category.name) == normalized,
    )) {
      return const OptionMutationResult(
        OptionMutationStatus.duplicate,
        message: '这个场景中已有同名分类。',
      );
    }
    if (original == null) {
      await transaction.insert('categories', {
        'id': _newId('custom-category'),
        'name': displayName,
        'scenario': targetScenario.name,
        'is_builtin': 0,
        'is_fallback': 0,
      });
    } else {
      await transaction.update(
        'categories',
        {'name': displayName},
        where: 'id = ?',
        whereArgs: [id],
      );
      await transaction.update(
        'options',
        {'category': displayName},
        where: 'scenario = ? AND category = ?',
        whereArgs: [targetScenario.name, original.name],
      );
      await transaction.rawUpdate(
        '''
        UPDATE option_categories SET category = ?
        WHERE category = ? AND option_id IN
          (SELECT id FROM options WHERE scenario = ?)
      ''',
        [displayName, original.name, targetScenario.name],
      );
    }
    return const OptionMutationResult(OptionMutationStatus.saved);
  });

  Future<OptionMutationResult> deleteCategory(String id) =>
      _database.transaction((transaction) async {
        final registered = await _categories(transaction);
        final matches = registered.where((category) => category.id == id);
        if (matches.isEmpty) {
          return const OptionMutationResult(
            OptionMutationStatus.invalid,
            message: '这个分类已不存在。',
          );
        }
        final category = matches.single;
        if (category.isBuiltIn) {
          return const OptionMutationResult(
            OptionMutationStatus.invalid,
            message: '内置分类不能删除，可以重命名。',
          );
        }
        final fallback = registered.singleWhere(
          (value) => value.scenario == category.scenario && value.isFallback,
        );
        await transaction.rawInsert(
          '''
          INSERT OR IGNORE INTO option_categories (option_id, category)
          SELECT c.option_id, ? FROM option_categories c
          JOIN options o ON o.id = c.option_id
          WHERE o.scenario = ? AND c.category = ?
        ''',
          [fallback.name, category.scenario.name, category.name],
        );
        await transaction.rawDelete(
          '''
          DELETE FROM option_categories WHERE category = ? AND option_id IN
            (SELECT id FROM options WHERE scenario = ?)
        ''',
          [category.name, category.scenario.name],
        );
        await transaction.update(
          'options',
          {'category': fallback.name},
          where: 'scenario = ? AND category = ?',
          whereArgs: [category.scenario.name, category.name],
        );
        await transaction.delete(
          'categories',
          where: 'id = ?',
          whereArgs: [id],
        );
        return const OptionMutationResult(OptionMutationStatus.saved);
      });

  String _newId(String prefix) =>
      '$prefix-${List.generate(16, (_) => _idRandom.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

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
          recognitionId: row['recognition_id'] as String?,
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
    String? category,
    String scenario = 'eat',
    String? imagePath,
    String? address,
    String? notes,
    bool confirmRestore = false,
    bool confirmSameFood = false,
    bool allowUncertainDuplicate = false,
    String? restoreOptionId,
    String? advisoryRestoreOptionId,
  }) => _database.transaction((transaction) async {
    final displayName = name.trim();
    if (!MealScenario.values.any((value) => value.name == scenario)) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '请选择有效的场景。',
      );
    }
    final registered = await _categories(transaction);
    final scopedCategories = registered.where(
      (value) => value.scenario.name == scenario,
    );
    const recognition = LocalRecognition();
    final inferredCategoryId = recognition.inferCategoryId(
      displayName,
      MealScenario.fromKey(scenario),
      scopedCategories.toList(),
    );
    final displayCategory =
        category?.trim() ??
        scopedCategories
            .where((value) => value.id == inferredCategoryId)
            .firstOrNull
            ?.name;
    if (displayName.isEmpty ||
        periods.isEmpty ||
        displayCategory == null ||
        displayCategory.isEmpty ||
        !MealScenario.values.any((value) => value.name == scenario)) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '请填写名称、一个分类，并至少选择一个适用时段。',
      );
    }
    if (!scopedCategories.any((value) => value.name == displayCategory)) {
      return const OptionMutationResult(
        OptionMutationStatus.invalid,
        message: '请选择当前场景中存在的分类。',
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
    final normalized = normalizedOptionName(displayName);
    final nameChanged =
        original == null || normalizedOptionName(original.name) != normalized;
    final enteredIdentity = recognition.identity(displayName, scenario);
    FoodOption? advisoryRestore;
    if (advisoryRestoreOptionId != null) {
      advisoryRestore = options
          .where((option) => option.id == advisoryRestoreOptionId)
          .firstOrNull;
      if (id != null ||
          (restoreOptionId != null &&
              restoreOptionId != advisoryRestoreOptionId) ||
          advisoryRestore == null ||
          advisoryRestore.scenario != scenario ||
          !advisoryRestore.isDeleted ||
          advisoryRestore.isBuiltIn ||
          recognition.compare(
                displayName,
                advisoryRestore.name,
                scenario,
                identityA: enteredIdentity,
                identityB: advisoryRestore.recognitionId,
              ) ==
              NameMatch.different) {
        return const OptionMutationResult(
          OptionMutationStatus.invalid,
          message: '无法恢复这个选项，请重新检查已有选项。',
        );
      }
    }
    NameMatch? renameMatch;
    if (id != null && nameChanged) {
      renameMatch = recognition.compare(
        displayName,
        original!.name,
        scenario,
        identityA: enteredIdentity,
        identityB: original.recognitionId,
      );
      if (renameMatch == NameMatch.different) {
        return OptionMutationResult(
          OptionMutationStatus.invalid,
          option: original,
          message: scenario == MealScenario.restaurant.name
              ? '新名称是不同的餐厅，请创建单独的选项以保留原有足迹。'
              : '新名称是不同的餐食，请创建单独的选项以保留原有足迹。',
        );
      }
    }
    final confirmed = <FoodOption>[];
    final uncertain = <FoodOption>[];
    // Existing alias collisions remain separate identities. Editing their
    // unchanged name or other fields must remain possible.
    if (nameChanged) {
      for (final option in options) {
        if (option.id == id || option.scenario != scenario) continue;
        final match = recognition.compare(
          displayName,
          option.name,
          scenario,
          identityA: original?.recognitionId ?? enteredIdentity,
          identityB: option.recognitionId,
        );
        if (match == NameMatch.confirmed) confirmed.add(option);
        if (match == NameMatch.uncertain) uncertain.add(option);
      }
    }
    if (confirmed.isNotEmpty) {
      final matches = List<FoodOption>.unmodifiable(confirmed);
      final onlyMatch = matches.length == 1 ? matches.single : null;
      final addressConflict =
          scenario == MealScenario.restaurant.name &&
          address != null &&
          matches.any(
            (value) =>
                normalizedOptionName(value.address ?? '') !=
                normalizedOptionName(address),
          );
      final branchGuidance = addressConflict
          ? '名称相同但地址不同，地址不能确定是否为不同分店；如需添加分店，请在名称中注明，例如街角小馆（东街店）。'
          : null;
      if (id == null &&
          matches.every((value) => value.isDeleted && !value.isBuiltIn)) {
        final selectedId = advisoryRestoreOptionId ?? restoreOptionId;
        final selected = selectedId == null
            ? onlyMatch
            : matches.where((value) => value.id == selectedId).firstOrNull;
        if (!confirmRestore || selected == null) {
          return OptionMutationResult(
            OptionMutationStatus.restorationRequired,
            option: onlyMatch,
            matches: matches,
            message:
                branchGuidance ??
                (matches.length == 1
                    ? '已有相同的已删除选项，恢复后会保存本表单的名称、分类、时段等内容，并保留原有足迹。'
                    : '已有多个相同的已删除选项，请选择要恢复的原选项；恢复后会保存本表单内容并保留原有足迹。'),
          );
        }
        original = selected;
      } else {
        return OptionMutationResult(
          OptionMutationStatus.duplicate,
          option: onlyMatch,
          matches: matches,
          message:
              branchGuidance ??
              (matches.any((value) => value.isActive && !value.isDeleted)
                  ? '已有相同餐食，请查看已有选项。'
                  : '已有相同餐食，请查看已有选项，可重新启用已停用的选项。'),
        );
      }
    }
    final unresolvedUncertain = uncertain
        .where((option) => option.id != advisoryRestoreOptionId)
        .toList();
    if (unresolvedUncertain.isNotEmpty && !allowUncertainDuplicate) {
      return OptionMutationResult(
        OptionMutationStatus.uncertainDuplicate,
        option: unresolvedUncertain.length == 1
            ? unresolvedUncertain.single
            : null,
        matches: List.unmodifiable(unresolvedUncertain),
        message: '可能已有类似餐食，请查看已有选项，或确认后仍然保存。',
      );
    }
    if (advisoryRestore != null) {
      if (!confirmRestore) {
        return OptionMutationResult(
          OptionMutationStatus.restorationRequired,
          option: advisoryRestore,
          matches: List.unmodifiable([advisoryRestore]),
          message: '恢复后会保存本表单的名称、分类、时段等内容，并保留原有足迹。',
        );
      }
      original = advisoryRestore;
    }
    if (id != null &&
        nameChanged &&
        renameMatch != NameMatch.confirmed &&
        !confirmSameFood) {
      return OptionMutationResult(
        OptionMutationStatus.renameConfirmationRequired,
        option: original,
        message: '无法判断新名称是否还是同一种餐食，请确认后保存。',
      );
    }
    final option = FoodOption(
      id: original?.id ?? _newId('custom'),
      name: displayName,
      art:
          original?.art ??
          _defaultArt(
            scopedCategories.firstWhere(
              (category) => category.name == displayCategory,
            ),
          ),
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
      recognitionId: original?.recognitionId ?? enteredIdentity,
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
      'recognition_id': option.recognitionId,
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

  // Assign once at creation using stable category identity, so later option or
  // category edits keep the same default illustration.
  static String _defaultArt(MealCategory category) => switch (category.id) {
    'builtin-category-restaurant-0' => 'shop-hotpot',
    'builtin-category-restaurant-1' => 'shop-barbecue',
    'builtin-category-restaurant-2' => 'shop-chinese',
    'builtin-category-restaurant-3' => 'shop-western',
    'builtin-category-restaurant-4' => 'shop-fastfood',
    'builtin-category-restaurant-5' => 'shop-buffet',
    'builtin-category-eat-0' => 'rice',
    'builtin-category-eat-1' || 'builtin-category-eat-2' => 'noodle',
    'builtin-category-eat-4' => 'bun',
    'builtin-category-eat-5' => 'porridge',
    'builtin-category-eat-7' => 'burger',
    'builtin-category-eat-8' => 'drink',
    _ => category.scenario == MealScenario.restaurant ? 'storefront' : 'plate',
  };

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
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      (grouped[row['operation_id']! as String] ??= []).add(row);
    }
    return List.unmodifiable(
      grouped.entries.map((entry) {
        final row = entry.value.first;
        return HistoryEntry(
          operationId: entry.key,
          confirmedAt: DateTime.fromMicrosecondsSinceEpoch(
            row['confirmed_at']! as int,
            isUtc: true,
          ),
          period: MealPeriod.values.byName(row['period']! as String),
          options: entry.value
              .map((item) => optionsById[item['option_id']]!)
              .toList(),
        );
      }),
    );
  }

  Future<bool> deleteHistory(String operationId) =>
      _database.transaction((transaction) async {
        // The v8 foreign key has no cascade. Remove children and their complete
        // record in one transaction while retaining all referenced option data.
        await transaction.delete(
          'history_items',
          where: 'operation_id = ?',
          whereArgs: [operationId],
        );
        final deleted = await transaction.delete(
          'history_records',
          where: 'operation_id = ?',
          whereArgs: [operationId],
        );
        return deleted > 0;
      });

  Future<void> confirm(ConfirmationOperation operation) async {
    if (operation.operationId.trim().isEmpty) {
      throw ArgumentError.value(operation.operationId, 'operationId');
    }
    final options = operation.options;
    if (options.isEmpty || options.length > 10) {
      throw ArgumentError.value(options.length, 'options', 'Expected 1–10.');
    }
    final scenario = options.first.scenario;
    if (!MealScenario.values.any((value) => value.name == scenario) ||
        options.any((option) => option.scenario != scenario) ||
        (scenario != MealScenario.cook.name && options.length != 1) ||
        options.map((option) => option.id).toSet().length != options.length) {
      throw ArgumentError('Expected distinct options from one scenario.');
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
            items.length != options.length) {
          throw StateError('Confirmation operation payload does not match.');
        }
        for (var index = 0; index < options.length; index++) {
          if (items[index]['position'] != index ||
              items[index]['option_id'] != options[index].id) {
            throw StateError('Confirmation operation payload does not match.');
          }
        }
        // A committed retry acknowledges the original payload even when an
        // option has since become ineligible. Its scenario must still match.
        for (final option in options) {
          final stored = await transaction.query(
            'options',
            columns: ['scenario'],
            where: 'id = ?',
            whereArgs: [option.id],
          );
          if (stored.isEmpty || stored.single['scenario'] != scenario) {
            throw StateError('Confirmation option scenario does not match.');
          }
        }
        return false;
      }

      for (final option in options) {
        final eligible = await transaction.rawQuery(
          '''
          SELECT o.id FROM options o
          JOIN option_periods p ON p.option_id = o.id
          WHERE o.id = ? AND o.scenario = ? AND o.is_active = 1
            AND o.is_deleted = 0 AND p.period = ?
        ''',
          [option.id, scenario, operation.period.name],
        );
        if (eligible.isEmpty) {
          throw StateError('The option is no longer eligible for this meal.');
        }
      }
      await transaction.insert('history_records', {
        'operation_id': operation.operationId,
        'confirmed_at': operation.confirmedAt.microsecondsSinceEpoch,
        'period': operation.period.name,
      });
      await _onConfirmationPhase?.call(ConfirmationPhase.afterHeaderWritten);
      for (var index = 0; index < options.length; index++) {
        await transaction.insert('history_items', {
          'operation_id': operation.operationId,
          'position': index,
          'option_id': options[index].id,
        });
        await _onConfirmationPhase?.call(ConfirmationPhase.afterItemWritten);
      }
      return true;
    });
    if (inserted) {
      await _onConfirmationPhase?.call(ConfirmationPhase.beforeAcknowledgement);
    }
  }

  Future<void> close() => _database.close();
}
