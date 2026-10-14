import 'dart:io';
import 'dart:math';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/card_draw.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  Finder key(String value) => find.byKey(ValueKey(value));
  ScrollController browsing(WidgetTester tester) =>
      tester.widget<ListView>(key('card-fan-scroll')).controller!;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('card-virtualization-');
    final databasePath = '${directory.path}/meal.sqlite';
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    await database.transaction((transaction) async {
      await transaction.update('options', {'is_active': 0});
      final batch = transaction.batch();
      for (var index = 0; index < 1000; index++) {
        batch.insert('options', {
          'id': 'large-$index',
          'name': '家里慢慢炖的番茄土豆胡萝卜牛肉完整名称 $index',
          'art': 'plate',
          'scenario': 'cook',
          'category': '未分类',
          'is_builtin': 0,
          'is_active': 1,
          'is_deleted': 0,
        });
        batch.insert('option_periods', {
          'option_id': 'large-$index',
          'period': 'lunch',
        });
        batch.insert('option_categories', {
          'option_id': 'large-$index',
          'category': '未分类',
        });
      }
      await batch.commit(noResult: true);
    });
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 13, 12),
      random: Random(43),
    );
    await controller.initialize();
    controller.changeScenario(MealScenario.cook);
    controller.changeCookingCount(10);
    await controller.updatePreferences(
      controller.preferences.copyWith(mode: DrawMode.cards),
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 1000),
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CardDraw(
                  controller: controller,
                  revealAnimation: const AlwaysStoppedAnimation(1),
                  onReveal: () {
                    if (controller.startDraw()) controller.finishDraw();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<SemanticsNode> descendants(SemanticsNode node) sync* {
    yield node;
    final children = <SemanticsNode>[];
    node.visitChildren((child) {
      children.add(child);
      return true;
    });
    for (final child in children) {
      yield* descendants(child);
    }
  }

  testWidgets(
    '1000 hidden slots are lazy and sequential semantic focus never selects',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      final scroll = browsing(tester);
      expect(controller.cardDeck, hasLength(1000));
      final ids = controller.cardDeck.map((option) => option.id).toList();
      expect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is InkWell &&
                  widget.key.toString().contains('candidate-card-'),
            )
            .evaluate()
            .length,
        lessThan(20),
      );
      expect(key('candidate-card-0'), findsNothing);
      scroll.jumpTo(0);
      await tester.pump();
      for (var index = 0; index < 1000; index++) {
        // Simulate sequential traversal using platform scrolling at each visible
        // boundary. Cached offstage children are not promised as accessible nodes.
        if (key('card-semantics-$index').evaluate().isEmpty) {
          final root = tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!;
          final scrollNode = descendants(root).singleWhere(
            (node) =>
                node.getSemanticsData().scrollChildCount == 1000 &&
                node.getSemanticsData().hasAction(SemanticsAction.scrollLeft),
          );
          scrollNode.owner!.performAction(
            scrollNode.id,
            SemanticsAction.scrollLeft,
          );
          await tester.pumpAndSettle();
        }
        expect(
          key('card-semantics-$index'),
          findsOneWidget,
          reason: 'logical index $index at scroll offset ${scroll.offset}',
        );
        final node = tester.getSemantics(key('card-semantics-$index'));
        expect(node.label, '第 ${index + 1} 张牌，共 1000 张');
        expect(node.label, isNot(contains(controller.cardDeck[index].name)));
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.didGainAccessibilityFocus,
        );
        await tester.pump();
        expect(controller.selectedCardIndex, isNull);
      }
      final last = tester.getSemantics(key('card-semantics-999'));
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        last.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(controller.selectedCardIndex, 999);
      expect(controller.results, isEmpty);
      final selectedId = controller.selectedCard!.id;
      scroll.jumpTo(0);
      await tester.pump();
      expect(key('candidate-card-999'), findsNothing);
      expect(controller.selectedCard!.id, selectedId);
      expect(controller.cardDeck.map((option) => option.id), ids);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(
        tester
            .getSemantics(key('card-semantics-999'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      final events = <Object?>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            events.add(message);
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        tester.getSemantics(key('card-semantics-999')).id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(controller.results.single.id, selectedId);
      expect(
        events.whereType<Map>().where((event) => event['type'] == 'focus'),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'system semantic scrolling exposes every slot without activating a card',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      final scroll = browsing(tester)..jumpTo(0);
      await tester.pump();
      final visited = <int>{};
      while (true) {
        final root = tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!;
        final nodes = descendants(root).toList();
        for (final node in nodes) {
          final match = RegExp(r'^第 (\d+) 张牌，共 1000 张$').firstMatch(node.label);
          if (match != null) visited.add(int.parse(match[1]!) - 1);
        }
        if (scroll.offset >= scroll.position.maxScrollExtent) break;
        final scrollNode = nodes.singleWhere(
          (node) =>
              node.getSemanticsData().hasAction(SemanticsAction.scrollLeft),
        );
        final previous = scroll.offset;
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          scrollNode.id,
          SemanticsAction.scrollLeft,
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(previous));
        expect(controller.selectedCardIndex, isNull);
      }
      expect(visited, containsAll(List.generate(1000, (index) => index)));
      expect(controller.results, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'real overlap coordinates scroll without selecting or revealing',
    (tester) async {
      await mount(tester);
      final scroll = browsing(tester);
      scroll.jumpTo(0);
      await tester.pump();
      final fan = tester.getRect(key('card-fan-scroll'));
      final point = Offset(fan.left + 20 + 48 * 2 + 24, fan.top + 70);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(controller.selectedCardIndex, 2);
      final selected = controller.selectedCard!.id;
      final before = scroll.offset;
      // The right edge of the raised 82dp face overlaps the next 48dp slot.
      // It must reveal the chosen card on tap, while still accepting a drag.
      final selectedRightEdge = Offset(
        fan.left + 20 + 48 * 2 + 65,
        fan.top + 70,
      );
      final gesture = await tester.startGesture(selectedRightEdge);
      await gesture.moveBy(const Offset(-24, 0));
      await gesture.moveBy(const Offset(-176, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(before));
      expect(controller.selectedCard!.id, selected);
      expect(controller.results, isEmpty);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.tapAt(selectedRightEdge);
      await tester.pumpAndSettle();
      expect(controller.results.single.id, selected);
      await tester.tap(key('collect-central-card'));
      await tester.pumpAndSettle();
      expect(controller.collectedResults, hasLength(1));
      await tester.tapAt(tester.getCenter(key('card-center-blank')));
      await tester.pump();
      expect(controller.results, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets(
      'ten collected full names and reopen actions at $size and 2x text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(MealApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        await tester.tap(key('primary-action'));
        await tester.pumpAndSettle();
        for (var index = 0; index < 10; index++) {
          expect(controller.selectCard(0), isTrue);
          expect(controller.startDraw(), isTrue);
          controller.finishDraw();
          expect(controller.collectCard(), isTrue);
        }
        await tester.pumpAndSettle();
        for (var index = 0; index < 10; index++) {
          final target = key('collected-card-$index');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          final text = find.descendant(
            of: target,
            matching: find.text(controller.results[index].name),
          );
          expect(text, findsOneWidget);
          final widget = tester.widget<Text>(text);
          expect(widget.maxLines, isNull);
          expect(widget.overflow, isNot(TextOverflow.ellipsis));
          final node = tester.getSemantics(target);
          expect(node.label, controller.results[index].name);
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(controller.focusedResultIndex, index);
          expect(
            tester.getSemantics(target).flagsCollection.isSelected,
            Tristate.isTrue,
          );
          await tester.ensureVisible(key('replace-result-$index'));
          await tester.pumpAndSettle();
          expect(key('replace-result-$index').hitTestable(), findsOneWidget);
        }
        await tester.ensureVisible(key('primary-action'));
        await tester.pumpAndSettle();
        expect(key('primary-action').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
