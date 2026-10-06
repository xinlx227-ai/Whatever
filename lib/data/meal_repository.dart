import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../domain/meal.dart';
import '../domain/meal_preferences.dart';

enum ConfirmationPhase { afterHeaderWritten, beforeAcknowledgement }

typedef ConfirmationFault = FutureOr<void> Function(ConfirmationPhase phase);

class MealRepository {
  MealRepository._(this._database, this._onConfirmationPhase);

  final Database _database;
  final ConfirmationFault? _onConfirmationPhase;

  static Future<MealRepository> open({
    required DatabaseFactory factory,
    required String path,
    ConfirmationFault? onConfirmationPhase,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
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
          for (final option in seedOptions) {
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
          await _createPreferences(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createPreferences(database);
          }
        },
      ),
    );
    return MealRepository._(database, onConfirmationPhase);
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
    return List.unmodifiable(
      rows.map(
        (row) => FoodOption(
          id: row['id']! as String,
          name: row['name']! as String,
          art: row['art']! as String,
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
