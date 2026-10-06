import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/presentation/meal_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android draw, confirm, browse, and reopen durable history', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('meal-android-');
    final path = p.join(directory.path, 'journey.sqlite');
    var repository = await MealRepository.open(
      factory: databaseFactory,
      path: path,
    );
    var controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 6, 12),
    );
    await controller.initialize();
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('primary-action')));
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pump();
    expect(controller.isDrawing, isTrue);
    expect(controller.history, isEmpty);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final chosen = controller.result!;
    expect(find.text(chosen.name), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('primary-action')));
    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    expect(controller.hasRound, isFalse);
    expect(controller.history, hasLength(1));
    await tester.tap(find.text('足迹'));
    await tester.pumpAndSettle();
    expect(find.text(chosen.name), findsOneWidget);
    await tester.tap(find.text('选项库'));
    await tester.pumpAndSettle();
    expect(controller.options, hasLength(8));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await repository.close();
    repository = await MealRepository.open(
      factory: databaseFactory,
      path: path,
    );
    controller = MealController(repository: repository);
    await controller.initialize();
    await tester.pumpWidget(MealApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.hasRound, isFalse);
    await tester.tap(find.text('足迹'));
    await tester.pumpAndSettle();
    expect(controller.history, hasLength(1));
    expect(find.text(chosen.name), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });
}
