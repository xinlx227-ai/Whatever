import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/wheel.dart';

FoodOption option(
  String id, {
  String category = '未分类',
  Set<String>? categories,
  String scenario = 'eat',
}) => FoodOption(
  id: id,
  name: '完整候选名称 $id',
  art: 'plate',
  periods: const {MealPeriod.lunch},
  scenario: scenario,
  category: category,
  categories: categories,
);

List<Object> signature(WheelLayout layout) => [
  for (final sector in layout.sectors)
    [sector.optionIds, sector.assetName, sector.isMystery],
];

void main() {
  test(
    'all candidates remain reachable exactly once under the display cap',
    () {
      for (final count in [0, 1, 2, 8, 10, 18, 36, 60, 301]) {
        final options = [
          for (var i = 0; i < count; i++)
            option('$i', category: i % 5 == 0 ? '面食' : '盖饭套餐'),
        ];
        final layout = WheelLayout.fromOptions(options);
        final represented = layout.sectors.expand((s) => s.optionIds).toList();
        expect(layout.sectors.length, lessThanOrEqualTo(18));
        expect(represented, unorderedEquals(options.map((o) => o.id)));
        expect(represented.toSet().length, count);
        for (final candidate in options) {
          final sector = layout.sectors[layout.sectorIndexFor(candidate.id)];
          expect(sector.optionIds, contains(candidate.id));
          expect(
            sector.assetName,
            candidate.category == '面食' ? 'noodle' : 'rice',
          );
        }
        expect(
          layout.sectors.where((s) => s.isMystery).length,
          count < 10 ? 0 : (layout.sectors.length / 3).round(),
        );
      }
    },
  );

  test('input order never changes grouping, positions or mystery marks', () {
    final options = [
      for (var i = 0; i < 60; i++)
        option('$i', category: i.isEven ? '面食' : '盖饭套餐'),
    ];
    final original = WheelLayout.fromOptions(options);
    expect(
      signature(WheelLayout.fromOptions(options.reversed.toList())),
      signature(original),
    );
    expect(
      signature(WheelLayout.fromOptions([...options])),
      signature(original),
    );
    final reduced = WheelLayout.fromOptions(options.sublist(1));
    expect(() => reduced.sectorIndexFor(options.first.id), throwsStateError);
    for (final remaining in options.sublist(1)) {
      expect(
        reduced.sectors[reduced.sectorIndexFor(remaining.id)].optionIds,
        contains(remaining.id),
      );
    }
  });

  test(
    'overlapping tags follow fixed priority and do not duplicate candidates',
    () {
      final layouts = [
        WheelLayout.fromOptions([
          option('overlap', category: '面食', categories: {'饮品', '盖饭套餐'}),
        ]),
        WheelLayout.fromOptions([
          option('overlap', category: '饮品', categories: {'盖饭套餐', '面食'}),
        ]),
      ];
      expect(signature(layouts[0]), signature(layouts[1]));
      expect(layouts[0].sectors.single.assetName, 'rice');
      expect(layouts[0].sectors.single.optionIds, ['overlap']);
      final restaurant = WheelLayout.fromOptions([
        option(
          'shop',
          scenario: 'restaurant',
          category: '快餐',
          categories: {'火锅'},
        ),
      ]);
      expect(restaurant.sectors.single.assetName, 'shop-hotpot');
    },
  );

  test(
    'unillustrated categories use neutral food/store clues, not mystery',
    () {
      for (final scenario in MealScenario.values) {
        final layout = WheelLayout.fromOptions([
          option('custom', scenario: scenario.name, category: '我自己的分类'),
        ]);
        expect(
          layout.sectors.single.assetName,
          scenario == MealScenario.restaurant ? 'storefront' : 'plate',
        );
        expect(layout.sectors.single.isMystery, isFalse);
      }
      final shops = WheelLayout.fromOptions([
        for (final category in scenarioCategories[MealScenario.restaurant]!)
          option(category, scenario: 'restaurant', category: category),
      ]);
      expect(
        shops.sectors.map((s) => s.assetName),
        unorderedEquals([
          'shop-hotpot',
          'shop-barbecue',
          'shop-chinese',
          'shop-western',
          'shop-fastfood',
          'shop-buffet',
          'storefront',
        ]),
      );
    },
  );

  test('ambiguous duplicate identities are rejected', () {
    expect(
      () => WheelLayout.fromOptions([option('same'), option('same')]),
      throwsArgumentError,
    );
  });

  testWidgets('only sectors rotate; the central upward pointer stays fixed', (
    tester,
  ) async {
    final options = [
      option('rice', category: '盖饭套餐'),
      option('noodles', category: '面食'),
    ];
    Future<void> show(double angle) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 320,
              child: MealWheel(options: options, angle: angle),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(0);
    final pointer = find.byKey(const ValueKey('wheel-fixed-pointer'));
    final bounds = tester.getRect(pointer);
    await show(math.pi / 2);
    expect(tester.getRect(pointer), bounds);
    expect(
      find.ancestor(of: pointer, matching: find.byType(Transform)),
      findsNothing,
    );
    final rotor = tester.widget<Transform>(
      find.byKey(const ValueKey('wheel-rotor')),
    );
    expect(rotor.transform.entry(0, 0), closeTo(0, 1e-10));
    expect(rotor.transform.entry(1, 0), closeTo(1, 1e-10));
    for (final candidate in options) {
      expect(find.text(candidate.name), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dense wheel loads illustrations on a small surface and large text',
    (tester) async {
      final options = [
        for (final scenario in MealScenario.values)
          for (final category in scenarioCategories[scenario]!)
            option(
              '${scenario.name}-$category',
              scenario: scenario.name,
              category: category,
            ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox.square(
                dimension: 180,
                child: MealWheel(options: options, angle: 0),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
