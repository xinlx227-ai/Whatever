import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/presentation/option_art.dart';

void main() {
  testWidgets('extreme photos have bounded aspect-preserving display decodes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bounded-art-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    for (final dimensions in [const Size(20, 12000), const Size(12000, 20)]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
      final picture = recorder.endRecording();
      final original = (await tester.runAsync(
        () => picture.toImage(
          dimensions.width.toInt(),
          dimensions.height.toInt(),
        ),
      ))!;
      final bytes = (await tester.runAsync(
        () => original.toByteData(format: ui.ImageByteFormat.png),
      ))!.buffer.asUint8List();
      picture.dispose();
      original.dispose();
      final file = File('${directory.path}/${dimensions.width}.png');
      await tester.runAsync(() => file.writeAsBytes(bytes));
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: OptionArt(
              option: FoodOption(
                id: 'extreme',
                name: '长图',
                art: 'plate',
                periods: {MealPeriod.lunch},
                imagePath: file.path,
              ),
              size: 48,
            ),
          ),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final stream = (await tester.runAsync(
        () async => provider.resolve(const ImageConfiguration()),
      ))!;
      ImageInfo? decoded;
      final listener = ImageStreamListener((info, _) {
        decoded = info;
      });
      stream.addListener(listener);
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (decoded == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(decoded, isNotNull);
      expect(decoded!.image.width, inInclusiveRange(1, 96));
      expect(decoded!.image.height, inInclusiveRange(1, 96));
      expect(
        decoded!.image.width > decoded!.image.height,
        dimensions.width > dimensions.height,
      );
      expect(await tester.runAsync(() => file.readAsBytes()), bytes);
      stream.removeListener(listener);
      decoded!.dispose();
    }
  });

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
