import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/data/option_images.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/meal_app.dart';
import 'package:whatever/presentation/option_editor.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-editor-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 6, 12, 30),
      random: Random(37),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  final name = find.byKey(const Key('option-name'));
  final save = find.byKey(const Key('save-option'));
  Finder period(MealPeriod value) =>
      find.widgetWithText(FilterChip, value.label);

  Future<void> mountEditor(
    WidgetTester tester, {
    FoodOption? option,
    Future<String?> Function()? pickImage,
    OptionImages? images,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => OptionEditor(
                    controller: controller,
                    option: option,
                    pickImage: pickImage,
                    images: images,
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> finishSaveFlow(WidgetTester tester) async {
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(OptionEditor).evaluate().isNotEmpty &&
        tester.widget<FilledButton>(save).onPressed == null &&
        find.byType(AlertDialog).evaluate().isEmpty &&
        find.byType(SimpleDialog).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Editor save did not finish');
      }
      // Image persistence and cleanup can outlive the controller write itself.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(save));
    await finishSaveFlow(tester);
  }

  FoodOption startRound() {
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    return controller.result!;
  }

  Future<void> answerSaveDialog(WidgetTester tester, String label) async {
    // The save flow started in runAsync; resume its dialog continuation there.
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.isBusy) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Dialog mutation did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    await finishSaveFlow(tester);
  }

  Future<FoodOption> create(WidgetTester tester, String value) async {
    final result = await tester.runAsync(
      () => controller.saveOption(name: value, periods: {MealPeriod.lunch}),
    );
    expect(result!.changed, isTrue);
    return result.option!;
  }

  testWidgets('new form defaults to local time, not the selected draw period', (
    tester,
  ) async {
    expect(controller.changePeriod(MealPeriod.dinner), isTrue);
    await mountEditor(tester);
    expect(
      tester.widget<FilterChip>(period(MealPeriod.lunch)).selected,
      isTrue,
    );
    expect(
      tester.widget<FilterChip>(period(MealPeriod.dinner)).selected,
      isFalse,
    );
    expect(find.text('未分类'), findsOneWidget);
    await tester.enterText(name, '  番茄鸡蛋面  ');
    await tapSave(tester);
    expect(find.byType(OptionEditor), findsNothing);
    final option = controller.options.singleWhere((food) => !food.isBuiltIn);
    expect(option.name, '番茄鸡蛋面');
    expect(option.periods, {MealPeriod.lunch});
    expect(option.category, '面食');
    expect(option.imagePath, isNull);
    expect(controller.period, MealPeriod.dinner);
  });

  testWidgets('name and a meal period are required before any library write', (
    tester,
  ) async {
    final selected = startRound();
    await mountEditor(tester);
    await tester.enterText(name, '   ');
    await tapSave(tester);
    expect(find.text('请填写名称。'), findsOneWidget);
    await tester.enterText(name, '番茄鸡蛋面');
    await tester.ensureVisible(period(MealPeriod.lunch));
    await tester.tap(period(MealPeriod.lunch));
    await tapSave(tester);
    expect(find.text('请至少选择一个餐段。'), findsOneWidget);
    expect(controller.options, hasLength(seedOptions.length));
    expect(controller.result, same(selected));
    final stored = await tester.runAsync(repository.options);
    expect(stored, hasLength(seedOptions.length));
  });

  testWidgets('classification follows input until a manual choice is made', (
    tester,
  ) async {
    await mountEditor(tester);
    final dropdown = find.byKey(const Key('option-category'));
    await tester.enterText(name, '番茄鸡蛋面');
    await tester.pumpAndSettle();
    expect(find.text('已根据名称分类，可手动修改'), findsOneWidget);
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
      controller
          .categoriesFor(MealScenario.eat)
          .singleWhere((value) => value.name == '面食')
          .id,
    );
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('轻食').last);
    await tester.pumpAndSettle();
    await tester.enterText(name, '南瓜粥');
    await tester.pumpAndSettle();
    expect(find.text('已保留你的分类选择'), findsOneWidget);
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
      controller
          .categoriesFor(MealScenario.eat)
          .singleWhere((value) => value.name == '轻食')
          .id,
    );
  });

  testWidgets('uncertain duplicates allow inspection and explicit creation', (
    tester,
  ) async {
    final selected = startRound();
    await mountEditor(tester);
    await tester.enterText(name, '牛肉面特色版');
    await tapSave(tester);
    expect(find.text('可能已有相似选项'), findsOneWidget);
    expect(controller.result, same(selected));
    await answerSaveDialog(tester, '查看已有选项');
    expect(find.text('返回表单'), findsOneWidget);
    await answerSaveDialog(tester, '返回表单');
    expect(find.text('仍然添加'), findsOneWidget);
    await answerSaveDialog(tester, '仍然添加');
    expect(find.byType(OptionEditor), findsNothing);
    expect(controller.options.any((value) => value.name == '牛肉面特色版'), isTrue);
    expect(controller.hasRound, isFalse);
    expect(controller.takeRestartNotice(), isNotNull);
  });

  testWidgets('confirmed added ingredients block creation with no override', (
    tester,
  ) async {
    final selected = startRound();
    await mountEditor(tester);
    await tester.enterText(name, '牛肉面加蛋');
    await tapSave(tester);
    expect(find.text('已有相同餐食'), findsOneWidget);
    expect(find.text('仍然添加'), findsNothing);
    expect(controller.result, same(selected));
    await answerSaveDialog(tester, '取消');
    expect(controller.options.where((value) => !value.isBuiltIn), isEmpty);
  });

  testWidgets(
    'multiple deleted aliases require selecting a restoration target',
    (tester) async {
      await tester.runAsync(() async {
        final database = await databaseFactoryFfi.openDatabase(
          path.join(directory.path, 'meal.sqlite'),
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          for (final (id, label) in [
            ('old-tomato-1', '番茄鸡蛋面'),
            ('old-tomato-2', '西红柿鸡蛋面'),
          ]) {
            await database.insert('options', {
              'id': id,
              'name': label,
              'art': 'noodle',
              'scenario': 'eat',
              'category': '未分类',
              'is_builtin': 0,
              'is_active': 0,
              'is_deleted': 1,
            });
            await database.insert('option_periods', {
              'option_id': id,
              'period': 'dinner',
            });
            await database.insert('option_categories', {
              'option_id': id,
              'category': '未分类',
            });
          }
        } finally {
          await database.close();
        }
        await controller.initialize();
      });
      final selected = startRound();
      await mountEditor(tester);
      await tester.enterText(name, '番茄鸡蛋面少油');
      await tapSave(tester);
      expect(find.text('选择要恢复的原选项'), findsOneWidget);
      expect(find.text('恢复并保存'), findsNothing);
      expect(controller.result, same(selected));
      await answerSaveDialog(tester, '取消');
      expect(controller.result, same(selected));
      await tapSave(tester);
      await tester.runAsync(() async {
        await tester.tap(find.textContaining('2. 西红柿鸡蛋面'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('本次表单的名称、分类和餐段会覆盖'), findsOneWidget);
      await answerSaveDialog(tester, '恢复并保存');
      expect(
        controller.options
            .singleWhere((value) => value.id == 'old-tomato-1')
            .isDeleted,
        isTrue,
      );
      final restored = controller.options.singleWhere(
        (value) => value.id == 'old-tomato-2',
      );
      expect(restored.isDeleted, isFalse);
      expect(restored.name, '番茄鸡蛋面少油');
      expect(restored.periods, {MealPeriod.lunch});
      expect(controller.hasRound, isFalse);
    },
  );

  testWidgets('curated alias rename saves directly and remains searchable', (
    tester,
  ) async {
    final original = await create(tester, '番茄鸡蛋面');
    await mountEditor(tester, option: original);
    await tester.enterText(name, '西红柿鸡蛋面');
    await tapSave(tester);
    expect(find.byType(OptionEditor), findsNothing);
    expect(controller.libraryOptions(query: '番茄鸡蛋面').single.id, original.id);
    expect(
      controller
          .libraryOptions(scenario: 'cook', query: '番茄鸡蛋面')
          .every((value) => value.scenario == 'cook'),
      isTrue,
    );
    final updated = controller.options.singleWhere(
      (value) => value.id == original.id,
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(name, '鸡肉面');
    await tapSave(tester);
    expect(find.textContaining('不同的餐食'), findsOneWidget);
    expect(
      controller.options.singleWhere((value) => value.id == original.id).name,
      updated.name,
    );
  });

  testWidgets('Back cancel and discard leave an unfinished round untouched', (
    tester,
  ) async {
    final selected = startRound();
    await mountEditor(tester);
    await tester.enterText(name, '未保存的餐食');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(name).controller!.text, '未保存的餐食');
    expect(controller.result, same(selected));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(OptionEditor), findsNothing);
    expect(controller.result, same(selected));
    expect(controller.options, hasLength(seedOptions.length));
    expect(controller.restartNotice, isNull);
  });

  testWidgets(
    'no-op save preserves a round; saved period edits invalidate it',
    (tester) async {
      final original = await create(tester, '番茄鸡蛋面');
      final selected = startRound();
      await mountEditor(tester, option: original);
      await tapSave(tester);
      expect(find.byType(OptionEditor), findsNothing);
      expect(controller.result, same(selected));
      expect(controller.restartNotice, isNull);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(period(MealPeriod.dinner));
      await tester.tap(period(MealPeriod.dinner));
      await tapSave(tester);
      expect(controller.hasRound, isFalse);
      expect(controller.result, isNull);
      expect(controller.restartNotice, isNotNull);
      final stored = await tester.runAsync(repository.options);
      expect(stored!.singleWhere((food) => food.id == original.id).periods, {
        MealPeriod.lunch,
        MealPeriod.dinner,
      });
    },
  );

  testWidgets('canceled image picker leaves an unchanged form clean', (
    tester,
  ) async {
    final selected = startRound();
    var picks = 0;
    await mountEditor(
      tester,
      option: controller.options.first,
      pickImage: () async {
        picks++;
        return null;
      },
    );
    await tester.tap(find.byKey(const Key('pick-option-image')));
    await tester.pumpAndSettle();
    expect(picks, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OptionEditor), findsNothing);
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(controller.result, same(selected));
    expect(controller.restartNotice, isNull);
  });

  testWidgets(
    'discard after image duplicate rejection removes the unused owned copy',
    (tester) async {
      await create(tester, '已有餐食');
      final selected = startRound();
      final source = File(path.join(directory.path, 'picker.png'));
      await tester.runAsync(
        () => source.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/jPwPAfAAUAAf+mXJtdAAAAAElFTkSuQmCC',
          ),
        ),
      );
      await mountEditor(
        tester,
        pickImage: () async => source.path,
        images: OptionImages(directory: () async => directory),
      );
      await tester.enterText(name, '已有餐食');
      await tester.tap(find.byKey(const Key('pick-option-image')));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(find.text('已有相同餐食'), findsOneWidget);
      expect(find.text('重新启用'), findsNothing);
      await answerSaveDialog(tester, '取消');
      final ownedDirectory = Directory(
        path.join(directory.path, 'option-images'),
      );
      final candidates = await tester.runAsync(
        () => ownedDirectory.list().toList(),
      );
      expect(candidates, hasLength(1));
      final owned = File(candidates!.single.path);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.byType(OptionEditor), findsNothing);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await tester.runAsync(owned.exists) == true) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Unused owned image was not removed');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(await tester.runAsync(source.exists), isTrue);
      expect(controller.result, same(selected));
      expect(
        controller.options.where((option) => !option.isBuiltIn),
        hasLength(1),
      );
      expect(controller.restartNotice, isNull);
    },
  );

  testWidgets(
    'duplicate viewing preserves draft and round; reactivation retains durable identity',
    (tester) async {
      final original = await create(tester, 'My Noodles');
      await tester.runAsync(
        () => controller.setOptionActive(original.id, false),
      );
      final selected = startRound();
      await mountEditor(tester);
      await tester.enterText(name, '  ＭＹ   ＮＯＯＤＬＥＳ  ');
      await tapSave(tester);
      expect(find.byType(OptionEditor), findsOneWidget);
      expect(find.text('已有相同餐食'), findsOneWidget);
      expect(controller.options.where((food) => !food.isBuiltIn), hasLength(1));
      expect(controller.result, same(selected));
      expect(controller.restartNotice, isNull);
      await answerSaveDialog(tester, '取消');
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        '  ＭＹ   ＮＯＯＤＬＥＳ  ',
      );
      expect(controller.result, same(selected));
      expect(
        controller.options
            .singleWhere((food) => food.id == original.id)
            .isActive,
        isFalse,
      );

      await tapSave(tester);
      await answerSaveDialog(tester, '查看已有选项');
      expect(find.text(original.name), findsOneWidget);
      expect(find.text('未分类 · 已停用'), findsOneWidget);
      expect(controller.result, same(selected));
      await answerSaveDialog(tester, '返回表单');
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        '  ＭＹ   ＮＯＯＤＬＥＳ  ',
      );
      expect(controller.restartNotice, isNull);

      await tapSave(tester);
      await answerSaveDialog(tester, '重新启用');
      expect(find.byType(OptionEditor), findsNothing);
      final existing = controller.options.singleWhere(
        (food) => !food.isBuiltIn,
      );
      expect(existing.id, original.id);
      expect(existing.name, original.name);
      expect(existing.periods, original.periods);
      expect(existing.isActive, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.restartNotice, isNotNull);
      final durable = (await tester.runAsync(
        repository.options,
      ))!.singleWhere((food) => !food.isBuiltIn);
      expect(durable.id, original.id);
      expect(durable.isActive, isTrue);
    },
  );

  testWidgets(
    'restoring a deleted option with a new photo removes the previous owned photo',
    (tester) async {
      final images = OptionImages(directory: () async => directory);
      final oldSource = File(path.join(directory.path, 'red.png'));
      final newSource = File(path.join(directory.path, 'blue.png'));
      final replacementBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY2Bg+P8fAAMCAf/Jsq3uAAAAAElFTkSuQmCC',
      );
      late String oldOwned;
      late FoodOption original;
      await tester.runAsync(() async {
        await oldSource.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/jPwPAfAAUAAf+mXJtdAAAAAElFTkSuQmCC',
          ),
        );
        await newSource.writeAsBytes(replacementBytes);
        oldOwned = await images.persist(oldSource.path);
        final saved = await controller.saveOption(
          name: '恢复餐食',
          periods: {MealPeriod.lunch},
          imagePath: oldOwned,
        );
        original = saved.option!;
        await controller.deleteOption(original.id);
      });
      await mountEditor(
        tester,
        images: images,
        pickImage: () async => newSource.path,
      );
      await tester.enterText(name, original.name);
      await tester.tap(find.byKey(const Key('pick-option-image')));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(find.text('恢复原来的选项？'), findsOneWidget);
      await answerSaveDialog(tester, '恢复并保存');
      expect(find.byType(OptionEditor), findsNothing);
      final restored = controller.options.singleWhere(
        (option) => option.id == original.id,
      );
      expect(restored.isDeleted, isFalse);
      expect(restored.imagePath, isNot(oldOwned));
      await tester.runAsync(() async {
        expect(await File(oldOwned).exists(), isFalse);
        expect(await File(restored.imagePath!).readAsBytes(), replacementBytes);
        expect(
          await Directory(
            path.join(directory.path, 'option-images'),
          ).list().length,
          1,
        );
      });
    },
  );

  testWidgets(
    'deleted exact match requires confirmation and retains identity',
    (tester) async {
      final original = await create(tester, 'My Noodles');
      await tester.runAsync(() => controller.deleteOption(original.id));
      final selected = startRound();
      await mountEditor(tester);
      await tester.enterText(name, 'MY NOODLES');
      await tapSave(tester);
      expect(find.text('恢复原来的选项？'), findsOneWidget);
      await answerSaveDialog(tester, '取消');
      expect(
        controller.options
            .singleWhere((food) => food.id == original.id)
            .isDeleted,
        isTrue,
      );
      expect(controller.result, same(selected));
      await tapSave(tester);
      await answerSaveDialog(tester, '恢复并保存');
      final restored = controller.options.singleWhere(
        (food) => food.id == original.id,
      );
      expect(restored.isDeleted, isFalse);
      expect(restored.isActive, isTrue);
      expect(controller.options.where((food) => !food.isBuiltIn), hasLength(1));
      expect(find.byType(OptionEditor), findsNothing);
      expect(controller.hasRound, isFalse);
    },
  );

  testWidgets(
    'rename cancellation preserves identity and confirmed rename saves',
    (tester) async {
      final original = await create(tester, '番茄鸡蛋面');
      final selected = startRound();
      await mountEditor(tester, option: original);
      await tester.enterText(name, '妈妈的拿手面');
      await tapSave(tester);
      expect(find.text('还是同一种餐食吗？'), findsOneWidget);
      await answerSaveDialog(tester, '取消');
      expect(
        controller.options.singleWhere((food) => food.id == original.id).name,
        original.name,
      );
      expect(controller.result, same(selected));
      await tapSave(tester);
      await answerSaveDialog(tester, '是同一种，保存');
      expect(find.byType(OptionEditor), findsNothing);
      expect(
        controller.options.singleWhere((food) => food.id == original.id).name,
        '妈妈的拿手面',
      );
      expect(controller.hasRound, isFalse);
    },
  );

  testWidgets('built-ins expose display editing but no delete or period edit', (
    tester,
  ) async {
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项库'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-rice')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('edit-rice')));
    await tester.tap(find.byKey(const ValueKey('edit-rice')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(name).enabled, isTrue);
    expect(find.byKey(const Key('pick-option-image')), findsOneWidget);
    for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip))) {
      expect(chip.onSelected, isNull);
    }
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    expect(find.text('内置餐食的分类与餐段由系统维护。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'editor at $size keeps large-text fields and actions reachable',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final option in <FoodOption?>[null, controller.options.first]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await mountEditor(tester, option: option);
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final category = find.byType(DropdownButtonFormField<String>);
          final locked = option?.isBuiltIn ?? false;
          expect(
            tester.widget<DropdownButtonFormField<String>>(category).onChanged,
            locked ? isNull : isNotNull,
          );
          expect(tester.widget<TextFormField>(name).enabled, isTrue);
          expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
          for (final value in MealPeriod.values) {
            expect(
              tester.widget<FilterChip>(period(value)).onSelected,
              locked ? isNull : isNotNull,
            );
          }

          for (final target in [
            name,
            find.byKey(const Key('pick-option-image')),
            category,
            for (final value in MealPeriod.values) period(value),
            save,
          ]) {
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(target);
            expect(
              bounds.top,
              greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
            );
            expect(bounds.bottom, lessThanOrEqualTo(size.height));
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(target.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  testWidgets('recovered image needs consent and starts an unsaved editor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final source = File(path.join(directory.path, 'recovered.png'));
    // Recovery consent operates on the returned path. Image decoding and
    // durable ownership are covered separately with real files.

    for (final choice in ['稍后再选', '用图片新建']) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MealApp(controller: controller, recoveredImage: source.path),
      );
      await tester.pumpAndSettle();
      expect(find.text('找回了刚才选择的图片'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      if (choice == '稍后再选') {
        expect(find.byType(OptionEditor), findsNothing);
      } else {
        expect(find.byType(OptionEditor), findsOneWidget);
        expect(
          tester
              .widget<OptionEditor>(find.byType(OptionEditor))
              .initialImagePath,
          source.path,
        );
        expect(tester.widget<TextFormField>(name).controller!.text, isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();
        expect(find.byType(OptionEditor), findsNothing);
      }
      final stored = await tester.runAsync(repository.options);
      expect(stored, hasLength(seedOptions.length));
      expect(controller.options, hasLength(seedOptions.length));
      expect(controller.restartNotice, isNull);
      expect(tester.takeException(), isNull);
    }
  });
}
