import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatever/application/online_recognition_session.dart';
import 'package:whatever/data/online_recognition_transport.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/online_recognition.dart';

class _DelayedTransport implements OnlineRecognitionTransport {
  final replies = <Completer<String?>>[];
  int cancellations = 0;

  @override
  Future<String?> send(String body, String apiKey) {
    final reply = Completer<String?>();
    replies.add(reply);
    return reply.future;
  }

  // Deliberately uncancellable: freshness must also reject completed replies.
  @override
  void cancel() => cancellations++;
}

void main() {
  final request = OnlineRecognitionRequest.build(
    name: '特色餐食',
    scenario: MealScenario.eat,
    categories: const [
      MealCategory(
        id: 'noodles',
        name: '面食',
        scenario: MealScenario.eat,
        isBuiltIn: true,
        isFallback: false,
      ),
      MealCategory(
        id: 'fallback',
        name: '未分类',
        scenario: MealScenario.eat,
        isBuiltIn: true,
        isFallback: true,
      ),
    ],
    candidates: const [],
  )!;
  final response = jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {
          'content': jsonEncode({'category_id': 'c0', 'duplicate_ids': []}),
        },
      },
    ],
  });

  testWidgets(
    'deadline includes reservation time and cannot extend after send',
    (tester) async {
      final transport = _DelayedTransport();
      final reservation = Completer<bool>();
      final session = OnlineRecognitionSession(
        transport: transport,
        apiKey: 'fake',
        reserve: () => reservation.future,
        enabled: () => true,
      );
      addTearDown(session.dispose);
      var finished = false;
      OnlineRecognitionResult? result;
      final pending = session.recognize(request).then((value) {
        result = value;
        finished = true;
      });
      await tester.pump(const Duration(seconds: 2));
      reservation.complete(true);
      await tester.pump();
      expect(transport.replies, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(finished, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await pending;
      expect(finished, isTrue);
      expect(result, isNull);
      transport.replies.single.complete(response);
      await tester.pump();
      expect(result, isNull);
    },
  );

  testWidgets('reservation completing after timeout never transmits', (
    tester,
  ) async {
    final transport = _DelayedTransport();
    final reservation = Completer<bool>();
    final session = OnlineRecognitionSession(
      transport: transport,
      apiKey: 'fake',
      reserve: () => reservation.future,
      enabled: () => true,
    );
    addTearDown(session.dispose);
    final pending = session.recognize(request);
    await tester.pump(const Duration(seconds: 3));
    expect(await pending, isNull);
    reservation.complete(true);
    await tester.pump();
    expect(transport.replies, isEmpty);
  });

  testWidgets(
    'superseding request rejects the old reply and accepts current reply',
    (tester) async {
      final transport = _DelayedTransport();
      final session = OnlineRecognitionSession(
        transport: transport,
        apiKey: 'fake',
        reserve: () async => true,
        enabled: () => true,
      );
      addTearDown(session.dispose);
      final old = session.recognize(request);
      await tester.pump();
      final current = session.recognize(request);
      await tester.pump();
      transport.replies[0].complete(response);
      await tester.pump();
      expect(await old, isNull);
      transport.replies[1].complete(response);
      await tester.pump();
      expect((await current)!.categoryId, 'noodles');
    },
  );

  for (final action in ['invalidate', 'disable', 'dispose']) {
    testWidgets('$action rejects an otherwise valid in-flight result', (
      tester,
    ) async {
      var enabled = true;
      final transport = _DelayedTransport();
      final session = OnlineRecognitionSession(
        transport: transport,
        apiKey: 'fake',
        reserve: () async => true,
        enabled: () => enabled,
      );
      addTearDown(session.dispose);
      final pending = session.recognize(request);
      await tester.pump();
      if (action == 'invalidate') session.invalidate();
      if (action == 'disable') enabled = false;
      if (action == 'dispose') session.dispose();
      transport.replies.single.complete(response);
      await tester.pump();
      expect(await pending, isNull);
    });
  }

  testWidgets('disabled, missing key and denied quota skip transport', (
    tester,
  ) async {
    for (final configuration in [
      (enabled: false, key: 'fake', reserved: true),
      (enabled: true, key: '', reserved: true),
      (enabled: true, key: 'fake', reserved: false),
    ]) {
      final transport = _DelayedTransport();
      final session = OnlineRecognitionSession(
        transport: transport,
        apiKey: configuration.key,
        reserve: () async => configuration.reserved,
        enabled: () => configuration.enabled,
      );
      final pending = session.recognize(request);
      await tester.pump();
      expect(await pending, isNull);
      expect(transport.replies, isEmpty);
      session.dispose();
    }
  });

  testWidgets('transport exceptions fall back without automatic retry', (
    tester,
  ) async {
    final transport = _DelayedTransport();
    final session = OnlineRecognitionSession(
      transport: transport,
      apiKey: 'fake',
      reserve: () async => true,
      enabled: () => true,
    );
    addTearDown(session.dispose);
    final pending = session.recognize(request);
    await tester.pump();
    transport.replies.single.completeError(StateError('offline'));
    await tester.pump();
    expect(await pending, isNull);
    await tester.pump(const Duration(seconds: 10));
    expect(transport.replies, hasLength(1));
  });
}
