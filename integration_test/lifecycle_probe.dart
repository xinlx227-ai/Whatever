/// Test-only Android entry point for host-driven adb lifecycle verification.
/// Build with --target integration_test/lifecycle_probe.dart, then use adb to
/// background, lock, terminate, or remove the process from recent tasks and
/// inspect the visible state through uiautomator. Uses its own durable database.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MealRepository? repository;
  MealController? controller;
  try {
    repository = await MealRepository.open(
      factory: databaseFactory,
      path: p.join(await getDatabasesPath(), 'lifecycle-probe.sqlite'),
    );
    controller = MealController(repository: repository);
    await controller.initialize();
    runApp(
      MaterialApp(
        home: _ProbePage(controller: controller, repository: repository),
      ),
    );
  } catch (error) {
    controller?.dispose();
    await repository?.close();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(child: Text('Initialization error: $error')),
        ),
      ),
    );
  }
}

class _ProbePage extends StatefulWidget {
  const _ProbePage({required this.controller, required this.repository});

  final MealController controller;
  final MealRepository repository;

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  String? _actionError;
  bool _runningAction = false;

  MealController get controller => widget.controller;

  void _require(bool accepted, String action) {
    if (!accepted) {
      throw StateError(controller.error ?? '$action was rejected');
    }
  }

  Future<void> _run(FutureOr<void> Function() action) async {
    if (_runningAction) return;
    setState(() {
      _runningAction = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _prepare() async {
    _require(
      await controller.updatePreferences(
        const MealPreferences(mode: DrawMode.cards, excludeYesterday: true),
      ),
      'Update preferences',
    );
    _require(controller.excludeForSession('soy-milk'), 'Exclude soy-milk');
    _require(controller.changePeriod(MealPeriod.lateNight), 'Change period');
    _draw();
  }

  void _draw() {
    _require(controller.startDraw(), 'Start draw');
    controller.finishDraw();
  }

  Future<void> _reset() async {
    _require(controller.abandon(), 'Abandon');
    _require(
      await controller.updatePreferences(const MealPreferences()),
      'Reset preferences',
    );
    _require(controller.restoreSessionExclusions(), 'Restore exclusions');
  }

  @override
  void dispose() {
    controller.dispose();
    unawaited(widget.repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lifecycle probe')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            final exclusions = controller.sessionExclusions.toList()..sort();
            final enabled = !_runningAction && !controller.isBusy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('processId: $pid'),
                Text('period: ${controller.period.name}'),
                Text('mode: ${controller.preferences.mode.name}'),
                Text(
                  'excludeYesterday: ${controller.preferences.excludeYesterday}',
                ),
                Text('sessionExclusions: [${exclusions.join(',')}]'),
                Text('hasRound: ${controller.hasRound}'),
                Text('isDrawing: ${controller.isDrawing}'),
                Text('isModeLocked: ${controller.isModeLocked}'),
                Text('result: ${controller.result?.id ?? 'none'}'),
                Text('historyCount: ${controller.history.length}'),
                Text('controllerError: ${controller.error ?? 'none'}'),
                Text('probeError: ${_actionError ?? 'none'}'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: enabled ? () => _run(_prepare) : null,
                      child: const Text('Prepare session'),
                    ),
                    ElevatedButton(
                      onPressed: enabled
                          ? () => _run(() async {
                              _require(await controller.confirm(), 'Confirm');
                            })
                          : null,
                      child: const Text('Confirm'),
                    ),
                    ElevatedButton(
                      onPressed: enabled ? () => _run(_draw) : null,
                      child: const Text('New round'),
                    ),
                    ElevatedButton(
                      onPressed: enabled
                          ? () => _run(() {
                              _require(controller.abandon(), 'Abandon');
                            })
                          : null,
                      child: const Text('Abandon'),
                    ),
                    ElevatedButton(
                      onPressed: enabled ? () => _run(_reset) : null,
                      child: const Text('Reset preferences'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
