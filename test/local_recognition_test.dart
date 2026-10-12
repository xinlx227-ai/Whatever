import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatever/domain/local_recognition.dart';
import 'package:whatever/domain/meal.dart';

const recognition = LocalRecognition();

List<MealCategory> categoriesFor(MealScenario scenario) => [
  for (var index = 0; index < scenarioCategories[scenario]!.length; index++)
    MealCategory(
      id: 'builtin-category-${scenario.name}-${scenarioCategories[scenario]![index] == '未分类' ? 'fallback' : index}',
      name: scenarioCategories[scenario]![index],
      scenario: scenario,
      isBuiltIn: true,
      isFallback: scenarioCategories[scenario]![index] == '未分类',
    ),
];

MealCategory customCategory(String id, String name, MealScenario scenario) =>
    MealCategory(
      id: id,
      name: name,
      scenario: scenario,
      isBuiltIn: false,
      isFallback: false,
    );

FoodOption option(String name, {String scenario = 'eat', String? identity}) =>
    FoodOption(
      id: 'test-option',
      name: name,
      art: 'rice',
      periods: {MealPeriod.lunch},
      scenario: scenario,
      recognitionId: identity,
    );

void main() {
  test('versioned labeled corpus reports precision and coverage denominators', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/local_recognition_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(fixture['datasetVersion'], LocalRecognition.datasetVersion);
    final cases = fixture['cases'] as List<dynamic>;
    expect(cases.length, greaterThanOrEqualTo(200));
    final expectedCounts = <NameMatch, int>{};
    final predictedCounts = <NameMatch, int>{};
    var trueConfirmed = 0;
    var falseHardBlocks = 0;
    for (final item in cases) {
      final row = item as Map<String, dynamic>;
      final expected = NameMatch.values.byName(row['expected'] as String);
      final actual = recognition.compare(
        row['a'] as String,
        row['b'] as String,
        row['scenario'] as String,
      );
      expectedCounts.update(expected, (value) => value + 1, ifAbsent: () => 1);
      predictedCounts.update(actual, (value) => value + 1, ifAbsent: () => 1);
      if (actual == NameMatch.confirmed) {
        if (expected == NameMatch.confirmed) {
          trueConfirmed++;
        } else {
          falseHardBlocks++;
        }
      }
      expect(
        actual,
        expected,
        reason: '${row['id']} ${row['group']}: ${row['a']} / ${row['b']}',
      );
    }
    expect(falseHardBlocks, 0);
    final confirmed = predictedCounts[NameMatch.confirmed] ?? 0;
    final positive = expectedCounts[NameMatch.confirmed] ?? 0;
    final semanticDecisions =
        confirmed + (predictedCounts[NameMatch.different] ?? 0);
    // This project-authored corpus is regression evidence, not field accuracy.
    // ignore: avoid_print
    print(
      'Local recognition ${LocalRecognition.datasetVersion}: '
      'confirmed precision $trueConfirmed/$confirmed; '
      'positive recall $trueConfirmed/$positive; '
      'semantic decision coverage $semanticDecisions/${cases.length}; '
      'uncertain ${predictedCounts[NameMatch.uncertain] ?? 0}/${cases.length}; '
      'unknown ${predictedCounts[NameMatch.unknown] ?? 0}/${cases.length}; '
      'false hard blocks $falseHardBlocks/${cases.length - positive}.',
    );
  });

  test('all 70 approved scenario entries have identity and seed category', () {
    expect(seedOptions.length, 70);
    expect(seedOptions.where((value) => value.scenario == 'eat').length, 32);
    expect(seedOptions.where((value) => value.scenario == 'cook').length, 26);
    expect(
      seedOptions.where((value) => value.scenario == 'restaurant').length,
      12,
    );
    for (final seed in seedOptions) {
      expect(recognition.identity(seed.name, seed.scenario), isNotNull);
      final scenario = MealScenario.fromKey(seed.scenario);
      final categories = categoriesFor(scenario);
      expect(
        recognition.inferCategoryId(seed.name, scenario, categories),
        categories.singleWhere((value) => value.name == seed.category).id,
        reason: seed.name,
      );
    }
  });

  test('known identity survives display rename and supports alias search', () {
    final identity = recognition.identity('番茄炒蛋', 'cook');
    final renamed = option('妈妈的拿手菜', scenario: 'cook', identity: identity);
    expect(
      recognition.compare('妈妈的拿手菜', '西红柿炒鸡蛋', 'cook', identityA: identity),
      NameMatch.confirmed,
    );
    expect(recognition.matchesSearch(renamed, '西红柿炒鸡蛋'), isTrue);
    expect(recognition.matchesSearch(renamed, '西红柿'), isTrue);
    expect(recognition.matchesSearch(renamed, '拿手'), isTrue);
    expect(recognition.matchesSearch(renamed, '番茄鸡蛋汤'), isFalse);
    expect(
      recognition.compare('番茄鸡蛋汤', '妈妈的拿手菜', 'cook', identityB: identity),
      NameMatch.different,
    );
  });

  test('search uses curated aliases and complete recognized variants', () {
    expect(recognition.matchesSearch(option('披萨'), '比萨'), isTrue);
    expect(recognition.matchesSearch(option('牛肉面'), '牛肉拉面'), isFalse);
    expect(recognition.matchesSearch(option('牛肉面'), '牛肉面加蛋少油'), isTrue);
    expect(recognition.matchesSearch(option('豆奶'), '豆浆'), isFalse);
    expect(
      recognition.matchesSearch(option('Soup-Bowl'), 'Soup Bowl'),
      isFalse,
    );
    expect(recognition.matchesSearch(option('未知食物'), '  '), isTrue);
  });

  test(
    'restaurant search retrieves branches without collapsing their identity',
    () {
      final east = option('肯德基（东街店）', scenario: 'restaurant');
      expect(recognition.matchesSearch(east, 'KFC'), isTrue);
      expect(recognition.matchesSearch(east, 'KFC（东街店）'), isTrue);
      expect(recognition.matchesSearch(east, '肯德基（西街店）'), isFalse);
      expect(
        recognition.compare('街角小馆（东街店）', '街角小馆（西街店）', 'restaurant'),
        NameMatch.different,
      );
      expect(
        recognition.compare('街角小馆（东街店）', '街角小館（东街店）', 'restaurant'),
        NameMatch.unknown,
      );
    },
  );

  test(
    'category inference is scenario-specific and independent of label rename',
    () {
      final categories = categoriesFor(MealScenario.eat);
      final noodleId = 'builtin-category-eat-1';
      final renamed = [
        for (final category in categories)
          if (category.id == noodleId)
            MealCategory(
              id: category.id,
              name: '面面俱到',
              scenario: category.scenario,
              isBuiltIn: true,
              isFallback: false,
            )
          else
            category,
      ];
      expect(
        recognition.inferCategoryId('西红柿鸡蛋面', MealScenario.eat, renamed),
        noodleId,
      );
      expect(
        recognition.inferCategoryId(
          '牛肉面',
          MealScenario.cook,
          categoriesFor(MealScenario.cook),
        ),
        'builtin-category-cook-5',
      );
      expect(
        recognition.inferCategoryId(
          '豆浆',
          MealScenario.cook,
          categoriesFor(MealScenario.cook),
        ),
        'builtin-category-cook-fallback',
      );
    },
  );

  test(
    'custom objective categories win only with unambiguous curated evidence',
    () {
      final categories = categoriesFor(MealScenario.cook);
      final eggCategory = customCategory(
        'custom-egg',
        '鸡蛋类',
        MealScenario.cook,
      );
      expect(
        recognition.inferCategoryId('西红柿炒蛋加肉', MealScenario.cook, [
          ...categories,
          eggCategory,
        ]),
        eggCategory.id,
      );
      expect(
        recognition.inferCategoryId('牛肉面加蛋', MealScenario.cook, [
          ...categories,
          eggCategory,
        ]),
        'builtin-category-cook-5',
        reason:
            'An optional ingredient does not change base-food classification.',
      );
      expect(
        recognition.inferCategoryId('番茄炒蛋', MealScenario.cook, [
          ...categories,
          eggCategory,
          customCategory('custom-tomato', '番茄类', MealScenario.cook),
        ]),
        'builtin-category-cook-fallback',
      );
      expect(
        recognition.inferCategoryId('秘制神仙菜', MealScenario.cook, [
          ...categories,
          customCategory('custom-subjective', '好吃的', MealScenario.cook),
        ]),
        'builtin-category-cook-fallback',
      );
      expect(
        recognition.inferCategoryId('番茄炒蛋', MealScenario.cook, [
          ...categories,
          customCategory('custom-wrong-scenario', '鸡蛋类', MealScenario.eat),
        ]),
        'builtin-category-cook-0',
      );
    },
  );

  test('long malformed modifier input abstains within a bounded duration', () {
    final names = [
      '牛肉面${List.filled(116, ',').join()}x',
      '牛肉面${List.filled(38, '少油,').join()}x',
    ];
    final timer = Stopwatch()..start();
    for (final name in names) {
      expect(name.length, lessThanOrEqualTo(120));
      expect(recognition.identity(name, 'eat'), isNull);
      expect(recognition.compare(name, '牛肉面', 'eat'), NameMatch.uncertain);
    }
    timer.stop();
    expect(timer.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('ambiguous soy wording never selects either protected identity', () {
    expect(recognition.identity('豆乳', 'eat'), isNull);
    for (final name in ['豆浆', '豆漿', '豆奶']) {
      expect(recognition.compare('豆乳', name, 'eat'), NameMatch.uncertain);
      expect(recognition.compare(name, '豆乳少糖', 'eat'), NameMatch.uncertain);
    }
    expect(recognition.compare('豆浆', '豆奶', 'eat'), NameMatch.different);
    expect(
      recognition.inferCategoryId(
        '豆乳',
        MealScenario.eat,
        categoriesFor(MealScenario.eat),
      ),
      'builtin-category-eat-fallback',
    );
  });

  test('opaque renames retain uncertain-match evidence as well as aliases', () {
    expect(
      recognition.compare(
        '妈妈餐',
        '牛肉面豪华版',
        'eat',
        identityA: recognition.identity('牛肉面', 'eat'),
      ),
      NameMatch.uncertain,
    );
    expect(
      recognition.compare(
        '牛肉面豪华版',
        '妈妈餐',
        'eat',
        identityB: recognition.identity('牛肉面', 'eat'),
      ),
      NameMatch.uncertain,
    );
    expect(
      recognition.compare(
        '早餐饮品',
        '豆乳',
        'eat',
        identityA: recognition.identity('豆浆', 'eat'),
      ),
      NameMatch.uncertain,
    );
  });

  test('bounded parser consumes all suffix text and validates scenario', () {
    expect(recognition.identity('牛肉面（少油，加蛋）', 'eat'), isNotNull);
    for (final name in [
      '牛肉面少油未知',
      '牛肉面（少油）未知',
      '牛肉面加',
      '牛肉面加香蕉',
      '牛肉面换鸡肉',
      '牛肉面（少油',
    ]) {
      expect(recognition.identity(name, 'eat'), isNull, reason: name);
    }
    expect(recognition.identity('牛肉面', 'other'), isNull);
    expect(recognition.identity('海底捞', 'eat'), isNull);
    expect(recognition.identity('牛肉面', 'restaurant'), isNull);
    expect(
      recognition.compare(
        'unknown',
        'another',
        'eat',
        identityA: 'cook:noodles',
        identityB: 'cook:noodles',
      ),
      NameMatch.unknown,
    );
  });
}
