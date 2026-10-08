import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

class LastOptionRandom implements Random {
  @override
  int nextInt(int max) => max - 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  late MealController controller;
  late DateTime now;
  ConfirmationFault? fault;

  Future<void> open() async {
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
      onConfirmationPhase: (phase) => fault?.call(phase),
    );
    controller = MealController(
      repository: repository,
      random: LastOptionRandom(),
      clock: () => now,
    );
    await controller.initialize();
  }

  Future<void> reopen() async {
    controller.dispose();
    await repository.close();
    await open();
  }

  Future<OptionMutationResult> create(
    String name, {
    String? imagePath,
    String scenario = 'eat',
  }) => controller.saveOption(
    name: name,
    periods: {MealPeriod.lunch, MealPeriod.dinner},
    imagePath: imagePath,
    scenario: scenario,
  );

  void draw() {
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    expect(controller.result, isNotNull);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-library-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    now = DateTime(2026, 10, 5, 12);
    fault = null;
    await open();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'public create, draw, confirm, deactivate, delete and restore retain identity and image',
    () async {
      final photo = File(path.join(directory.path, 'owned-image.jpg'));
      await photo.writeAsBytes([1, 2, 3]);
      final created = await create('  My  Soup  ', imagePath: photo.path);
      expect(created.status, OptionMutationStatus.saved);
      final option = created.option!;
      expect(option.name, 'My  Soup');
      expect(option.isBuiltIn, isFalse);
      expect(option.category, '未分类');
      draw();
      expect(controller.result!.id, option.id);
      expect(await controller.confirm(), isTrue);
      final confirmed = controller.history.single;
      expect(
        (await controller.setOptionActive(option.id, false)).changed,
        isTrue,
      );
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains(option.id)),
      );
      expect(
        controller.libraryOptions(status: LibraryStatus.inactive).single.id,
        option.id,
      );
      expect(controller.history.single.option.imagePath, photo.path);
      expect((await controller.deleteOption(option.id)).changed, isTrue);
      expect(
        controller
            .libraryOptions(status: LibraryStatus.all)
            .map((option) => option.id),
        isNot(contains(option.id)),
      );
      await reopen();
      expect(controller.history.single.option.isDeleted, isTrue);
      expect(controller.history.single.operationId, confirmed.operationId);
      expect(controller.history.single.option.imagePath, photo.path);
      final restorePrompt = await create('my soup');
      expect(restorePrompt.status, OptionMutationStatus.restorationRequired);
      expect(restorePrompt.option!.id, option.id);
      expect(controller.history.single.option.isDeleted, isTrue);
      final restored = await controller.saveOption(
        name: 'my soup',
        periods: option.periods,
        confirmRestore: true,
      );
      expect(restored.changed, isTrue);
      expect(restored.option!.id, option.id);
      expect(restored.option!.isActive, isTrue);
      expect(restored.option!.isDeleted, isFalse);
      expect(restored.option!.imagePath, photo.path);
      now = DateTime(2026, 10, 6, 12);
      expect(
        await controller.updatePreferences(
          const MealPreferences(excludeYesterday: true),
        ),
        isTrue,
      );
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains(option.id)),
      );
      await reopen();
      expect(controller.history.single.option.name, 'my soup');
      expect(controller.history.single.confirmedAt, confirmed.confirmedAt);
      expect(controller.history.single.option.id, option.id);
      expect(
        await File(controller.history.single.option.imagePath!).readAsBytes(),
        [1, 2, 3],
      );
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains(option.id)),
      );
    },
  );

  test(
    'exact normalization blocks active, inactive, and deleted duplicates without collapsing boundaries',
    () async {
      final created = (await create(' ＳＯＵＰ  Bowl ')).option!;
      for (final name in ['soup bowl', 'SOUP\tBowl', 'Ｓｏｕｐ　Ｂｏｗｌ']) {
        final duplicate = await create(name);
        expect(duplicate.status, OptionMutationStatus.duplicate);
        expect(duplicate.option!.id, created.id);
      }
      await controller.setOptionActive(created.id, false);
      expect(
        (await create('Soup Bowl')).status,
        OptionMutationStatus.duplicate,
      );
      await controller.deleteOption(created.id);
      expect(
        (await create('Soup Bowl')).status,
        OptionMutationStatus.restorationRequired,
      );
      expect((await create('SoupBowl')).changed, isTrue);
      expect((await create('Soup-Bowl')).changed, isTrue);
      final kana = (await create('ｶﾞﾊﾟﾝ')).option!;
      final kanaDuplicate = await create('ガパン');
      expect(kanaDuplicate.status, OptionMutationStatus.duplicate);
      expect(kanaDuplicate.option!.id, kana.id);
      expect((await create('① Soup')).changed, isTrue);
      expect((await create('1 Soup')).changed, isTrue);
      for (final pair in [
        ('￥１２', '¥12'),
        ('\uffa1 Soup', '\u3131 Soup'),
        ('\uffc2 Soup', '\u314f Soup'),
        ('\uffca Soup', '\u3155 Soup'),
        ('\uffd2 Soup', '\u315b Soup'),
        ('\uffda Soup', '\u3161 Soup'),
      ]) {
        final created = await create(pair.$1);
        expect(created.changed, isTrue);
        final duplicate = await create(pair.$2);
        expect(duplicate.status, OptionMutationStatus.duplicate);
        expect(duplicate.option!.id, created.option!.id);
      }
    },
  );

  test(
    'search and status are scoped to scenario; deleted items never appear',
    () async {
      final eat = (await create('Soup Bowl')).option!;
      final cook = (await create('Soup Bowl', scenario: 'cook')).option!;
      expect(controller.libraryOptions(query: 'ＳＯＵＰ').single.id, eat.id);
      expect(
        controller.libraryOptions(query: 'SOUP', scenario: 'cook').single.id,
        cook.id,
      );
      expect(
        controller.candidates.map((option) => option.id),
        isNot(contains(cook.id)),
      );
      await controller.setOptionActive(eat.id, false);
      expect(controller.libraryOptions(query: 'Soup'), isEmpty);
      expect(
        controller
            .libraryOptions(query: 'Soup', status: LibraryStatus.all)
            .single
            .id,
        eat.id,
      );
      await controller.deleteOption(eat.id);
      for (final status in LibraryStatus.values) {
        expect(
          controller.libraryOptions(query: 'Soup', status: status),
          isEmpty,
        );
      }
      expect(
        controller.libraryOptions(query: 'Soup', scenario: 'cook').single.id,
        cook.id,
      );
    },
  );

  test(
    'only durable actual changes invalidate; unchanged, invalid, and duplicate actions preserve the round',
    () async {
      await controller.saveCategory(name: '汤');
      final option = (await create('Soup')).option!;
      expect(option.art, 'plate');
      controller.excludeForSession('soy-milk');
      draw();
      final chosen = controller.result;
      expect(
        (await controller.saveOption(
          id: option.id,
          name: ' Soup ',
          periods: option.periods,
        )).status,
        OptionMutationStatus.unchanged,
      );
      expect(
        (await controller.setOptionActive(option.id, true)).status,
        OptionMutationStatus.unchanged,
      );
      expect((await create('SOUP')).status, OptionMutationStatus.duplicate);
      expect((await create('   ')).status, OptionMutationStatus.invalid);
      expect(
        (await controller.saveOption(name: 'No periods', periods: {})).status,
        OptionMutationStatus.invalid,
      );
      expect(controller.result, same(chosen));
      expect(controller.isModeLocked, isTrue);
      expect(controller.restartNotice, isNull);
      expect(
        (await controller.saveOption(
          id: option.id,
          name: option.name,
          periods: option.periods,
          category: '汤',
        )).changed,
        isTrue,
      );
      expect(controller.hasRound, isFalse);
      expect(controller.isModeLocked, isFalse);
      expect(controller.takeRestartNotice(), isNotNull);
      expect(controller.sessionExclusions, {'soy-milk'});
      draw();
      expect((await create('Other soup', scenario: 'cook')).changed, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.takeRestartNotice(), isNotNull);
    },
  );

  test(
    'rename requires identity confirmation, blocks duplicates, and updates retained history',
    () async {
      final option = (await create('Soup')).option!;
      draw();
      expect(await controller.confirm(), isTrue);
      final timestamp = controller.history.single.confirmedAt;
      draw();
      final chosen = controller.result;
      final pending = await controller.saveOption(
        id: option.id,
        name: 'Better soup',
        periods: option.periods,
      );
      expect(pending.status, OptionMutationStatus.renameConfirmationRequired);
      expect(controller.result, same(chosen));
      final renamed = await controller.saveOption(
        id: option.id,
        name: 'Better soup',
        periods: option.periods,
        confirmSameFood: true,
      );
      expect(renamed.changed, isTrue);
      expect(renamed.option!.id, option.id);
      expect(controller.history.single.option.name, 'Better soup');
      expect(controller.history.single.confirmedAt, timestamp);
      final blocked = await controller.saveOption(
        id: option.id,
        name: '牛肉面',
        periods: option.periods,
        confirmSameFood: true,
      );
      expect(blocked.status, OptionMutationStatus.duplicate);
      expect(controller.history.single.option.name, 'Better soup');
    },
  );

  test(
    'builtin protections are enforced beyond the form and display edits retain periods',
    () async {
      final builtin = controller.options.first;
      draw();
      final selected = controller.result;
      expect(
        (await controller.deleteOption(builtin.id)).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await controller.saveOption(
          id: builtin.id,
          name: builtin.name,
          periods: {MealPeriod.breakfast},
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(
        (await controller.saveOption(
          id: builtin.id,
          name: builtin.name,
          periods: builtin.periods,
          category: '新分类',
        )).status,
        OptionMutationStatus.invalid,
      );
      expect(controller.result, same(selected));
      final renamed = await controller.saveOption(
        id: builtin.id,
        name: '黄焖鸡套餐',
        category: builtin.category,
        periods: builtin.periods,
        confirmSameFood: true,
      );
      expect(renamed.changed, isTrue);
      expect(renamed.option!.isBuiltIn, isTrue);
      expect(renamed.option!.periods, builtin.periods);
      expect(renamed.option!.category, builtin.category);
      expect(
        (await controller.setOptionActive(builtin.id, false)).changed,
        isTrue,
      );
      expect(
        (await controller.setOptionActive(builtin.id, true)).changed,
        isTrue,
      );
    },
  );

  test(
    'failed SQLite mutation rolls back metadata and periods and leaves the round usable',
    () async {
      await controller.saveCategory(name: '汤');
      final option = (await create('Soup')).option!;
      final database = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await database.execute('''
        CREATE TRIGGER fail_period AFTER INSERT ON option_periods
        WHEN NEW.option_id = '${option.id}'
        BEGIN SELECT RAISE(ABORT, 'Injected period failure'); END
      ''');
        draw();
        final chosen = controller.result;
        final failed = await controller.saveOption(
          id: option.id,
          name: option.name,
          category: '汤',
          periods: {MealPeriod.breakfast},
        );
        expect(failed.status, OptionMutationStatus.failed);
        expect(controller.result, same(chosen));
        expect(controller.restartNotice, isNull);
        final persisted = (await repository.options()).firstWhere(
          (item) => item.id == option.id,
        );
        expect(persisted.category, option.category);
        expect(persisted.periods, option.periods);
        await database.execute('DROP TRIGGER fail_period');
        expect(
          (await controller.saveOption(
            id: option.id,
            name: option.name,
            category: '汤',
            periods: {MealPeriod.breakfast},
          )).changed,
          isTrue,
        );
        expect(controller.hasRound, isFalse);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'mutation reserves the boundary, waits for confirmation, and serializes competing duplicates',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fault = (phase) async {
        if (phase == ConfirmationPhase.afterHeaderWritten) {
          entered.complete();
          await release.future;
        }
      };
      final option = (await create('Soup')).option!;
      draw();
      final confirmation = controller.confirm();
      await entered.future;
      final deletion = controller.deleteOption(option.id);
      final firstCreate = create('New soup');
      final secondCreate = create('ＮＥＷ Soup');
      expect(controller.isBusy, isTrue);
      expect(await controller.confirm(), isFalse);
      expect(controller.startDraw(), isFalse);
      release.complete();
      expect(await confirmation, isTrue);
      expect((await deletion).changed, isTrue);
      expect((await firstCreate).changed, isTrue);
      expect((await secondCreate).status, OptionMutationStatus.duplicate);
      expect(controller.history, hasLength(1));
      expect(controller.history.single.option.id, option.id);
      expect(controller.history.single.option.isDeleted, isTrue);
      expect(controller.isBusy, isFalse);
      expect(controller.libraryOptions(query: 'new soup'), hasLength(1));
    },
  );

  test(
    'new-option local period follows the clock rather than the manual draw period',
    () async {
      controller.changePeriod(MealPeriod.lateNight);
      expect(controller.currentLocalPeriod, MealPeriod.lunch);
      now = DateTime(2026, 10, 5, 19);
      expect(controller.currentLocalPeriod, MealPeriod.dinner);
      expect(controller.period, MealPeriod.lateNight);
    },
  );

  for (final version in [1, 2]) {
    test(
      'v$version upgrade preserves original seed IDs, history, and preference pair',
      () async {
        controller.dispose();
        await repository.close();
        await File(databasePath).delete();
        final legacy = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: version,
            onCreate: (database, _) async {
              await database.execute(
                'CREATE TABLE options (id TEXT PRIMARY KEY, name TEXT NOT NULL, art TEXT NOT NULL)',
              );
              await database.execute(
                'CREATE TABLE option_periods (option_id TEXT NOT NULL REFERENCES options(id), period TEXT NOT NULL, PRIMARY KEY (option_id, period))',
              );
              await database.execute(
                'CREATE TABLE history_records (operation_id TEXT PRIMARY KEY, confirmed_at INTEGER NOT NULL, period TEXT NOT NULL)',
              );
              await database.execute(
                'CREATE TABLE history_items (operation_id TEXT NOT NULL REFERENCES history_records(operation_id), position INTEGER NOT NULL, option_id TEXT NOT NULL REFERENCES options(id), PRIMARY KEY (operation_id, position))',
              );
              for (final option in seedOptions.take(8)) {
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
                'operation_id': 'legacy-confirmation',
                'confirmed_at': now.microsecondsSinceEpoch,
                'period': 'lunch',
              });
              await database.insert('history_items', {
                'operation_id': 'legacy-confirmation',
                'position': 0,
                'option_id': 'rice',
              });
              if (version == 2) {
                await database.execute(
                  'CREATE TABLE preferences (id INTEGER PRIMARY KEY, mode TEXT NOT NULL, exclude_yesterday INTEGER NOT NULL)',
                );
                await database.insert('preferences', {
                  'id': 1,
                  'mode': 'cards',
                  'exclude_yesterday': 1,
                });
              }
            },
          ),
        );
        await legacy.close();
        await open();
        expect(
          controller.options.map((option) => option.id),
          seedOptions.map((option) => option.id),
        );
        expect(
          controller.options.every(
            (option) =>
                option.isBuiltIn && option.isActive && !option.isDeleted,
          ),
          isTrue,
        );
        expect(controller.history.single.option.id, 'rice');
        expect(controller.history.single.confirmedAt, now.toUtc());
        expect(controller.history.single.operationId, 'legacy-confirmation');
        expect(
          controller.preferences.mode,
          version == 2 ? DrawMode.cards : DrawMode.wheel,
        );
        expect(controller.preferences.excludeYesterday, version == 2);
        expect((await create('Soup')).changed, isTrue);
        await reopen();
        expect(controller.history.single.operationId, 'legacy-confirmation');
        expect(controller.libraryOptions(query: 'Soup'), hasLength(1));
        final inspector = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          expect(await inspector.getVersion(), 5);
          expect(await inspector.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await inspector.close();
        }
      },
    );
  }
}
