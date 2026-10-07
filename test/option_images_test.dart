import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/data/option_images.dart';
import 'package:whatever/domain/meal.dart';

void main() {
  sqfliteFfiInit();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/jPwPAfAAUAAf+mXJtdAAAAAElFTkSuQmCC',
  );
  late Directory directory;
  late MealRepository repository;
  late MealController controller;
  late OptionImages images;

  Future<void> open() async {
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
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatever-images-');
    images = OptionImages(directory: () async => directory);
    await open();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'owned image and history survive picker source removal and reopen',
    (tester) async {
      await tester.runAsync(() async {
        final source = File(path.join(directory.path, 'picker.png'));
        await source.writeAsBytes(png);
        final owned = await images.persist(source.path);
        expect(
          path.isWithin(path.join(directory.path, 'option-images'), owned),
          isTrue,
        );
        expect(owned, isNot(source.path));
        final saved = await controller.saveOption(
          name: '番茄鸡蛋面',
          periods: {MealPeriod.lunch},
          imagePath: owned,
        );
        expect(saved.changed, isTrue);
        final id = saved.option!.id;
        for (final food
            in controller.options.where((food) => food.id != id).toList()) {
          await controller.setOptionActive(food.id, false);
        }
        expect(controller.startDraw(), isTrue);
        controller.finishDraw();
        expect(controller.result!.id, id);
        expect(await controller.confirm(), isTrue);
        await controller.deleteOption(id);
        await source.delete();
        controller.dispose();
        await repository.close();
        await open();
        final stored = controller.options.singleWhere((food) => food.id == id);
        expect(stored.isDeleted, isTrue);
        expect(stored.imagePath, owned);
        expect(controller.history.single.option.id, id);
        expect(controller.history.single.option.imagePath, owned);
        expect(await File(owned).readAsBytes(), png);
        expect(await source.exists(), isFalse);
      });
    },
  );

  testWidgets('same image bytes reuse ownership and keep no-op round intact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = File(path.join(directory.path, 'picker.png'));
      await source.writeAsBytes(png);
      final owned = await images.persist(source.path);
      final saved = await controller.saveOption(
        name: '番茄鸡蛋面',
        periods: {MealPeriod.lunch},
        imagePath: owned,
      );
      final option = saved.option!;
      expect(controller.startDraw(), isTrue);
      controller.finishDraw();
      final selected = controller.result;
      final replacement = File(path.join(directory.path, 'second-picker.png'));
      await replacement.writeAsBytes(png);
      final sameImage = await images.persist(
        replacement.path,
        existingPath: owned,
      );
      final result = await controller.saveOption(
        id: option.id,
        name: option.name,
        periods: option.periods,
        imagePath: sameImage,
      );
      expect(sameImage, owned);
      expect(result.status, OptionMutationStatus.unchanged);
      expect(controller.result, same(selected));
      expect(controller.restartNotice, isNull);
      expect(
        await Directory(
          path.join(directory.path, 'option-images'),
        ).list().length,
        1,
      );
    });
  });

  testWidgets('undecodable image is rejected before changing owned data', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = File(path.join(directory.path, 'picker.png'));
      await source.writeAsBytes(png);
      final owned = await images.persist(source.path);
      final saved = await controller.saveOption(
        name: '番茄鸡蛋面',
        periods: {MealPeriod.lunch},
        imagePath: owned,
      );
      expect(controller.startDraw(), isTrue);
      controller.finishDraw();
      final selected = controller.result;
      final invalid = File(path.join(directory.path, 'not-an-image.txt'));
      await invalid.writeAsString('These bytes are not an image.');
      await expectLater(
        images.persist(invalid.path, existingPath: owned),
        throwsA(anything),
      );
      final stored = (await repository.options()).singleWhere(
        (food) => food.id == saved.option!.id,
      );
      expect(stored.imagePath, owned);
      expect(stored.name, saved.option!.name);
      expect(await File(owned).readAsBytes(), png);
      expect(controller.result, same(selected));
      expect(controller.restartNotice, isNull);
      expect(
        await Directory(
          path.join(directory.path, 'option-images'),
        ).list().length,
        1,
      );
    });
  });

  testWidgets(
    'cleanup removes canceled owned copies and retains deleted backing images',
    (tester) async {
      await tester.runAsync(() async {
        final source = File(path.join(directory.path, 'picker.png'));
        await source.writeAsBytes(png);
        final retained = await images.persist(source.path);
        final saved = await controller.saveOption(
          name: '保留图片的餐食',
          periods: {MealPeriod.lunch},
          imagePath: retained,
        );
        await controller.deleteOption(saved.option!.id);
        final canceled = await images.persist(source.path);
        await images.discardUnreferenced([
          canceled,
          canceled,
          retained,
          source.path,
        ], controller.imagePathsInUse);
        expect(await File(canceled).exists(), isFalse);
        expect(await File(retained).readAsBytes(), png);
        expect(await source.readAsBytes(), png);
        expect(await controller.imagePathsInUse(), contains(retained));
      });
    },
  );

  testWidgets(
    'cleanup after replacement removes only the superseded owned image',
    (tester) async {
      await tester.runAsync(() async {
        final source = File(path.join(directory.path, 'picker.png'));
        await source.writeAsBytes(png);
        final original = await images.persist(source.path);
        final saved = await controller.saveOption(
          name: '更换图片的餐食',
          periods: {MealPeriod.lunch},
          imagePath: original,
        );
        final replacement = await images.persist(source.path);
        final edited = await controller.saveOption(
          id: saved.option!.id,
          name: saved.option!.name,
          periods: saved.option!.periods,
          imagePath: replacement,
        );
        expect(edited.changed, isTrue);
        await images.discardUnreferenced([
          original,
          replacement,
        ], controller.imagePathsInUse);
        expect(await File(original).exists(), isFalse);
        expect(await File(replacement).readAsBytes(), png);
        final stored = (await repository.options()).singleWhere(
          (option) => option.id == saved.option!.id,
        );
        expect(stored.imagePath, replacement);
      });
    },
  );

  testWidgets('failed durable-reference reads retain possible backing images', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = File(path.join(directory.path, 'picker.png'));
      await source.writeAsBytes(png);
      final owned = await images.persist(source.path);
      await images.discardUnreferenced([
        owned,
      ], () async => throw StateError('Injected reference read failure'));
      expect(await File(owned).readAsBytes(), png);
    });
  });

  testWidgets(
    'valid PNG header with a truncated body never becomes an owned image',
    (tester) async {
      await tester.runAsync(() async {
        final source = File(path.join(directory.path, 'truncated.png'));
        // The complete PNG signature and IHDR describe a real 1x1 RGBA image;
        // truncation removes the image data and closing chunks.
        await source.writeAsBytes(png.sublist(0, 33));
        final existing = controller.options.first;
        expect(controller.startDraw(), isTrue);
        controller.finishDraw();
        final selected = controller.result;
        await expectLater(images.persist(source.path), throwsA(anything));
        expect(
          await Directory(path.join(directory.path, 'option-images')).exists(),
          isFalse,
        );
        final stored = (await repository.options()).singleWhere(
          (option) => option.id == existing.id,
        );
        expect(stored.imagePath, isNull);
        expect(controller.result, same(selected));
        expect(controller.restartNotice, isNull);
      });
    },
  );
}
