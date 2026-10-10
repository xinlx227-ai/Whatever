import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/option_art.dart';

void main() {
  testWidgets('every default illustration loads without missing assets', (
    tester,
  ) async {
    final examples = <String, FoodOption>{
      for (final option in seedOptions) defaultOptionArt(option): option,
      'storefront': const FoodOption(
        id: 'personal-shop',
        name: '街角小店',
        art: 'storefront',
        scenario: 'restaurant',
        periods: {MealPeriod.lunch},
      ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final option in examples.values)
                OptionArt(option: option, size: 64),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(examples.length));
    expect(tester.takeException(), isNull);
  });

  test('renaming restaurant/category preserves its default artwork', () {
    final original = seedOptions.firstWhere(
      (o) => o.id == 'restaurant-haidilao',
    );
    final renamed = FoodOption(
      id: original.id,
      name: '新显示名',
      art: original.art,
      scenario: original.scenario,
      category: '新分类',
      periods: original.periods,
    );
    expect(defaultOptionArt(renamed), defaultOptionArt(original));
    expect(defaultOptionArt(renamed), 'shop-hotpot');
  });

  testWidgets(
    'user image takes precedence and missing file uses stable default',
    (tester) async {
      Future<void> show(String path) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OptionArt(
              option: FoodOption(
                id: 'personal',
                name: '我的菜',
                art: 'plate',
                periods: {MealPeriod.lunch},
                imagePath: path,
              ),
              size: 100,
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }

      await show(
        File(
          'docs/design/assets/card-back-celestial-black-purple-gold.png',
        ).absolute.path,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      await show(File('build/nonexistent-option-image.png').absolute.path);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
