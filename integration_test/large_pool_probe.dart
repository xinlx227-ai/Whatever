/// Release-only Android entry point for host-driven Issue #16 measurements.
/// Uses actual production widgets and gestures; no Flutter test binding.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:whatever/application/meal_controller.dart';
import 'package:whatever/data/meal_repository.dart';
import 'package:whatever/domain/meal.dart';
import 'package:whatever/domain/meal_preferences.dart';
import 'package:whatever/presentation/meal_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid || !kReleaseMode) {
    throw StateError('This measurement probe requires Android release mode.');
  }
  final external = await getExternalStorageDirectory();
  if (external == null) {
    throw StateError('External control directory unavailable');
  }
  final probe = _Probe(Directory(p.join(external.path, 'issue16')));
  await probe.directory.create(recursive: true);
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('等待模拟器测量指令'))),
    ),
  );
  SchedulerBinding.instance.addTimingsCallback(probe.recordFrames);
  GestureBinding.instance.pointerRouter.addGlobalRoute(probe.recordPointer);
  await probe.respond({
    'id': 'boot',
    'ok': true,
    'pid': pid,
    'release': kReleaseMode,
  });
  await probe.listen();
}

class _Probe {
  _Probe(this.directory);
  final Directory directory;
  MealRepository? repository;
  MealController? controller;
  Directory? fixture;
  String? lastCommand;
  Map<String, dynamic>? arm;
  Map<String, dynamic>? input;
  final List<Map<String, dynamic>> frames = [];
  final Map<int, Map<String, dynamic>> framesByNumber = {};
  final List<Map<String, dynamic>> inputs = [];
  final List<Map<String, dynamic>> windows = [];
  Map<String, dynamic>? activeWindow;
  Map<String, dynamic> caseInfo = {};

  int get now => DateTime.now().microsecondsSinceEpoch;
  File get commandFile => File(p.join(directory.path, 'command.json'));

  Future<void> respond(Map<String, dynamic> value) async {
    final temporary = File(p.join(directory.path, 'response.tmp'));
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(p.join(directory.path, 'response.json'));
  }

  Future<void> listen() async {
    while (true) {
      try {
        if (await commandFile.exists()) {
          final command =
              jsonDecode(await commandFile.readAsString())
                  as Map<String, dynamic>;
          final id = command['id'] as String;
          if (lastCommand != id) {
            lastCommand = id;
            try {
              final result = await execute(command);
              await respond({'id': id, 'ok': true, ...result});
            } catch (error, stack) {
              await respond({
                'id': id,
                'ok': false,
                'error': '$error',
                'stack': '$stack',
              });
            }
          }
        }
      } catch (_) {
        // Host renames complete JSON into place; retry incomplete reads.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<Map<String, dynamic>> execute(Map<String, dynamic> command) async {
    switch (command['op']) {
      case 'configure':
        await configure(command);
        return state();
      case 'state':
        return state();
      case 'idle':
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (controller?.isBusy == true || controller?.isDrawing == true) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Production state did not become idle');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return state();
      case 'resolve':
        return await resolve(command);
      case 'begin':
        if (activeWindow != null) throw StateError('A window is already open');
        activeWindow = {'label': command['label'], 'startWallUs': now};
        return {'window': activeWindow};
      case 'end':
        if (activeWindow == null) throw StateError('No open window');
        activeWindow!['endWallUs'] = now;
        windows.add(activeWindow!);
        activeWindow = null;
        return state();
      case 'export':
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final report = {
          'protocol': 1,
          'case': caseInfo,
          'pid': pid,
          'release': kReleaseMode,
          'windows': windows,
          'frames': frames,
          'inputs': inputs,
          'state': state(),
        };
        await File(
          p.join(directory.path, 'report.json'),
        ).writeAsString(jsonEncode(report), flush: true);
        return {'report': p.join(directory.path, 'report.json'), ...state()};
      default:
        throw ArgumentError('Unknown operation ${command['op']}');
    }
  }

  Future<void> configure(Map<String, dynamic> command) async {
    final count = command['pool'] as int;
    final photoPercent = command['photos'] as int;
    final mode = DrawMode.values.byName(command['mode'] as String);
    final scenario = MealScenario.values.byName(
      command['scenario'] as String? ?? 'eat',
    );
    if (![50, 200, 1000].contains(count) ||
        ![0, 50, 100].contains(photoPercent)) {
      throw ArgumentError('Use the fixed pool/photo matrix');
    }
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    controller?.removeListener(changed);
    controller?.dispose();
    await repository?.close();
    if (fixture != null) await fixture!.delete(recursive: true);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    frames.clear();
    framesByNumber.clear();
    inputs.clear();
    windows.clear();
    activeWindow = null;
    arm = null;
    input = null;
    fixture = await Directory.systemTemp.createTemp('issue16-native-');
    final databasePath = p.join(fixture!.path, 'fixture.sqlite');
    final created = await MealRepository.open(
      factory: databaseFactory,
      path: databasePath,
    );
    await created.savePreferences(
      MealPreferences(
        mode: mode,
        cardTutorialDismissed: true,
        cardCollectionTutorialDismissed: true,
      ),
    );
    await created.close();
    final database = await databaseFactory.openDatabase(databasePath);
    final photoCount = count * photoPercent ~/ 100;
    try {
      await database.transaction((transaction) async {
        await transaction.update('options', {'is_active': 0});
        final batch = transaction.batch();
        for (var index = 0; index < count; index++) {
          final id =
              'issue16-${scenario.name}-${index.toString().padLeft(4, '0')}';
          final photo = index < photoCount
              ? p.join(
                  directory.path,
                  'photos',
                  'photo-${index.toString().padLeft(4, '0')}.jpg',
                )
              : null;
          if (photo != null && !await File(photo).exists()) {
            throw StateError('Missing distinct fixture photo $photo');
          }
          batch.insert('options', {
            'id': id,
            'name': scenario == MealScenario.restaurant
                ? '测量餐厅${index.toString().padLeft(4, '0')}城市中心广场北门旗舰分店'
                : '测量菜品${index.toString().padLeft(4, '0')}香菇时蔬鸡肉砂锅配米饭套餐',
            'art': seedOptions[index % seedOptions.length].art,
            'scenario': scenario.name,
            'category': '未分类',
            'is_builtin': 0,
            'is_active': 1,
            'is_deleted': 0,
            'image_path': photo,
          });
          batch.insert('option_categories', {
            'option_id': id,
            'category': '未分类',
          });
          for (final period in MealPeriod.values) {
            batch.insert('option_periods', {
              'option_id': id,
              'period': period.name,
            });
          }
        }
        await batch.commit(noResult: true);
      });
    } finally {
      await database.close();
    }
    repository = await MealRepository.open(
      factory: databaseFactory,
      path: databasePath,
    );
    controller = MealController(
      repository: repository!,
      random: math.Random(16),
      clock: () => DateTime(2026, 10, 13, 12),
    );
    await controller!.initialize();
    controller!.changeScenario(scenario);
    controller!.addListener(changed);
    caseInfo = {
      'pool': count,
      'photos': photoPercent,
      'mode': mode.name,
      'scenario': scenario.name,
    };
    runApp(MealApp(controller: controller!));
    await Future<void>.delayed(const Duration(seconds: 2));
    if (controller!.availableCount != count) {
      throw StateError('Eligible fixture count mismatch');
    }
  }

  Map<String, dynamic> state() {
    final model = controller;
    return {
      'pid': pid,
      'wallUs': now,
      'configured': model != null,
      if (model != null) ...{
        'busy': model.isBusy,
        'drawing': model.isDrawing,
        'hasRound': model.hasRound,
        'selected': model.selectedCardIndex,
        'results': model.results.map((value) => value.id).toList(),
        'historyCount': model.history.length,
        'latestHistoryKey': model.history.isEmpty
            ? null
            : 'history-${model.history.first.operationId}',
        'available': model.availableCount,
        'error': model.error,
      },
    };
  }

  List<Element> elements(bool Function(Element) matches) {
    final result = <Element>[];
    void visit(Element element) {
      if (matches(element)) result.add(element);
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return result;
  }

  String? keyOf(Element element) {
    final key = element.widget.key;
    return key is ValueKey<String> ? key.value : null;
  }

  Future<Map<String, dynamic>> resolve(Map<String, dynamic> command) async {
    final target = command['key'] as String?;
    final text = command['text'] as String?;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    var matches = elements(
      (element) => target == 'visible-card'
          ? (keyOf(element)?.startsWith('candidate-card-') ?? false)
          : target != null
          ? keyOf(element) == target
          : element.widget is Text && (element.widget as Text).data == text,
    );
    if (target == 'visible-card') {
      matches = matches.where((element) {
        final box = element.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) return false;
        final point = box.localToGlobal(
          Offset(box.size.width * .18, box.size.height * .6),
        );
        return screen.deflate(35).contains(point);
      }).toList();
      matches.sort((a, b) {
        final aa = a.findRenderObject()! as RenderBox;
        final bb = b.findRenderObject()! as RenderBox;
        return (aa.localToGlobal(aa.size.center(Offset.zero)).dx -
                screen.center.dx)
            .abs()
            .compareTo(
              (bb.localToGlobal(bb.size.center(Offset.zero)).dx -
                      screen.center.dx)
                  .abs(),
            );
      });
    }
    if (matches.isEmpty) {
      throw StateError('Target not mounted: ${target ?? text}');
    }
    final element = matches.first;
    if (target != 'visible-card' && command['ensureVisible'] != false) {
      await Scrollable.ensureVisible(
        element,
        duration: const Duration(milliseconds: 200),
        alignment: .5,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      throw StateError('Target has no render box');
    }
    final isCard = keyOf(element)?.startsWith('candidate-card-') ?? false;
    final selected =
        isCard &&
        int.tryParse(keyOf(element)!.split('-').last) ==
            controller?.selectedCardIndex;
    final point = box.localToGlobal(
      Offset(
        box.size.width *
            ((command['fractionX'] as num?)?.toDouble() ??
                (isCard && !selected ? .18 : .5)),
        box.size.height * .6,
      ),
    );
    if (!screen.contains(point)) {
      throw StateError('Target outside screen: $point');
    }
    if (command['feedback'] != null) {
      arm = {
        'label': command['label'] ?? target,
        'kind': command['feedback'],
        'previousSelected': controller?.selectedCardIndex,
      };
    } else {
      arm = null;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    return {
      'key': keyOf(element),
      'x': (point.dx * view.devicePixelRatio).round(),
      'y': (point.dy * view.devicePixelRatio).round(),
      'left': (topLeft.dx * view.devicePixelRatio).round(),
      'top': (topLeft.dy * view.devicePixelRatio).round(),
      'width': (box.size.width * view.devicePixelRatio).round(),
      'height': (box.size.height * view.devicePixelRatio).round(),
    };
  }

  void recordPointer(PointerEvent event) {
    if (event is! PointerDownEvent || arm == null) return;
    input = {
      ...arm!,
      'pointer': event.pointer,
      'deliveredWallUs': now,
      'platformTimestampUs': event.timeStamp.inMicroseconds,
    };
    inputs.add(input!);
    arm = null;
  }

  bool feedbackMatches(Map<String, dynamic> value) => switch (value['kind']) {
    'selection' =>
      controller?.selectedCardIndex != null &&
          controller?.selectedCardIndex != value['previousSelected'],
    'drawing' => controller?.isDrawing == true,
    'busy' => controller?.isBusy == true,
    _ => false,
  };

  Map<String, Object?> feedbackState() => {
    'selected': controller?.selectedCardIndex,
    'selectedOptionId': controller?.selectedCard?.id,
    'drawing': controller?.isDrawing,
    'busy': controller?.isBusy,
    'resultIds': controller?.results.map((option) => option.id).join(','),
  };

  void changed() {
    final pending = input;
    if (pending == null ||
        pending.containsKey('stateWallUs') ||
        !feedbackMatches(pending)) {
      return;
    }
    pending['stateWallUs'] = now;
    pending['stateWitness'] = feedbackState();
    pending['candidateFrames'] = <Map<String, Object?>>[];
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => witnessFeedback(pending),
    );
  }

  void witnessFeedback(Map<String, dynamic> pending) {
    if (pending['rasterFinishWallUs'] != null) {
      return;
    }
    final current = feedbackState();
    final candidates = pending['candidateFrames'] as List<Map<String, Object?>>;
    if (!feedbackMatches(pending) ||
        !mapEquals(pending['stateWitness'] as Map<String, Object?>, current)) {
      pending['stateEndedWallUs'] = now;
      pending['supersededBeforeFrame'] = candidates.isEmpty;
      return;
    }
    final frameNumber = ui.PlatformDispatcher.instance.frameData.frameNumber;
    final rawStamp =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    candidates.add({
      'frameNumber': frameNumber,
      'schedulerRawStampUs': rawStamp,
      'postFrameWallUs': now,
      'state': current,
    });
    // Preserve the original marker for timebase diagnostics; frame IDs prove
    // identity without inferring a match from nearby timestamps.
    pending.putIfAbsent('feedbackVsyncStartUs', () => rawStamp);
    pending.putIfAbsent('firstFeedbackFrameNumber', () => frameNumber);
    joinInput(pending);
    if (pending['rasterFinishWallUs'] == null) {
      // Observe the next naturally produced frame without requesting a frame.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => witnessFeedback(pending),
      );
    }
  }

  void joinInput(Map<String, dynamic> pending) {
    if (pending['candidateFrames'] == null ||
        pending['rasterFinishWallUs'] != null) {
      return;
    }
    final candidates = pending['candidateFrames'] as List<Map<String, Object?>>;
    Map<String, dynamic>? match;
    for (final candidate in candidates) {
      final number = candidate['frameNumber'] as int;
      if (number < 0) {
        continue;
      }
      match = framesByNumber[number];
      if (match != null) {
        break;
      }
    }
    if (match == null) {
      return;
    }
    pending['matchedFeedbackFrameNumber'] = match['frame'];
    pending['joinMethod'] = 'exactFrameNumberWithPersistentStateWitness';
    pending['rasterFinishWallUs'] = match['rasterFinishWallUs'];
    pending['deliveryToStateUs'] =
        (pending['stateWallUs'] as int) - (pending['deliveredWallUs'] as int);
    pending['deliveryToRasterUs'] =
        (match['rasterFinishWallUs'] as int) -
        (pending['deliveredWallUs'] as int);
    final platformTime = pending['platformTimestampUs'] as int;
    final rawFinish = match['rasterFinishUs'] as int;
    final wallOffset = (match['rasterFinishWallUs'] as int) - rawFinish;
    final queueUs =
        (pending['deliveredWallUs'] as int) - wallOffset - platformTime;
    final platformToRasterUs = rawFinish - platformTime;
    pending['platformToDartDeliveryUs'] = queueUs;
    pending['platformEventToRasterUs'] = platformToRasterUs;
    pending['inputClockValid'] =
        platformTime > 0 &&
        rawFinish > 0 &&
        queueUs >= 0 &&
        queueUs <= 5000000 &&
        platformToRasterUs >= 0 &&
        platformToRasterUs <= 5000000 &&
        (pending['deliveryToRasterUs'] as int) >= 0;
  }

  void recordFrames(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      final finishWall = timing.timestampInMicroseconds(
        ui.FramePhase.rasterFinishWallTime,
      );
      final offset =
          finishWall -
          timing.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      final frame = <String, dynamic>{
        'frame': timing.frameNumber,
        'buildUs': timing.buildDuration.inMicroseconds,
        'rasterUs': timing.rasterDuration.inMicroseconds,
        'totalSpanUs': timing.totalSpan.inMicroseconds,
        'vsyncWallUs':
            timing.timestampInMicroseconds(ui.FramePhase.vsyncStart) + offset,
        'vsyncStartUs': timing.timestampInMicroseconds(
          ui.FramePhase.vsyncStart,
        ),
        'buildStartUs': timing.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        ),
        'rasterFinishUs': timing.timestampInMicroseconds(
          ui.FramePhase.rasterFinish,
        ),
        'rasterFinishWallUs': finishWall,
      };
      frames.add(frame);
      framesByNumber[timing.frameNumber] = frame;
    }
    for (final pending in inputs) {
      joinInput(pending);
    }
  }
}
