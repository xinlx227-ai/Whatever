import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late MealRepository repository;
  late MealController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scenario-controller-');
    repository = await MealRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/meal.sqlite',
    );
    controller = MealController(
      repository: repository,
      clock: () => DateTime(2026, 10, 7, 12),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'each scenario and period uses a distinct full pool and durable history',
    () async {
      const expectedCounts = {
        MealScenario.eat: [14, 28, 29, 19],
        MealScenario.cook: [6, 20, 20, 6],
        MealScenario.restaurant: [2, 10, 12, 6],
      };
      for (final scenario in MealScenario.values) {
        expect(controller.changeScenario(scenario), isTrue);
        for (final period in MealPeriod.values) {
          controller.changePeriod(period);
          expect(
            controller.candidates,
            hasLength(expectedCounts[scenario]![period.index]),
          );
          expect(
            controller.candidates.map((option) => option.id).toSet().length,
            controller.candidates.length,
          );
          expect(
            controller.candidates.every(
              (option) =>
                  option.scenario == scenario.name &&
                  option.periods.contains(period),
            ),
            isTrue,
          );
          expect(controller.startDraw(), isTrue);
          controller.finishDraw();
          final selected = controller.result!;
          expect(await controller.confirm(), isTrue);
          expect(controller.scenario, scenario);
          expect(controller.period, period);
          expect(controller.history.first.option.id, selected.id);
          expect(controller.history.first.option.scenario, scenario.name);
          expect(controller.history.first.period, period);
        }
      }
      controller.dispose();
      await repository.close();
      repository = await MealRepository.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/meal.sqlite',
      );
      controller = MealController(
        repository: repository,
        clock: () => DateTime(2026, 10, 7, 6),
      );
      await controller.initialize();
      expect(controller.history, hasLength(12));
      expect(controller.scenario, MealScenario.eat);
      expect(controller.period, MealPeriod.breakfast);
      expect(controller.hasRound, isFalse);
    },
  );

  test(
    'scenario changes retain the shared manual period and session exclusions',
    () {
      controller.changePeriod(MealPeriod.lateNight);
      controller.excludeForSession('noodles');
      for (final scenario in MealScenario.values.reversed) {
        expect(controller.changeScenario(scenario), isTrue);
        expect(controller.period, MealPeriod.lateNight);
        expect(controller.sessionExclusions, {'noodles'});
      }
      expect(
        controller.candidates.any((option) => option.id == 'noodles'),
        isFalse,
      );
    },
  );

  test(
    'restaurant no-op preserves a food round; committed metadata change invalidates it',
    () async {
      final restaurant = controller.options.firstWhere(
        (option) => option.scenario == 'restaurant',
      );
      controller.startDraw();
      controller.finishDraw();
      final result = controller.result;
      final unchanged = await controller.saveOption(
        id: restaurant.id,
        scenario: restaurant.scenario,
        name: restaurant.name,
        category: restaurant.category,
        periods: restaurant.periods,
        address: '',
        notes: '',
      );
      expect(unchanged.status, OptionMutationStatus.unchanged);
      expect(controller.result, same(result));
      final saved = await controller.saveOption(
        id: restaurant.id,
        scenario: restaurant.scenario,
        name: restaurant.name,
        category: restaurant.category,
        periods: restaurant.periods,
        address: '测试路 12 号',
        notes: '先打电话确认',
      );
      expect(saved.changed, isTrue);
      expect(controller.hasRound, isFalse);
      expect(controller.scenario, MealScenario.eat);
      expect(controller.restartNotice, isNotNull);
      expect(
        controller.options
            .firstWhere((option) => option.id == restaurant.id)
            .address,
        '测试路 12 号',
      );
    },
  );
}
