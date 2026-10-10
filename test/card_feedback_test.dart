import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/card_draw.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('card-feedback-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 10, 12),
      random: Random(43),
    );
    await controller.initialize();
    controller.changeScenario(MealScenario.cook);
    controller.changeCookingCount(3);
    await controller.updatePreferences(
      controller.preferences.copyWith(mode: DrawMode.cards),
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Finder key(String value) => find.byKey(ValueKey(value));

  ScrollController browsing(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(key('card-fan-scroll')).controller!;

  double left(WidgetTester tester, int index) =>
      tester.widget<Positioned>(key('fan-position-$index')).left!;

  double opacity(WidgetTester tester, int index) => tester
      .widget<Opacity>(
        find.descendant(
          of: key('fan-position-$index'),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  Future<void> mount(
    WidgetTester tester, {
    bool settle = true,
    bool paused = false,
    bool reducedMotion = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(430, 1000),
            disableAnimations: reducedMotion,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CardDraw(
                  controller: controller,
                  revealAnimation: const AlwaysStoppedAnimation(1),
                  onReveal: () {},
                  paused: paused,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  void revealAndCollect(int index) {
    expect(controller.selectCard(index), isTrue);
    expect(controller.startDraw(), isTrue);
    controller.finishDraw();
    expect(controller.collectCard(), isTrue);
  }

  testWidgets('initial fan starts at full-deck midpoint with both directions', (
    tester,
  ) async {
    await mount(tester);
    final scroll = browsing(tester);
    final midpoint = scroll.position.maxScrollExtent / 2;
    expect(midpoint, greaterThan(176));
    expect(scroll.offset, closeTo(midpoint, .01));
    await tester.tap(key('browse-cards-back'));
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(midpoint));
    scroll.jumpTo(midpoint);
    await tester.pump();
    await tester.tap(key('browse-cards-forward'));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(midpoint));
  });

  for (final choice in ReplacementChoice.values) {
    testWidgets('$choice reshuffle recenters after removing a result', (
      tester,
    ) async {
      await mount(tester);
      revealAndCollect(8);
      revealAndCollect(8);
      await tester.pumpAndSettle();
      final scroll = browsing(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(controller.beginReplacement(1, choice), isTrue);
      await tester.pump();
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent / 2, .01));
      expect(find.text('正在洗牌…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent / 2, .01));
      expect(controller.hasPendingReplacement, isTrue);
      expect(controller.selectedCardIndex, isNull);
      expect(controller.isDrawing, isFalse);
    });
  }

  testWidgets('ordinary next dish preserves the user browsing offset', (
    tester,
  ) async {
    await mount(tester);
    final scroll = browsing(tester);
    scroll.jumpTo(scroll.offset + 88);
    await tester.pump();
    final offset = scroll.offset;
    final revision = controller.cardDeckShuffleRevision;
    revealAndCollect(10);
    await tester.pumpAndSettle();
    expect(controller.cardDeckShuffleRevision, revision);
    expect(scroll.offset, closeTo(offset, .01));
    expect(find.text('正在洗牌…'), findsNothing);
    expect(
      scroll.offset,
      isNot(closeTo(scroll.position.maxScrollExtent / 2, 1)),
    );
  });

  testWidgets('a short deck is centered as a group without scroll', (
    tester,
  ) async {
    final excluded = controller.candidates
        .skip(3)
        .map((option) => option.id)
        .toList();
    for (final id in excluded) {
      expect(controller.excludeForSession(id), isTrue);
    }
    await mount(tester);
    expect(controller.cardDeck, hasLength(3));
    expect(browsing(tester).position.maxScrollExtent, 0);
    final viewport = tester.getSize(key('card-fan-scroll')).width;
    final groupCenter = (left(tester, 0) + left(tester, 2) + 82) / 2;
    expect(groupCenter, closeTo(viewport / 2, .01));
  });

  for (final replacement in [false, true]) {
    testWidgets(
      '${replacement ? 'replacement' : 'initial'} shuffle keeps original travel and timing without scrolling',
      (tester) async {
        await mount(tester, settle: replacement);
        if (replacement) {
          revealAndCollect(8);
          await tester.pumpAndSettle();
          expect(
            controller.beginReplacement(0, ReplacementChoice.redraw),
            isTrue,
          );
          await tester.pump();
        }
        await tester.pump();
        final scroll = browsing(tester);
        final midpoint = scroll.position.maxScrollExtent / 2;
        final duration = replacement ? 700 : 1800;
        final spreadDuration = replacement ? 0 : 576;
        await tester.pump(Duration(milliseconds: spreadDuration));
        var previousLeft = left(tester, 11);
        var distance = 0.0;
        for (var elapsed = spreadDuration; elapsed < duration - 1; elapsed++) {
          await tester.pump(const Duration(milliseconds: 1));
          final currentLeft = left(tester, 11);
          if (currentLeft > previousLeft + 100) {
            distance +=
                previousLeft - currentLeft + controller.cardDeck.length * 44;
          } else {
            expect(currentLeft, lessThanOrEqualTo(previousLeft + .001));
            distance += previousLeft - currentLeft;
          }
          previousLeft = currentLeft;
          expect(scroll.offset, closeTo(midpoint, .01));
        }
        expect(distance, closeTo(18 * 44, .02));
        expect(find.text('正在洗牌…'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('正在洗牌…'), findsNothing);
        final restingLeft = left(tester, 11);
        await tester.pump(const Duration(milliseconds: 500));
        expect(left(tester, 11), restingLeft);
        expect(scroll.offset, closeTo(midpoint, .01));
      },
    );
  }

  testWidgets('centered 14-card shuffle has no interior fade or spacing seam', (
    tester,
  ) async {
    for (final option in controller.candidates.skip(14).toList()) {
      expect(controller.excludeForSession(option.id), isTrue);
    }
    await mount(tester, settle: false);
    expect(controller.cardDeck, hasLength(14));
    await tester.pump(const Duration(milliseconds: 800));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final scroll = browsing(tester);
      final viewport = tester.getSize(key('card-fan-scroll')).width;
      final visible = List.generate(14, (index) => index).where((index) {
        final x = left(tester, index) - scroll.offset;
        return x > 30 && x + 82 < viewport - 30;
      }).toList()..sort((a, b) => left(tester, a).compareTo(left(tester, b)));
      for (final index in visible) {
        expect(opacity(tester, index), 1, reason: 'interior card $index fades');
      }
      for (var index = 1; index < visible.length; index++) {
        expect(
          left(tester, visible[index]) - left(tester, visible[index - 1]),
          closeTo(44, .01),
          reason: 'visible fan has an internal circulation seam',
        );
      }
    }
  });

  testWidgets('circulation moves left and wraps only while faded out', (
    tester,
  ) async {
    await mount(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 660));
    final before = left(tester, 11);
    await tester.pump(const Duration(milliseconds: 100));
    expect(left(tester, 11), lessThan(before));
    var sawWrap = false;
    for (var frame = 0; frame < 90 && !sawWrap; frame++) {
      final previousLeft = left(tester, 11);
      final previousOpacity = opacity(tester, 11);
      await tester.pump(const Duration(milliseconds: 10));
      if (left(tester, 11) > previousLeft + 100) {
        sawWrap = true;
        expect(previousOpacity, lessThan(.2));
        expect(opacity(tester, 11), lessThan(.2));
      }
    }
    expect(sawWrap, isTrue);
    await tester.pumpAndSettle();
    expect(opacity(tester, 11), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused and reduced-motion fans still center without advancing', (
    tester,
  ) async {
    await mount(tester, settle: false, paused: true);
    await tester.pump();
    final scroll = browsing(tester);
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent / 2, .01));
    final position = left(tester, 11);
    await tester.pump(const Duration(seconds: 3));
    expect(left(tester, 11), position);
    await mount(tester, reducedMotion: true);
    expect(find.text('正在洗牌…'), findsNothing);
    final restingPosition = left(tester, 11);
    await tester.pump(const Duration(seconds: 3));
    expect(left(tester, 11), restingPosition);
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent / 2, .01));
  });
}
