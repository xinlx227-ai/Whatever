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
import 'package:whatever/data/online_recognition_transport.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/online_recognition_settings.dart';
import 'package:whatever/presentation/option_editor.dart';

class _Call {
  _Call(this.body);
  final String body;
  final reply = Completer<String?>();

  Map<String, dynamic> get input {
    final envelope = jsonDecode(body) as Map<String, dynamic>;
    final messages = envelope['messages'] as List<dynamic>;
    return jsonDecode(messages.last['content'] as String)
        as Map<String, dynamic>;
  }

  void complete({String? category, List<String> duplicates = const []}) {
    String reference(String group, String name) =>
        (input[group] as List<dynamic>).singleWhere(
              (item) => item['name'] == name,
            )['id']
            as String;
    reply.complete(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({
                'category_id': category == null
                    ? null
                    : reference('categories', category),
                'duplicate_ids': [
                  for (final name in duplicates) reference('candidates', name),
                ],
              }),
            },
          },
        ],
      }),
    );
  }
}

class _Transport implements OnlineRecognitionTransport {
  final calls = <_Call>[];
  int cancellations = 0;

  @override
  Future<String?> send(String body, String apiKey) {
    expect(apiKey, 'deterministic-fake-key');
    final call = _Call(body);
    calls.add(call);
    return call.reply.future;
  }

  @override
  void cancel() => cancellations++;
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late _Transport transport;
  final name = find.byKey(const Key('option-name'));
  final save = find.byKey(const Key('save-option'));
  final category = find.byKey(const Key('option-category'));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-online-ui-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: path.join(directory.path, 'meal.sqlite'),
    );
    transport = _Transport();
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 12, 12),
      random: Random(37),
      onlineTransportFactory: () => transport,
      onlineApiKey: 'deterministic-fake-key',
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Local asynchronous operation did not finish');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    FoodOption? option,
    bool settings = false,
    MealScenario scenario = MealScenario.eat,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [optionEditorRouteObserver],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => settings
                      ? OnlineRecognitionSettingsPage(controller: controller)
                      : OptionEditor(
                          controller: controller,
                          option: option,
                          scenario: scenario,
                        ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> enable(WidgetTester tester) async {
    expect(
      await tester.runAsync(
        () => controller.setOnlineRecognition(enabled: true, consent: true),
      ),
      isTrue,
    );
    await tester.pump();
  }

  Future<void> request(
    WidgetTester tester,
    String value, {
    int count = 1,
  }) async {
    await tester.enterText(name, value);
    await tester.pump(const Duration(milliseconds: 600));
    await waitUntil(tester, () => transport.calls.length == count);
  }

  String selectedCategory() => controller
      .categoriesFor(MealScenario.eat)
      .singleWhere(
        (value) =>
            value.id ==
            (category.evaluate().single.widget
                    as DropdownButtonFormField<String>)
                .initialValue,
      )
      .name;

  Future<void> chooseCategory(WidgetTester tester, String value) async {
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  Future<void> finishSave(WidgetTester tester) async {
    await tester.pump();
    await waitUntil(
      tester,
      () =>
          find.byType(OptionEditor).evaluate().isEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(SimpleDialog).evaluate().isNotEmpty ||
          tester.widget<FilledButton>(save).onPressed != null,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.runAsync(() => tester.tap(save));
    await finishSave(tester);
  }

  Future<void> answer(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    await waitUntil(tester, () => !controller.isBusy);
    await finishSave(tester);
  }

  Future<FoodOption> create(WidgetTester tester, String value) async {
    final result = await tester.runAsync(
      () => controller.saveOption(
        name: value,
        periods: {MealPeriod.lunch},
        allowUncertainDuplicate: true,
      ),
    );
    expect(result!.changed, isTrue);
    return result.option!;
  }

  testWidgets(
    'first uncertain name asks consent before any transmission; refusal stays local',
    (tester) async {
      await mount(tester);
      await tester.enterText(name, '星河特色餐');
      await tester.pump(const Duration(milliseconds: 599));
      expect(find.text('开启在线识别？'), findsNothing);
      expect(transport.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('开启在线识别？'), findsOneWidget);
      expect(transport.calls, isEmpty);
      await tester.runAsync(() => tester.tap(find.text('仅用本地')));
      await waitUntil(tester, () => controller.onlineSettings.consentAsked);
      await tester.pumpAndSettle();
      await tester.enterText(name, '山海特色餐');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('开启在线识别？'), findsNothing);
      expect(transport.calls, isEmpty);
      await tapSave(tester);
      expect(controller.options.any((o) => o.name == '山海特色餐'), isTrue);
      expect(controller.onlineSettings.enabled, isFalse);
    },
  );

  testWidgets(
    'first agreement sends only after consent and applies timely category',
    (tester) async {
      await mount(tester);
      await tester.enterText(name, '星河特色餐');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(transport.calls, isEmpty);
      await tester.runAsync(() => tester.tap(find.text('同意并开启')));
      await waitUntil(tester, () => transport.calls.isNotEmpty);
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      expect(selectedCategory(), '面食');
      expect(find.text('AI 自动分类，可手动修改'), findsOneWidget);
    },
  );

  testWidgets(
    'settings requires consent and persists enabled and disabled states',
    (tester) async {
      await mount(tester, settings: true);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('开启在线识别？'), findsOneWidget);
      expect(transport.calls, isEmpty);
      await tester.runAsync(() => tester.tap(find.text('同意并开启')));
      await waitUntil(tester, () => controller.onlineSettings.enabled);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.runAsync(() => tester.tap(find.byType(SwitchListTile)));
      await waitUntil(tester, () => !controller.onlineSettings.enabled);
      final stored = await tester.runAsync(
        repository.onlineRecognitionSettings,
      );
      expect(stored!.enabled, isFalse);
      expect(stored.consentGranted, isTrue);
      expect(transport.calls, isEmpty);
    },
  );

  testWidgets('manual category wins over in-flight AI and later name changes', (
    tester,
  ) async {
    await enable(tester);
    await mount(tester);
    await request(tester, '星河特色餐');
    await chooseCategory(tester, '轻食');
    transport.calls.single.complete(category: '面食');
    await tester.pump();
    expect(selectedCategory(), '轻食');
    expect(find.text('AI 自动分类，可手动修改'), findsNothing);
    await tester.enterText(name, '山海特色餐');
    await tester.pump();
    expect(selectedCategory(), '轻食');
    await tapSave(tester);
    expect(
      controller.options.singleWhere((o) => o.name == '山海特色餐').category,
      '轻食',
    );
  });

  testWidgets('definite local classification wins over online category', (
    tester,
  ) async {
    await create(tester, '银河私房餐');
    await enable(tester);
    await mount(tester);
    await request(tester, '番茄鸡蛋面');
    transport.calls.single.complete(category: '饮品');
    await tester.pump();
    expect(selectedCategory(), '面食');
    expect(find.text('AI 自动分类，可手动修改'), findsNothing);
  });

  testWidgets(
    'save during request persists immediately and late reply never rewrites it',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      await tapSave(tester);
      expect(find.byType(OptionEditor), findsNothing);
      final saved = controller.options.singleWhere((o) => o.name == '星河特色餐');
      expect(saved.category, '未分类');
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      final stored = (await tester.runAsync(
        repository.options,
      ))!.singleWhere((o) => o.id == saved.id);
      expect(stored.category, '未分类');
      expect(
        controller.options.singleWhere((o) => o.id == saved.id).category,
        '未分类',
      );
    },
  );

  testWidgets(
    'superseded name rejects prior category and accepts current category',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      await request(tester, '山海特色餐', count: 2);
      transport.calls.first.complete(category: '面食');
      await tester.pump();
      expect(selectedCategory(), '未分类');
      transport.calls.last.complete(category: '饮品');
      await tester.pump();
      await tester.pump();
      expect(selectedCategory(), '饮品');
    },
  );

  testWidgets(
    'disable while in flight rejects result and blocks future transmissions',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      await tester.runAsync(
        () => controller.setOnlineRecognition(enabled: false),
      );
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      expect(selectedCategory(), '未分类');
      await tester.enterText(name, '山海特色餐');
      await tester.pump(const Duration(seconds: 1));
      expect(transport.calls, hasLength(1));
    },
  );

  testWidgets(
    'category registry change invalidates the entire request snapshot',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      await tester.runAsync(() => controller.saveCategory(name: '我的收藏'));
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      expect(selectedCategory(), '未分类');
      expect(find.text('AI 自动分类，可手动修改'), findsNothing);
    },
  );

  testWidgets(
    'editor disposal ignores uncancellable response and keeps library unchanged',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      final count = controller.options.length;
      await tester.pumpWidget(const SizedBox.shrink());
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      expect(controller.options, hasLength(count));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timed-out response stays local and saving remains available', (
    tester,
  ) async {
    await enable(tester);
    await mount(tester);
    await request(tester, '星河特色餐');
    await tester.pump(const Duration(seconds: 3));
    transport.calls.single.complete(category: '面食');
    await tester.pump();
    expect(selectedCategory(), '未分类');
    await tapSave(tester);
    expect(
      controller.options.singleWhere((o) => o.name == '星河特色餐').category,
      '未分类',
    );
    expect(transport.calls, hasLength(1));
  });

  testWidgets(
    'address and notes changes neither transmit nor enter request payload',
    (tester) async {
      await enable(tester);
      await mount(tester, scenario: MealScenario.restaurant);
      await tester.enterText(
        find.byKey(const Key('option-address')),
        'private home address',
      );
      await tester.enterText(
        find.byKey(const Key('option-notes')),
        'private family notes',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(transport.calls, isEmpty);
      await request(tester, '山海私房馆');
      expect(
        transport.calls.single.body,
        isNot(contains('private home address')),
      );
      expect(
        transport.calls.single.body,
        isNot(contains('private family notes')),
      );
      expect(transport.calls.single.input['scenario'], 'restaurant');
      transport.calls.single.complete();
      await tester.pump();
    },
  );

  testWidgets('category popup defers first consent until it closes', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(name, '星河特色餐');
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('开启在线识别？'), findsNothing);
    expect(transport.calls, isEmpty);
    Navigator.of(tester.element(find.byType(OptionEditor))).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('开启在线识别？'), findsOneWidget);
    await answer(tester, '仅用本地');
  });

  testWidgets(
    'category popup preserves a timely category and duplicate reply',
    (tester) async {
      final existing = await create(tester, '银河私房餐');
      await enable(tester);
      await mount(tester);
      await request(tester, '山海招牌餐');
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      transport.calls.single.complete(
        category: '面食',
        duplicates: [existing.name],
      );
      await tester.pump();
      await tester.pump();
      Navigator.of(tester.element(find.byType(OptionEditor))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(selectedCategory(), '面食');
      await tapSave(tester);
      expect(find.text('可能已有相似选项'), findsOneWidget);
      await answer(tester, '返回编辑');
    },
  );

  testWidgets(
    'leaving and returning before reply still invalidates the request',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      final navigator = Navigator.of(tester.element(find.byType(OptionEditor)));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      await tester.pump();
      expect(selectedCategory(), '未分类');
    },
  );

  testWidgets(
    'immediate save after closing popup retains the timely duplicate',
    (tester) async {
      final existing = await create(tester, '银河私房餐');
      await enable(tester);
      await mount(tester);
      await request(tester, '山海招牌餐');
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      transport.calls.single.complete(duplicates: [existing.name]);
      await tester.pump();
      await tester.pump();
      Navigator.of(tester.element(find.byType(OptionEditor))).pop();
      // Invoke save before advancing the popup-result deferral timer.
      await tester.runAsync(() async {
        tester.widget<FilledButton>(save).onPressed!();
      });
      await finishSave(tester);
      expect(find.text('可能已有相似选项'), findsOneWidget);
      expect(controller.options.any((o) => o.name == '山海招牌餐'), isFalse);
      await answer(tester, '返回编辑');
    },
  );

  testWidgets('a covered editor ignores online replies until new input', (
    tester,
  ) async {
    await enable(tester);
    await mount(tester);
    await request(tester, '星河特色餐');
    final navigator = Navigator.of(tester.element(find.byType(OptionEditor)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    transport.calls.single.complete(category: '面食');
    await tester.pump();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(selectedCategory(), '未分类');
    expect(transport.calls, hasLength(1));
  });

  testWidgets(
    'successful classification saves and draws the durable new item',
    (tester) async {
      await enable(tester);
      await mount(tester);
      await request(tester, '星河特色餐');
      transport.calls.single.complete(category: '面食');
      await tester.pump();
      await tapSave(tester);
      final saved = controller.options.singleWhere((o) => o.name == '星河特色餐');
      await tester.runAsync(() async {
        for (final option
            in controller.options
                .where((o) => o.scenario == 'eat' && o.id != saved.id)
                .toList()) {
          await controller.setOptionActive(option.id, false);
        }
      });
      expect(controller.startDraw(), isTrue);
      controller.finishDraw();
      expect(controller.result!.id, saved.id);
      expect(controller.result!.category, '面食');
      expect(await tester.runAsync(controller.confirm), isTrue);
      expect(
        (await tester.runAsync(repository.history))!.single.options.single.id,
        saved.id,
      );
    },
  );

  testWidgets('returning to edit preserves timely hints for the next save', (
    tester,
  ) async {
    final existing = await create(tester, '银河私房餐');
    await enable(tester);
    await mount(tester);
    await request(tester, '山海招牌餐');
    transport.calls.single.complete(duplicates: [existing.name]);
    await tester.pump();
    await tapSave(tester);
    await answer(tester, '返回编辑');
    await tapSave(tester);
    expect(find.text('可能已有相似选项'), findsOneWidget);
    await answer(tester, '返回编辑');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tapSave(tester);
    expect(find.text('可能已有相似选项'), findsOneWidget);
    expect(transport.calls, hasLength(1));
    expect(controller.options.any((o) => o.name == '山海招牌餐'), isFalse);
    await answer(tester, '保存新项');
    expect(controller.options.any((o) => o.name == '山海招牌餐'), isTrue);
  });

  for (final useExisting in [true, false]) {
    testWidgets(
      'AI duplicate new entry explicitly ${useExisting ? 'uses existing' : 'saves new'}',
      (tester) async {
        final existing = await create(tester, '银河私房餐');
        await enable(tester);
        await mount(tester);
        await request(tester, '山海招牌餐');
        transport.calls.single.complete(duplicates: [existing.name]);
        await tester.pump();
        expect(find.text('可能已有相似选项'), findsNothing);
        await tapSave(tester);
        expect(find.text('可能已有相似选项'), findsOneWidget);
        await answer(tester, useExisting ? '使用已有' : '保存新项');
        expect(find.byType(OptionEditor), findsNothing);
        expect(controller.options.any((o) => o.name == '山海招牌餐'), !useExisting);
        expect(
          controller.options.singleWhere((o) => o.id == existing.id).name,
          existing.name,
        );
      },
    );
  }

  testWidgets(
    'multiple AI matches require explicit selection and keep the draft on cancel',
    (tester) async {
      final first = await create(tester, '银河私房餐');
      final second = await create(tester, '远山家宴');
      await enable(tester);
      await mount(tester);
      await request(tester, '山海招牌餐');
      transport.calls.single.complete(duplicates: [first.name, second.name]);
      await tester.pump();
      await tapSave(tester);
      await answer(tester, '使用已有');
      expect(find.text('选择要使用的选项'), findsOneWidget);
      expect(find.textContaining(first.name), findsOneWidget);
      expect(find.textContaining(second.name), findsOneWidget);
      await answer(tester, '取消');
      await answer(tester, '返回编辑');
      expect(tester.widget<TextFormField>(name).controller!.text, '山海招牌餐');
      expect(controller.options.any((o) => o.name == '山海招牌餐'), isFalse);
    },
  );

  testWidgets(
    'AI disabled duplicate needs explicit activation and preserves existing values',
    (tester) async {
      final existing = await create(tester, '银河私房餐');
      await tester.runAsync(
        () => controller.setOptionActive(existing.id, false),
      );
      await enable(tester);
      await mount(tester);
      await request(tester, '山海招牌餐');
      transport.calls.single.complete(
        category: '面食',
        duplicates: [existing.name],
      );
      await tester.pump();
      await tapSave(tester);
      await answer(tester, '使用已有');
      expect(find.text('启用并使用'), findsOneWidget);
      expect(
        controller.options.singleWhere((o) => o.id == existing.id).isActive,
        isFalse,
      );
      await answer(tester, '启用并使用');
      final durable = (await tester.runAsync(
        repository.options,
      ))!.singleWhere((o) => o.id == existing.id);
      expect(durable.isActive, isTrue);
      expect(durable.name, existing.name);
      expect(durable.category, existing.category);
      expect(controller.options.any((o) => o.name == '山海招牌餐'), isFalse);
    },
  );

  testWidgets(
    'AI deleted duplicate needs restoration disclosure and retains history identity',
    (tester) async {
      final existing = await create(tester, '银河私房餐');
      await tester.runAsync(() async {
        for (final option
            in controller.options
                .where((o) => o.scenario == 'eat' && o.id != existing.id)
                .toList()) {
          await controller.setOptionActive(option.id, false);
        }
        expect(controller.startDraw(), isTrue);
        controller.finishDraw();
        expect(await controller.confirm(), isTrue);
        await controller.deleteOption(existing.id);
      });
      await enable(tester);
      await mount(tester);
      await request(tester, '山海招牌餐');
      transport.calls.single.complete(
        category: '面食',
        duplicates: [existing.name],
      );
      await tester.pump();
      await tapSave(tester);
      await answer(tester, '使用已有');
      expect(find.text('恢复并使用'), findsOneWidget);
      await answer(tester, '恢复并使用');
      expect(find.textContaining('本次表单的名称、分类和餐段会覆盖'), findsOneWidget);
      expect(
        controller.options.singleWhere((o) => o.id == existing.id).isDeleted,
        isTrue,
      );
      await answer(tester, '恢复并保存');
      final restored = controller.options.singleWhere(
        (o) => o.id == existing.id,
      );
      expect(restored.isDeleted, isFalse);
      expect(restored.isActive, isTrue);
      expect(restored.name, '山海招牌餐');
      expect(restored.category, '面食');
      expect(controller.options.where((o) => !o.isBuiltIn), hasLength(1));
      expect(
        (await tester.runAsync(repository.history))!.single.options.single.id,
        existing.id,
      );
    },
  );

  testWidgets(
    'edit duplicate viewing keeps draft and explicit save updates the same identity',
    (tester) async {
      final original = await create(tester, '旧时私房餐');
      final existing = await create(tester, '银河家宴');
      await enable(tester);
      await mount(tester, option: original);
      await request(tester, '山海招牌餐');
      expect(
        (transport.calls.single.input['candidates'] as List).any(
          (o) => o['name'] == original.name,
        ),
        isFalse,
      );
      transport.calls.single.complete(
        category: '面食',
        duplicates: [existing.name],
      );
      await tester.pump();
      expect(selectedCategory(), original.category);
      await tapSave(tester);
      expect(find.text('保存新项'), findsNothing);
      await answer(tester, '查看已有项');
      expect(find.text('返回表单'), findsOneWidget);
      await answer(tester, '返回表单');
      await answer(tester, '返回编辑');
      expect(tester.widget<TextFormField>(name).controller!.text, '山海招牌餐');
      await request(tester, '山海招牌餐新版', count: 2);
      transport.calls.last.complete(duplicates: [existing.name]);
      await tester.pump();
      await tapSave(tester);
      await answer(tester, '仍然保存本条');
      expect(find.text('还是同一种餐食吗？'), findsOneWidget);
      await answer(tester, '是同一种，保存');
      expect(controller.options.where((o) => !o.isBuiltIn), hasLength(2));
      expect(
        controller.options.singleWhere((o) => o.id == original.id).name,
        '山海招牌餐新版',
      );
      expect(
        controller.options.singleWhere((o) => o.id == existing.id).name,
        existing.name,
      );
    },
  );
}
