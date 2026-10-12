import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/local_recognition.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/domain/online_recognition_settings.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  const periods = {MealPeriod.lunch};
  const recognition = LocalRecognition();

  Future<Database> inspect() => databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  Future<void> reopen() async {
    await repository.close();
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
  }

  Future<FoodOption> retainedOption(
    String id,
    String name, {
    String scenario = 'cook',
    bool deleted = true,
    String? imagePath,
    String? address,
    String? notes,
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
        'is_active': deleted ? 0 : 1,
        'is_deleted': deleted ? 1 : 0,
        'image_path': imagePath,
        'address': address,
        'notes': notes,
        'recognition_id': recognition.identity(name, scenario),
      });
      await database.insert('option_categories', {
        'option_id': id,
        'category': '未分类',
      });
      await database.insert('option_periods', {
        'option_id': id,
        'period': MealPeriod.lunch.name,
      });
    } finally {
      await database.close();
    }
    return (await repository.options()).singleWhere(
      (option) => option.id == id,
    );
  }

  void expectSettings(
    OnlineRecognitionSettings actual, {
    bool asked = false,
    bool granted = false,
    bool enabled = false,
  }) {
    expect(actual.consentAsked, asked);
    expect(actual.consentGranted, granted);
    expect(actual.enabled, enabled);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-online-');
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

  test('consent defaults off and all decisions survive reopening', () async {
    expectSettings(await repository.onlineRecognitionSettings());
    for (final settings in [
      const OnlineRecognitionSettings(consentAsked: true),
      const OnlineRecognitionSettings(
        consentAsked: true,
        consentGranted: true,
        enabled: true,
      ),
      const OnlineRecognitionSettings(consentAsked: true, consentGranted: true),
      const OnlineRecognitionSettings(consentAsked: true),
    ]) {
      await repository.saveOnlineRecognitionSettings(settings);
      await reopen();
      expectSettings(
        await repository.onlineRecognitionSettings(),
        asked: settings.consentAsked,
        granted: settings.consentGranted,
        enabled: settings.enabled,
      );
    }
    await repository.saveOnlineRecognitionSettings(
      const OnlineRecognitionSettings(enabled: true),
    );
    expectSettings(await repository.onlineRecognitionSettings());
  });

  test('stale meal preference writes cannot overwrite consent', () async {
    final stale = await repository.preferences();
    await repository.saveOnlineRecognitionSettings(
      const OnlineRecognitionSettings(
        consentAsked: true,
        consentGranted: true,
        enabled: true,
      ),
    );
    await repository.savePreferences(stale);
    await reopen();
    expectSettings(
      await repository.onlineRecognitionSettings(),
      asked: true,
      granted: true,
      enabled: true,
    );
  });

  test(
    'concurrent reservations atomically enforce rolling six per minute',
    () async {
      final now = DateTime(2026, 10, 12, 12);
      final accepted = await Future.wait(
        List.generate(
          40,
          (_) => repository.reserveOnlineRecognitionRequest(now),
        ),
      );
      expect(accepted.where((value) => value), hasLength(6));
      await reopen();
      expect(await repository.reserveOnlineRecognitionRequest(now), isFalse);
      expect(
        await repository.reserveOnlineRecognitionRequest(
          now.add(const Duration(seconds: 59, milliseconds: 999)),
        ),
        isFalse,
      );
      expect(
        await repository.reserveOnlineRecognitionRequest(
          now.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    },
  );

  test('minute window rolls instead of resetting at a clock minute', () async {
    final now = DateTime(2026, 10, 12, 12, 0, 50);
    for (var index = 0; index < 6; index++) {
      expect(await repository.reserveOnlineRecognitionRequest(now), isTrue);
    }
    expect(
      await repository.reserveOnlineRecognitionRequest(
        DateTime(2026, 10, 12, 12, 1),
      ),
      isFalse,
    );
  });

  test(
    'thirty daily reservations survive restart, failure and toggle',
    () async {
      final start = DateTime(2026, 10, 12, 12);
      for (var index = 0; index < 30; index++) {
        expect(
          await repository.reserveOnlineRecognitionRequest(
            start.add(Duration(minutes: index)),
          ),
          isTrue,
        );
      }
      // Reservations are final even when transport is never acknowledged.
      await repository.saveOnlineRecognitionSettings(
        const OnlineRecognitionSettings(),
      );
      await repository.saveOnlineRecognitionSettings(
        const OnlineRecognitionSettings(
          consentAsked: true,
          consentGranted: true,
          enabled: true,
        ),
      );
      await reopen();
      expect(
        await repository.reserveOnlineRecognitionRequest(
          DateTime(2026, 10, 12, 23, 59),
        ),
        isFalse,
      );
      expect(
        await repository.reserveOnlineRecognitionRequest(
          DateTime(2026, 10, 13),
        ),
        isTrue,
      );
    },
  );

  test(
    'calendar midnight resets daily count but preserves rolling quota',
    () async {
      final lastMinute = DateTime(2026, 10, 12, 23, 59, 40);
      for (var index = 0; index < 6; index++) {
        expect(
          await repository.reserveOnlineRecognitionRequest(lastMinute),
          isTrue,
        );
      }
      await reopen();
      expect(
        await repository.reserveOnlineRecognitionRequest(
          DateTime(2026, 10, 13),
        ),
        isFalse,
      );
      expect(
        await repository.reserveOnlineRecognitionRequest(
          DateTime(2026, 10, 13, 0, 0, 40),
        ),
        isTrue,
      );
    },
  );

  test(
    'v8 upgrade preserves every existing table and defaults online off',
    () async {
      await repository.savePreferences(
        const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
      );
      final option = await retainedOption(
        'migration-kept',
        '保留菜品',
        deleted: false,
      );
      await repository.confirm(
        ConfirmationOperation(
          operationId: 'migration-history',
          confirmedAt: DateTime(2026, 10, 12, 12),
          period: MealPeriod.lunch,
          option: option,
        ),
      );
      await repository.deleteOption(option.id);
      await repository.close();
      final before = <String, List<Map<String, Object?>>>{};
      final legacy = await inspect();
      try {
        for (final table in [
          'options',
          'option_periods',
          'option_categories',
          'categories',
          'history_records',
          'history_items',
          'preferences',
        ]) {
          before[table] = await legacy.query(table, orderBy: 'rowid');
        }
        await legacy.execute('DROP TABLE online_recognition_requests');
        await legacy.execute('DROP TABLE online_recognition_settings');
        await legacy.setVersion(8);
      } finally {
        await legacy.close();
      }
      repository = await MealRepository.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      expectSettings(await repository.onlineRecognitionSettings());
      final database = await inspect();
      try {
        expect(await database.getVersion(), 9);
        for (final entry in before.entries) {
          expect(
            await database.query(entry.key, orderBy: 'rowid'),
            entry.value,
          );
        }
        expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await database.close();
      }
      expect((await repository.history()).single.option.id, option.id);
    },
  );

  test('failed reservation transaction consumes no quota', () async {
    final database = await inspect();
    try {
      await database.execute('''
        CREATE TRIGGER fail_online_request BEFORE INSERT ON online_recognition_requests
        BEGIN SELECT RAISE(ABORT, 'Injected reservation write failure'); END
      ''');
      await expectLater(
        repository.reserveOnlineRecognitionRequest(DateTime(2026, 10, 12, 12)),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.query('online_recognition_requests'), isEmpty);
      await database.execute('DROP TRIGGER fail_online_request');
    } finally {
      await database.close();
    }
    expect(
      await repository.reserveOnlineRecognitionRequest(
        DateTime(2026, 10, 12, 12),
      ),
      isTrue,
    );
  });

  test(
    'advisory restoration requires confirmation and retains ID and history',
    () async {
      final original = await retainedOption(
        'advisory-dish',
        '韭菜炒虾仁',
        deleted: false,
        imagePath: 'original.jpg',
      );
      await repository.confirm(
        ConfirmationOperation(
          operationId: 'original-history',
          confirmedAt: DateTime(2026, 10, 12, 12),
          period: MealPeriod.lunch,
          option: original,
        ),
      );
      await repository.deleteOption(original.id);
      final count = (await repository.options()).length;
      final prompt = await repository.saveOption(
        name: '虾仁炒韭菜',
        periods: {MealPeriod.dinner},
        scenario: 'cook',
        category: '家常菜',
        advisoryRestoreOptionId: original.id,
      );
      expect(prompt.status, OptionMutationStatus.restorationRequired);
      expect(prompt.matches.single.id, original.id);
      expect((await repository.options()).length, count);
      expect((await repository.history()).single.option.isDeleted, isTrue);
      final restored = await repository.saveOption(
        name: '虾仁炒韭菜',
        periods: {MealPeriod.dinner},
        scenario: 'cook',
        category: '家常菜',
        advisoryRestoreOptionId: original.id,
        confirmRestore: true,
      );
      expect(restored.status, OptionMutationStatus.saved);
      expect(restored.option!.id, original.id);
      expect(restored.option!.name, '虾仁炒韭菜');
      expect(restored.option!.category, '家常菜');
      expect(restored.option!.periods, {MealPeriod.dinner});
      expect(restored.option!.imagePath, 'original.jpg');
      expect(restored.option!.recognitionId, original.recognitionId);
      expect(restored.option!.isDeleted, isFalse);
      expect(restored.option!.isActive, isTrue);
      await reopen();
      expect((await repository.options()).length, count);
      final history = (await repository.history()).single;
      expect(history.operationId, 'original-history');
      expect(history.option.id, original.id);
      expect(history.option.name, '虾仁炒韭菜');
    },
  );

  test(
    'advisory restaurant restore uses existing form overwrite semantics',
    () async {
      final original = await retainedOption(
        'advisory-shop',
        '家庭小馆',
        scenario: 'restaurant',
        imagePath: 'old.jpg',
        address: '旧地址',
        notes: '旧备注',
      );
      final restored = await repository.saveOption(
        name: '家庭食堂',
        periods: {MealPeriod.dinner},
        scenario: 'restaurant',
        category: '中餐',
        imagePath: 'new.jpg',
        address: '',
        notes: '新备注',
        advisoryRestoreOptionId: original.id,
        confirmRestore: true,
      );
      expect(restored.status, OptionMutationStatus.saved);
      expect(restored.option!.address, isNull);
      expect(restored.option!.notes, '新备注');
      expect(restored.option!.imagePath, 'new.jpg');
    },
  );

  test('invalid advisory targets cannot mutate or create', () async {
    final deleted = await retainedOption('deleted-target', '保留旧菜');
    final active = await retainedOption(
      'active-target',
      '另一个菜',
      deleted: false,
    );
    final count = (await repository.options()).length;
    for (final target in ['missing', active.id, 'rice']) {
      final result = await repository.saveOption(
        name: '新名字',
        periods: periods,
        scenario: 'cook',
        advisoryRestoreOptionId: target,
        confirmRestore: true,
      );
      expect(result.status, OptionMutationStatus.invalid);
    }
    final wrongScenario = await repository.saveOption(
      name: '新名字',
      periods: periods,
      scenario: 'eat',
      advisoryRestoreOptionId: deleted.id,
      confirmRestore: true,
    );
    expect(wrongScenario.status, OptionMutationStatus.invalid);
    final edit = await repository.saveOption(
      id: active.id,
      name: active.name,
      periods: periods,
      scenario: 'cook',
      advisoryRestoreOptionId: deleted.id,
      confirmRestore: true,
    );
    expect(edit.status, OptionMutationStatus.invalid);
    final conflictingSelection = await repository.saveOption(
      name: '新名字',
      periods: periods,
      scenario: 'cook',
      advisoryRestoreOptionId: deleted.id,
      restoreOptionId: active.id,
      confirmRestore: true,
    );
    expect(conflictingSelection.status, OptionMutationStatus.invalid);
    expect((await repository.options()).length, count);
    expect(
      (await repository.options())
          .singleWhere((value) => value.id == deleted.id)
          .isDeleted,
      isTrue,
    );
  });

  for (final pair in [
    ('番茄炒蛋', '青椒炒蛋', 'cook'),
    ('番茄炒蛋', '番茄鸡蛋汤', 'cook'),
    ('肯德基（人民路店）', 'KFC（茶山店）', 'restaurant'),
  ]) {
    test(
      'local different vetoes advisory restore ${pair.$1} to ${pair.$2}',
      () async {
        final original = await retainedOption(
          'different-target',
          pair.$1,
          scenario: pair.$3,
        );
        expect(
          recognition.compare(pair.$1, pair.$2, pair.$3),
          NameMatch.different,
        );
        final result = await repository.saveOption(
          name: pair.$2,
          periods: periods,
          scenario: pair.$3,
          advisoryRestoreOptionId: original.id,
          confirmRestore: true,
          allowUncertainDuplicate: true,
        );
        expect(result.status, OptionMutationStatus.invalid);
        expect(
          (await repository.options())
              .singleWhere((value) => value.id == original.id)
              .isDeleted,
          isTrue,
        );
      },
    );
  }

  test(
    'advisory selection cannot bypass full-library confirmed duplicate',
    () async {
      final advisory = await retainedOption('unrelated-deleted', '旧菜品');
      final result = await repository.saveOption(
        name: '番茄炒蛋',
        periods: periods,
        scenario: 'cook',
        advisoryRestoreOptionId: advisory.id,
        confirmRestore: true,
        allowUncertainDuplicate: true,
      );
      expect(result.status, OptionMutationStatus.duplicate);
      expect(result.matches.any((value) => value.name == '番茄炒蛋'), isTrue);
      expect(
        (await repository.options())
            .singleWhere((value) => value.id == advisory.id)
            .isDeleted,
        isTrue,
      );
    },
  );

  test(
    'other deleted confirmed matches retain local restoration authority',
    () async {
      final advisory = await retainedOption('unrelated-deleted', '旧菜品');
      final confirmed = await retainedOption('confirmed-deleted', '独家炖菜');
      final result = await repository.saveOption(
        name: confirmed.name,
        periods: periods,
        scenario: 'cook',
        advisoryRestoreOptionId: advisory.id,
        confirmRestore: true,
      );
      expect(result.status, OptionMutationStatus.restorationRequired);
      expect(result.matches.single.id, confirmed.id);
      expect(
        (await repository.options())
            .where(
              (value) => value.id == advisory.id || value.id == confirmed.id,
            )
            .every((value) => value.isDeleted),
        isTrue,
      );
    },
  );

  test(
    'other local uncertain matches still require explicit override',
    () async {
      final advisory = await retainedOption(
        'eat-deleted',
        '旧餐食',
        scenario: 'eat',
      );
      final result = await repository.saveOption(
        name: '牛肉面豪华版',
        periods: periods,
        scenario: 'eat',
        advisoryRestoreOptionId: advisory.id,
        confirmRestore: true,
      );
      expect(result.status, OptionMutationStatus.uncertainDuplicate);
      expect(result.matches.any((value) => value.id == 'noodles'), isTrue);
      expect(
        (await repository.options())
            .singleWhere((value) => value.id == advisory.id)
            .isDeleted,
        isTrue,
      );
    },
  );
}
