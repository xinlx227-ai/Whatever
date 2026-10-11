import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/option_art.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-history-ui-');
    databasePath = path.join(directory.path, 'meal.sqlite');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 11, 12, 30),
      random: Random(37),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  FoodOption option(String id) =>
      controller.options.singleWhere((option) => option.id == id);
  List<FoodOption> dishes() => [
    option('cook-mapo-tofu'),
    option('cook-twice-cooked-pork'),
    option('cook-cucumber'),
  ];

  Future<void> record(
    WidgetTester tester,
    String id,
    List<FoodOption> options, {
    DateTime? at,
  }) async {
    await tester.runAsync(
      () => repository.confirm(
        ConfirmationOperation(
          operationId: id,
          confirmedAt: at ?? DateTime(2026, 10, 11, 12, 30),
          period: MealPeriod.lunch,
          options: options,
        ),
      ),
    );
    await tester.runAsync(() => controller.applyDataChange(changed: true));
  }

  Future<void> inspect(
    WidgetTester tester,
    Future<void> Function(Database) action,
  ) async {
    await tester.runAsync(() async {
      final database = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await action(database);
      } finally {
        await database.close();
      }
    });
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(430, 932),
    double scale = 1,
    bool safeArea = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    if (safeArea) {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    // Start persisted UI actions in the real async zone, including the future
    // awaiting the deletion dialog. SQLite cannot progress in fake test time.
    await tester.runAsync(() => tester.tap(target));
    await tester.pumpAndSettle();
  }

  Future<void> finishMutation(WidgetTester tester, String buttonKey) async {
    await reveal(tester, key(buttonKey));
    await tester.runAsync(() async {
      final completed = Completer<void>();
      var started = false;
      void observeMutation() {
        if (controller.isBusy) {
          started = true;
        } else if (started && !completed.isCompleted) {
          completed.complete();
        }
      }

      controller.addListener(observeMutation);
      try {
        await tester.tap(key(buttonKey));
        await tester.pump();
        await completed.future.timeout(const Duration(seconds: 10));
      } finally {
        controller.removeListener(observeMutation);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> confirmDeletion(WidgetTester tester) =>
      finishMutation(tester, 'confirm-history-delete');

  testWidgets('committed deletion survives refresh failure and can recover', (
    tester,
  ) async {
    await record(tester, 'retained', [option('rice')]);
    await record(tester, 'removed', dishes());
    await mount(tester);
    await tap(tester, find.text('足迹'));
    await tap(tester, key('history-removed'));
    await tap(tester, key('delete-history-record'));
    await inspect(
      tester,
      (db) => db.execute('ALTER TABLE options RENAME TO unavailable_options'),
    );
    await confirmDeletion(tester);

    expect(controller.history.map((entry) => entry.operationId), ['retained']);
    expect(find.text('足迹详情'), findsNothing);
    expect(key('history-removed'), findsNothing);
    expect(key('history-retained'), findsOneWidget);
    expect(find.text('足迹已删除，但本地数据刷新失败，请重试刷新。'), findsOneWidget);
    expect(find.text('本地数据暂时未能刷新，请重试。'), findsOneWidget);
    expect(controller.canDraw, isFalse);
    await inspect(tester, (db) async {
      expect(
        await db.query(
          'history_records',
          where: 'operation_id = ?',
          whereArgs: ['removed'],
        ),
        isEmpty,
      );
    });

    await finishMutation(tester, 'retry-history-refresh');
    expect(find.text('本地数据暂时未能刷新，请重试。'), findsOneWidget);
    expect(key('history-removed'), findsNothing);
    expect(controller.canDraw, isFalse);
    await inspect(
      tester,
      (db) => db.execute('ALTER TABLE unavailable_options RENAME TO options'),
    );
    await finishMutation(tester, 'retry-history-refresh');
    expect(key('retry-history-refresh'), findsNothing);
    expect(controller.error, isNull);
    expect(controller.canDraw, isTrue);
    expect(controller.history.single.operationId, 'retained');
    expect(
      (await tester.runAsync(repository.history))!.single.operationId,
      'retained',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all records default to date order with one row per batch',
    (tester) async {
      final selected = dishes();
      await record(tester, 'older', [
        option('restaurant-haidilao'),
      ], at: DateTime(2026, 10, 10, 12, 30));
      await record(tester, 'same-time-first', [option('rice')]);
      await record(tester, 'same-time-last', selected);
      await record(tester, 'latest', [
        option('restaurant-kfc'),
      ], at: DateTime(2026, 10, 11, 13, 45));
      await mount(tester);
      await tap(tester, find.text('足迹'));

      expect(
        tester.widget<ChoiceChip>(key('history-filter-all')).selected,
        isTrue,
      );
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((tile) => tile.key),
        [
          const ValueKey('history-latest'),
          const ValueKey('history-same-time-last'),
          const ValueKey('history-same-time-first'),
          const ValueKey('history-older'),
        ],
      );
      expect(
        find.text(selected.map((dish) => dish.name).join('、')),
        findsOneWidget,
      );
      expect(find.text('2026年10月11日'), findsOneWidget);
      expect(find.text('2026年10月10日'), findsOneWidget);
      expect(find.text('13:45 · 午餐 · 去哪吃'), findsOneWidget);
      expect(find.text('12:30 · 午餐 · 做什么'), findsOneWidget);
      await tap(tester, key('history-latest'));
      expect(find.text('这次选择 · 共 1 项'), findsOneWidget);
      expect(find.text(option('restaurant-kfc').name), findsOneWidget);
      expect(key('history-detail-restaurant-kfc'), findsOneWidget);
      expect(find.text('13:45 · 午餐 · 去哪吃'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scenario filters stay independent and empty filter recovers all',
    (tester) async {
      await record(tester, 'eat', [option('rice')]);
      await record(tester, 'cook', dishes());
      controller.changeScenario(MealScenario.cook);
      controller.changePeriod(MealPeriod.dinner);
      final candidates = controller.candidates.map((item) => item.id).toList();
      final preferences = controller.preferences;
      await mount(tester);
      await tap(tester, find.text('选项库'));
      await tap(tester, key('library-scenario-restaurant'));
      await tap(tester, find.text('足迹'));

      await tap(tester, key('history-filter-eat'));
      expect(key('history-eat'), findsOneWidget);
      expect(key('history-cook'), findsNothing);
      await tap(tester, key('history-filter-cook'));
      expect(key('history-eat'), findsNothing);
      expect(key('history-cook'), findsOneWidget);
      await tap(tester, key('history-filter-restaurant'));
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('这个场景还没有足迹'), findsOneWidget);
      expect(find.text('去决定这一餐'), findsNothing);
      await tap(tester, find.text('查看全部足迹'));
      expect(key('history-eat'), findsOneWidget);
      expect(key('history-cook'), findsOneWidget);
      await tap(tester, key('history-filter-cook'));
      await tap(tester, find.text('选项库'));
      expect(
        tester.widget<ChoiceChip>(key('library-scenario-restaurant')).selected,
        isTrue,
      );
      await tap(tester, find.text('决定'));
      expect(
        tester.widget<ChoiceChip>(key('decide-scenario-cook')).selected,
        isTrue,
      );
      expect(controller.scenario, MealScenario.cook);
      expect(controller.period, MealPeriod.dinner);
      expect(controller.candidates.map((item) => item.id), candidates);
      expect(controller.preferences, same(preferences));
      expect(controller.hasRound, isFalse);
      await tap(tester, find.text('足迹'));
      expect(
        tester.widget<ChoiceChip>(key('history-filter-cook')).selected,
        isTrue,
      );
      expect(key('history-eat'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty history directs the user to deciding a meal', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('足迹'));
    expect(find.text('第一餐，值得期待'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    await tap(tester, find.text('去决定这一餐'));
    expect(key('primary-action'), findsOneWidget);
    expect(controller.hasRound, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail preserves order and resolves renamed deleted custom art',
    (tester) async {
      late FoodOption custom;
      late String replacementImage;
      await tester.runAsync(() async {
        final source = File(
          'docs/design/assets/card-back-celestial-black-purple-gold.png',
        );
        final initialImage = (await source.copy(
          path.join(directory.path, 'first.png'),
        )).path;
        replacementImage = (await source.copy(
          path.join(directory.path, 'current.png'),
        )).path;
        custom = (await controller.saveOption(
          name: '我的历史配菜',
          scenario: 'cook',
          periods: {MealPeriod.lunch},
          imagePath: initialImage,
        )).option!;
      });
      final selected = [dishes()[1], custom, dishes()[0]];
      await record(tester, 'references', selected);
      await tester.runAsync(() async {
        final renamed = await controller.saveOption(
          id: custom.id,
          name: '改名后的配菜',
          scenario: 'cook',
          periods: custom.periods,
          imagePath: replacementImage,
          confirmSameFood: true,
        );
        expect(renamed.changed, isTrue);
        expect((await controller.deleteOption(custom.id)).changed, isTrue);
      });
      await mount(tester);
      await tap(tester, find.text('足迹'));
      expect(
        find.text('${selected[0].name}、改名后的配菜、${selected[2].name}'),
        findsOneWidget,
      );
      await tap(tester, key('history-references'));
      expect(find.text('这次选择 · 共 3 项'), findsOneWidget);
      final art = tester
          .widgetList<OptionArt>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(OptionArt),
            ),
          )
          .toList();
      expect(
        art.map((widget) => widget.option.id),
        selected.map((dish) => dish.id),
      );
      expect(art[1].option.name, '改名后的配菜');
      expect(art[1].option.isDeleted, isTrue);
      expect(art[1].option.imagePath, replacementImage);
      final image = tester.widget<Image>(
        find.descendant(
          of: key('history-detail-${custom.id}'),
          matching: find.byType(Image),
        ),
      );
      final provider = image.image;
      final fileImage = provider is ResizeImage
          ? provider.imageProvider
          : provider;
      expect((fileImage as FileImage).file.path, replacementImage);
      expect(find.text('我的历史配菜'), findsNothing);
      expect(find.text('2026年10月11日'), findsOneWidget);
      expect(find.text('12:30 · 午餐 · 做什么'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling deletion retains the entire record and detail', (
    tester,
  ) async {
    final selected = dishes();
    await record(tester, 'cancel', selected);
    await mount(tester);
    await tap(tester, find.text('足迹'));
    await tap(tester, key('history-cancel'));
    await tap(tester, key('delete-history-record'));
    expect(find.text('删除这条足迹？'), findsOneWidget);
    expect(find.text('将删除这次选择的完整记录（共 3 项），无法恢复。选项库中的内容会保留。'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(find.text('足迹详情'), findsOneWidget);
    expect(
      controller.history.single.options.map((item) => item.id),
      selected.map((item) => item.id),
    );
    final stored = await tester.runAsync(repository.history);
    expect(stored!.single.options, hasLength(3));
    await tap(tester, find.byType(BackButton));
    expect(key('history-cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed deletion removes a whole batch and keeps the filter', (
    tester,
  ) async {
    final selected = dishes();
    await record(tester, 'retained', [option('rice')]);
    await record(tester, 'delete', selected);
    await mount(tester);
    await tap(tester, find.text('足迹'));
    await tap(tester, key('history-filter-cook'));
    await tap(tester, key('history-delete'));
    await tap(tester, key('delete-history-record'));
    await confirmDeletion(tester);

    expect(find.text('足迹详情'), findsNothing);
    expect(find.text('已删除这条足迹'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(key('history-filter-cook')).selected,
      isTrue,
    );
    expect(find.text('这个场景还没有足迹'), findsOneWidget);
    expect(controller.history.single.operationId, 'retained');
    expect(
      selected.every(
        (dish) => controller.options.any(
          (item) => item.id == dish.id && item.isActive && !item.isDeleted,
        ),
      ),
      isTrue,
    );
    await inspect(tester, (db) async {
      expect(
        await db.query(
          'history_items',
          where: 'operation_id = ?',
          whereArgs: ['delete'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'history_records',
          where: 'operation_id = ?',
          whereArgs: ['delete'],
        ),
        isEmpty,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
    await tap(tester, find.text('查看全部足迹'));
    expect(key('history-retained'), findsOneWidget);
    expect(key('history-delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed deletion keeps detail and the full batch for retry', (
    tester,
  ) async {
    final selected = dishes();
    await record(tester, 'retry', selected);
    await inspect(
      tester,
      (db) => db.execute('''
      CREATE TRIGGER reject_history_delete BEFORE DELETE ON history_records
      BEGIN SELECT RAISE(ABORT, 'injected deletion failure'); END
    '''),
    );
    await mount(tester);
    await tap(tester, find.text('足迹'));
    await tap(tester, key('history-retry'));
    await tap(tester, key('delete-history-record'));
    await confirmDeletion(tester);

    expect(find.text('足迹详情'), findsOneWidget);
    expect(find.text('删除失败，请重试。'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(key('delete-history-record')).onPressed,
      isNotNull,
    );
    expect(
      controller.history.single.options.map((item) => item.id),
      selected.map((item) => item.id),
    );
    final stored = await tester.runAsync(repository.history);
    expect(
      stored!.single.options.map((item) => item.id),
      selected.map((item) => item.id),
    );
    await inspect(
      tester,
      (db) => db.execute('DROP TRIGGER reject_history_delete'),
    );
    await tap(tester, key('delete-history-record'));
    await confirmDeletion(tester);
    expect(find.text('足迹详情'), findsNothing);
    expect(find.text('第一餐，值得期待'), findsOneWidget);
    expect(controller.history, isEmpty);
    expect(await tester.runAsync(repository.history), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final mode in DrawMode.values) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets(
        'history detail is reachable in $mode at $size with 2x text',
        (tester) async {
          await record(tester, 'large', dishes().take(2).toList());
          await tester.runAsync(
            () => controller.updatePreferences(
              controller.preferences.copyWith(mode: mode),
            ),
          );
          await mount(tester, size: size, scale: 2, safeArea: true);
          await tap(tester, find.text('足迹'));
          await tap(tester, key('history-filter-cook'));
          await tap(tester, key('history-large'));
          await reveal(tester, key('delete-history-record'));
          expect(key('delete-history-record').hitTestable(), findsOneWidget);
          expect(
            tester.getBottomLeft(key('delete-history-record')).dy,
            lessThanOrEqualTo(size.height - 24),
          );
          expect(
            Theme.of(tester.element(key('delete-history-record'))).brightness,
            mode == DrawMode.cards ? Brightness.dark : Brightness.light,
          );
          await tap(tester, key('delete-history-record'));
          await reveal(tester, key('confirm-history-delete'));
          expect(key('confirm-history-delete').hitTestable(), findsOneWidget);
          await tap(tester, find.text('取消'));
          expect(controller.history.single.options, hasLength(2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
