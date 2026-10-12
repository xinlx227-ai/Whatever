import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatever/data/online_recognition_transport.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/online_recognition.dart';

MealCategory category(
  String id,
  String name, {
  MealScenario scenario = MealScenario.eat,
  bool builtIn = true,
  bool fallback = false,
}) => MealCategory(
  id: id,
  name: name,
  scenario: scenario,
  isBuiltIn: builtIn,
  isFallback: fallback,
);

FoodOption option(
  String id,
  String name, {
  String scenario = 'eat',
  bool active = true,
  bool deleted = false,
  String? recognitionId = 'private-identity',
}) => FoodOption(
  id: id,
  name: name,
  scenario: scenario,
  art: 'private-art',
  periods: {MealPeriod.lunch},
  isActive: active,
  isDeleted: deleted,
  address: 'private-address',
  notes: 'private-notes',
  imagePath: 'private-photo',
  recognitionId: recognitionId,
);

OnlineRecognitionRequest request({
  String name = '香菜牛肉面',
  MealScenario scenario = MealScenario.eat,
  List<MealCategory>? categories,
  List<FoodOption> candidates = const [],
  String? excludeOptionId,
}) => OnlineRecognitionRequest.build(
  name: name,
  scenario: scenario,
  categories:
      categories ??
      [
        category('private-category', '面食'),
        category('fallback', '未分类', fallback: true),
      ],
  candidates: candidates,
  excludeOptionId: excludeOptionId,
)!;

Map<String, dynamic> userPayload(OnlineRecognitionRequest request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  return jsonDecode(body['messages'][1]['content'] as String)
      as Map<String, dynamic>;
}

String reply(
  Object? categoryRef,
  List<Object?> duplicateRefs, {
  String finish = 'stop',
}) => jsonEncode({
  'choices': [
    {
      'finish_reason': finish,
      'message': {
        'role': 'assistant',
        'content': jsonEncode({
          'category_id': categoryRef,
          'duplicate_ids': duplicateRefs,
        }),
      },
    },
  ],
});

void main() {
  group('minimal request and bounded shortlist', () {
    test(
      'sends only approved names and opaque references from this scenario',
      () {
        final built = request(
          categories: [
            category('private-category', '面食'),
            category('foreign-category', '汤羹', scenario: MealScenario.cook),
          ],
          candidates: [
            option('private-option', '香菜牛肉面'),
            option('foreign-option', '不能发送', scenario: 'cook'),
            option('self', '不能发送本人'),
          ],
          excludeOptionId: 'self',
        );
        final payload = userPayload(built);
        expect(
          payload.keys,
          unorderedEquals(['name', 'scenario', 'categories', 'candidates']),
        );
        expect(payload['scenario'], 'eat');
        expect(payload['categories'], [
          {'id': 'c0', 'name': '面食'},
        ]);
        expect(payload['candidates'], [
          {'id': 'o0', 'name': '香菜牛肉面'},
        ]);
        for (final private in [
          'private-category',
          'private-option',
          'private-art',
          'private-address',
          'private-notes',
          'private-photo',
          'private-identity',
          'foreign-option',
          'foreign-category',
          '不能发送',
        ]) {
          expect(built.body, isNot(contains(private)));
        }
        expect(built.categories['c0']!.id, 'private-category');
        expect(built.candidates['o0']!.id, 'private-option');
        expect(() => built.candidates.clear(), throwsUnsupportedError);
      },
    );

    test('includes zero, fewer than 80 and exactly at most 80 candidates', () {
      for (final count in [0, 4, 80, 95]) {
        final built = request(
          candidates: [for (var i = 0; i < count; i++) option('id-$i', '食物$i')],
        );
        expect(built.candidates.length, count > 80 ? 80 : count);
        expect(utf8.encode(built.body).length, lessThanOrEqualTo(16384));
      }
    });

    test(
      'retains inactive and deleted candidates and excludes repeated IDs',
      () {
        final built = request(
          candidates: [
            option('inactive', '凉面', active: false),
            option('deleted', '炒面', deleted: true),
            option('deleted', 'duplicate-row'),
          ],
        );
        expect(
          built.candidates.values.map((value) => value.id),
          unorderedEquals(['inactive', 'deleted']),
        );
      },
    );

    test(
      'ranking favors seller-independent dish and is independent of input order',
      () {
        final candidates = [
          option('z', '张记的韭菜炒虾仁'),
          option('a', '黑椒鸡肉炒饭'),
          option('b', '虾仁炒韭菜'),
          option('c', '南瓜粥'),
        ];
        final first = request(
          name: '李记的韭菜炒虾仁',
          scenario: MealScenario.eat,
          candidates: candidates,
        );
        final second = request(
          name: '李记的韭菜炒虾仁',
          candidates: candidates.reversed.toList(),
        );
        expect(first.candidates.values.first.id, 'z');
        expect(first.body, second.body);
      },
    );

    test(
      'stable tie ordering and repeated builds produce identical payloads',
      () {
        final candidates = [option('z', '未知乙'), option('a', '未知乙')];
        final built = request(name: '陌生名字', candidates: candidates);
        expect(built.candidates.values.map((value) => value.id), ['a', 'z']);
        expect(
          built.body,
          request(name: '陌生名字', candidates: candidates.reversed.toList()).body,
        );
      },
    );

    test(
      'complete ASCII body accepts exactly 16384 bytes and rejects the next byte',
      () {
        final base = request(name: 'x', categories: const []);
        final nameLength =
            OnlineRecognitionRequest.maxBytes -
            utf8.encode(base.body).length +
            1;
        final exact = request(
          name: List.filled(nameLength, 'x').join(),
          categories: const [],
        );
        expect(utf8.encode(exact.body).length, 16384);
        expect(
          OnlineRecognitionRequest.build(
            name: '${exact.name}x',
            scenario: MealScenario.eat,
            categories: const [],
            candidates: const [],
          ),
          isNull,
        );
      },
    );

    test(
      'measures UTF8 plus escaped JSON and removes whole lowest-ranked names',
      () {
        final candidates = [
          option('best', '香菜牛肉面'),
          for (var i = 0; i < 12; i++)
            option('tail-$i', '${List.filled(650, '汉😀"\\\n').join()}$i'),
        ];
        final built = request(candidates: candidates);
        final names = (userPayload(built)['candidates'] as List).map(
          (value) => value['name'],
        );
        expect(built.candidates.length, lessThan(candidates.length));
        expect(built.candidates.values.first.id, 'best');
        expect(names, built.candidates.values.map((value) => value.name));
        expect(utf8.encode(built.body).length, lessThanOrEqualTo(16384));
        expect(
          built.body,
          request(candidates: candidates.reversed.toList()).body,
        );
      },
    );

    test(
      'tail reduction can reach zero without truncating query or categories',
      () {
        final huge = option('huge', List.filled(12000, '长').join());
        final built = request(candidates: [huge]);
        expect(built.candidates, isEmpty);
        expect(userPayload(built)['name'], built.name);
        expect(userPayload(built)['categories'], [
          {'id': 'c0', 'name': '面食'},
          {'id': 'c1', 'name': '未分类'},
        ]);
      },
    );

    test(
      'oversized categories and empty query fall back without a request',
      () {
        expect(
          OnlineRecognitionRequest.build(
            name: '牛肉面',
            scenario: MealScenario.eat,
            categories: [category('large', List.filled(6000, '长').join())],
            candidates: const [],
          ),
          isNull,
        );
        expect(
          OnlineRecognitionRequest.build(
            name: '   ',
            scenario: MealScenario.eat,
            categories: const [],
            candidates: const [],
          ),
          isNull,
        );
      },
    );
  });

  group('validated advisory response', () {
    test('maps only snapshot references to local IDs', () {
      final built = request(candidates: [option('local-option', '香菜牛肉面')]);
      final parsed = built.parse(reply('c0', ['o0']))!;
      expect(parsed.categoryId, 'private-category');
      expect(parsed.duplicateIds, ['local-option']);
      expect(() => parsed.duplicateIds.clear(), throwsUnsupportedError);
    });

    test(
      'rejects unknown, local, malformed, repeated and wrong-typed references',
      () {
        final built = request(candidates: [option('local-option', '香菜牛肉面')]);
        for (final raw in [
          reply('unknown', []),
          reply('private-category', []),
          reply(null, ['local-option']),
          reply(null, ['o99']),
          reply(null, [1]),
          reply(1, []),
          reply(null, ['o0', 'o0']),
          reply(null, [], finish: 'length'),
          'not-json',
          '{}',
          jsonEncode({'choices': []}),
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content':
                      '{"category_id":null,"duplicate_ids":[],"extra":1}',
                },
              },
            ],
          }),
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': '{"category_id":null,"duplicate_ids":null}',
                },
              },
            ],
          }),
        ]) {
          expect(built.parse(raw), isNull, reason: raw);
        }
      },
    );

    test(
      'fallback and subjective category replies abstain without discarding duplicates',
      () {
        final built = request(
          name: '陌生汤',
          scenario: MealScenario.cook,
          categories: [
            category('subjective', '快手菜', scenario: MealScenario.cook),
            category(
              'fallback',
              '未分类',
              scenario: MealScenario.cook,
              fallback: true,
            ),
          ],
          candidates: [option('same', '陌生汤', scenario: 'cook')],
        );
        for (final ref in ['c0', 'c1']) {
          final result = built.parse(reply(ref, ['o0']))!;
          expect(result.categoryId, isNull);
          expect(result.duplicateIds, ['same']);
        }
      },
    );

    test(
      'unknown custom labels cannot become automatic personal categories',
      () {
        for (final label in ['最爱', '便宜', '妈妈拿手菜', '常吃', '近', '轻松做', '神秘类']) {
          final built = request(
            name: '虾仁炒韭菜',
            categories: [category('custom', label, builtIn: false)],
          );
          expect(
            built.parse(reply('c0', []))!.categoryId,
            isNull,
            reason: label,
          );
        }
      },
    );

    test(
      'stable built-in category IDs remain eligible after label renames',
      () {
        final built = request(
          categories: [category('builtin-category-eat-1', '自定义显示名称')],
        );
        expect(
          built.parse(reply('c0', []))!.categoryId,
          'builtin-category-eat-1',
        );
        final subjective = request(
          scenario: MealScenario.cook,
          categories: [
            category(
              'builtin-category-cook-1',
              '改名后的快手分类',
              scenario: MealScenario.cook,
            ),
          ],
        );
        expect(subjective.parse(reply('c0', []))!.categoryId, isNull);
      },
    );

    test(
      'objective custom evidence takes priority and multiple matches abstain',
      () {
        final built = request(
          name: '笋片炒牛肉',
          categories: [
            category('noodles', '面食'),
            category('beef', '牛肉类', builtIn: false),
          ],
        );
        expect(built.parse(reply('c1', []))!.categoryId, 'beef');
        expect(built.parse(reply('c0', []))!.categoryId, isNull);
        final ambiguous = request(
          name: '番茄炒鸡蛋',
          categories: [
            category('tomato', '番茄类', builtIn: false),
            category('egg', '蛋类', builtIn: false),
          ],
        );
        expect(ambiguous.parse(reply('c0', []))!.categoryId, isNull);
        final competing = request(
          name: '笋片炒牛肉',
          categories: [
            category('beef', '牛肉类', builtIn: false),
            category('shoot', '笋类', builtIn: false),
          ],
        );
        expect(competing.parse(reply('c0', []))!.categoryId, isNull);
      },
    );

    test(
      'local principal ingredient and food form differences veto model hints',
      () {
        final built = request(
          name: '番茄炒蛋',
          scenario: MealScenario.cook,
          candidates: [
            option('soup', '番茄鸡蛋汤', scenario: 'cook'),
            option('noodles', '番茄鸡蛋面', scenario: 'cook'),
            option('pepper', '青椒炒蛋', scenario: 'cook'),
            option('same', '西红柿炒鸡蛋', scenario: 'cook'),
          ],
        );
        final result = built.parse(
          reply(null, built.candidates.keys.toList()),
        )!;
        expect(result.duplicateIds, ['same']);
        final milk = request(name: '豆浆', candidates: [option('milk', '豆奶')]);
        expect(milk.parse(reply(null, ['o0']))!.duplicateIds, isEmpty);
        final wontons = request(
          name: '馄饨',
          candidates: [option('noodles', '馄饨面')],
        );
        expect(wontons.parse(reply(null, ['o0']))!.duplicateIds, isEmpty);
        final preparation = request(
          name: '番茄炒蛋',
          scenario: MealScenario.cook,
          candidates: [option('steamed', '蒸蛋羹', scenario: 'cook')],
        );
        expect(preparation.parse(reply(null, ['o0']))!.duplicateIds, isEmpty);
      },
    );

    test(
      'unknown reversed dishes and different sellers remain advisory candidates',
      () {
        final built = request(
          name: '张记的韭菜炒虾仁',
          candidates: [
            option('a', '李记的虾仁炒韭菜'),
            option('b', '虾仁炒韭菜', active: false),
            option('c', '韭菜炒虾仁', deleted: true),
          ],
        );
        expect(
          built
              .parse(reply(null, built.candidates.keys.toList()))!
              .duplicateIds,
          unorderedEquals(['a', 'b', 'c']),
        );
      },
    );

    test('restaurant branch contrasts and brand-only ambiguity veto hints', () {
      final built = request(
        name: '古茗（人民路店）',
        scenario: MealScenario.restaurant,
        candidates: [
          option('same', '古茗 (人民路店)', scenario: 'restaurant'),
          option('different', '古茗（茶山店）', scenario: 'restaurant'),
          option('brand', '古茗', scenario: 'restaurant'),
        ],
      );
      expect(
        built.parse(reply(null, built.candidates.keys.toList()))!.duplicateIds,
        ['same'],
      );
      final brandOnly = request(
        name: '古茗',
        scenario: MealScenario.restaurant,
        candidates: [option('branch', '古茗（人民路店）', scenario: 'restaurant')],
      );
      expect(brandOnly.parse(reply(null, ['o0']))!.duplicateIds, isEmpty);
    });

    test(
      'null and empty results are valid abstentions, not uniqueness proofs',
      () {
        final result = request().parse(reply(null, []))!;
        expect(result.categoryId, isNull);
        expect(result.duplicateIds, isEmpty);
      },
    );

    test('unknown brand spelling changes in the same branch stay advisory', () {
      final built = request(
        name: '街角小館（东街店）',
        scenario: MealScenario.restaurant,
        candidates: [option('existing', '街角小馆（东街店）', scenario: 'restaurant')],
      );
      expect(built.parse(reply(null, ['o0']))!.duplicateIds, ['existing']);
    });

    test('branch spelling corrections retain provider advisory hints', () {
      for (final names in [
        ('街角小馆（东街店）', '街角小馆（東街店）'),
        ('街角小馆（冬街店）', '街角小馆（东街店）'),
        ('街角小馆（莘莊店）', '街角小馆（莘庄店）'),
        ('肯德基（东街店）', 'KFC（東街店）'),
        ('肯德基（莘莊店）', '肯德基（莘庄店）'),
      ]) {
        final built = request(
          name: names.$2,
          scenario: MealScenario.restaurant,
          candidates: [option('existing', names.$1, scenario: 'restaurant')],
        );
        expect(built.parse(reply(null, ['o0']))!.duplicateIds, [
          'existing',
        ], reason: '${names.$1} / ${names.$2}');
      }
    });

    test('retained unknown branch spelling cannot hide a current conflict', () {
      final candidate = option(
        'existing',
        '肯德基（东街店）',
        scenario: 'restaurant',
        recognitionId: 'restaurant:restaurant-kfc#branch:冬街店',
      );
      final corrected = request(
        name: 'KFC（東街店）',
        scenario: MealScenario.restaurant,
        candidates: [candidate],
      );
      expect(corrected.parse(reply(null, ['o0']))!.duplicateIds, ['existing']);
      final different = request(
        name: '肯德基（西街店）',
        scenario: MealScenario.restaurant,
        candidates: [candidate],
      );
      expect(different.parse(reply(null, ['o0']))!.duplicateIds, isEmpty);
    });
  });

  group('HTTP transport using controlled endpoints', () {
    HttpServer? server;
    HttpOnlineRecognitionTransport? transport;

    Future<HttpOnlineRecognitionTransport> serve(
      Future<void> Function(HttpRequest) handler,
    ) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((incoming) {
        unawaited(handler(incoming));
      });
      return transport = HttpOnlineRecognitionTransport(
        endpoint: Uri.parse('http://127.0.0.1:${server!.port}/recognize'),
      );
    }

    tearDown(() async {
      transport?.cancel();
      await server?.close(force: true);
    });

    test('uses Xiaomi endpoint by default', () {
      expect(
        HttpOnlineRecognitionTransport().endpoint.toString(),
        'https://api.xiaomimimo.com/v1/chat/completions',
      );
    });

    test(
      'posts minimal UTF8 body with api-key and returns complete reply',
      () async {
        final built = request();
        final expected = reply(null, []);
        final http = await serve((incoming) async {
          expect(incoming.method, 'POST');
          expect(incoming.headers.value('api-key'), 'fake-key');
          expect(incoming.headers.contentType!.mimeType, 'application/json');
          expect(await utf8.decoder.bind(incoming).join(), built.body);
          incoming.response.write(expected);
          await incoming.response.close();
        });
        expect(await http.send(built.body, 'fake-key'), expected);
      },
    );

    test('401, 429 and 5xx fall back with no retry', () async {
      var requests = 0;
      final statuses = [401, 429, 503];
      final http = await serve((incoming) async {
        await incoming.drain<void>();
        incoming.response.statusCode = statuses[requests++];
        await incoming.response.close();
      });
      for (final _ in statuses) {
        expect(await http.send(request().body, 'fake-key'), isNull);
      }
      expect(requests, 3);
    });

    test('redirect is not followed with the bundled credential', () async {
      var calls = 0;
      final http = await serve((incoming) async {
        calls++;
        await incoming.drain<void>();
        incoming.response.statusCode = 302;
        incoming.response.headers.set(
          'location',
          'http://127.0.0.1:${server!.port}/elsewhere',
        );
        await incoming.response.close();
      });
      expect(await http.send(request().body, 'fake-key'), isNull);
      expect(calls, 1);
    });

    test('oversized streamed response and invalid UTF8 fall back', () async {
      var calls = 0;
      final http = await serve((incoming) async {
        await incoming.drain<void>();
        incoming.response.add(calls++ == 0 ? List.filled(65537, 97) : [0xff]);
        await incoming.response.close();
      });
      expect(await http.send(request().body, 'fake-key'), isNull);
      expect(await http.send(request().body, 'fake-key'), isNull);
    });

    test(
      'cancel settles immediately while awaiting headers, and reuse works',
      () async {
        final entered = Completer<void>();
        var calls = 0;
        final http = await serve((incoming) async {
          await incoming.drain<void>();
          if (calls++ == 0) {
            entered.complete();
            return;
          }
          incoming.response.write('fresh');
          await incoming.response.close();
        });
        final pending = http.send(request().body, 'fake-key');
        await entered.future;
        http.cancel();
        expect(await pending, isNull);
        expect(await http.send(request().body, 'fake-key'), 'fresh');
      },
    );

    test(
      'deadline includes response streaming, not just connection inactivity',
      () async {
        final http = await serve((incoming) async {
          await incoming.drain<void>();
          incoming.response.write('incomplete');
          await incoming.response.flush();
        });
        final watch = Stopwatch()..start();
        expect(await http.send(request().body, 'fake-key'), isNull);
        expect(watch.elapsedMilliseconds, inInclusiveRange(2800, 4500));
      },
    );

    test(
      'cancel closes a client even while connection establishment is pending',
      () async {
        final client = PendingConnectionClient();
        final http = transport = HttpOnlineRecognitionTransport(
          clientFactory: () => client,
        );
        final pending = http.send(request().body, 'fake-key');
        http.cancel();
        expect(await pending, isNull);
        expect(client.closedForcefully, isTrue);
        client.connection.completeError(
          const SocketException('controlled cancellation'),
        );
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('deadline also settles and closes a pending connection', () async {
      final client = PendingConnectionClient();
      final http = transport = HttpOnlineRecognitionTransport(
        clientFactory: () => client,
      );
      expect(await http.send(request().body, 'fake-key'), isNull);
      expect(client.closedForcefully, isTrue);
      client.connection.completeError(
        const SocketException('controlled timeout'),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'empty credentials and oversized body never create a client',
      () async {
        var creations = 0;
        final http = transport = HttpOnlineRecognitionTransport(
          clientFactory: () {
            creations++;
            return HttpClient();
          },
        );
        expect(await http.send(request().body, ''), isNull);
        expect(
          await http.send(List.filled(16385, 'x').join(), 'fake-key'),
          isNull,
        );
        expect(creations, 0);
      },
    );

    test('offline connection failure falls back', () async {
      final unused = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = unused.port;
      await unused.close(force: true);
      final http = transport = HttpOnlineRecognitionTransport(
        endpoint: Uri.parse('http://127.0.0.1:$port'),
      );
      expect(await http.send(request().body, 'fake-key'), isNull);
    });
  });
}

class PendingConnectionClient implements HttpClient {
  final connection = Completer<HttpClientRequest>();
  bool closedForcefully = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) => connection.future;

  @override
  void close({bool force = false}) {
    closedForcefully = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
