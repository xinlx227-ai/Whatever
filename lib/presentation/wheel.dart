import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/meal.dart';

const paper = Color(0xfffffaf1);
const ink = Color(0xff372e25);
const accent = Color(0xffb94320);
const muted = Color(0xff776658);
const soft = Color(0xfff4e9d8);

class WheelSector {
  WheelSector({
    required Iterable<String> optionIds,
    required this.assetName,
    required this.isMystery,
  }) : optionIds = List.unmodifiable(optionIds);

  final List<String> optionIds;
  final String assetName;
  final bool isMystery;
}

/// Maps already-sampled candidates to display sectors; it never draws a result.
class WheelLayout {
  WheelLayout._(Iterable<WheelSector> sectors)
    : sectors = List.unmodifiable(sectors) {
    for (var index = 0; index < this.sectors.length; index++) {
      for (final id in this.sectors[index].optionIds) {
        _sectorByOption[id] = index;
      }
    }
  }

  factory WheelLayout.fromOptions(List<FoodOption> options) {
    final sorted = [...options]..sort((a, b) => a.id.compareTo(b.id));
    if (sorted.map((option) => option.id).toSet().length != sorted.length) {
      throw ArgumentError('Wheel candidates must have unique IDs.');
    }
    final groups = <String, List<String>>{};
    for (final option in sorted) {
      groups.putIfAbsent(_assetFor(option), () => []).add(option.id);
    }
    final assets = groups.keys.toList()..sort();
    final members = <List<String>>[];
    final sectorAssets = <String>[];
    if (options.length <= maximumSectors) {
      for (final asset in assets) {
        for (final id in groups[asset]!) {
          members.add([id]);
          sectorAssets.add(asset);
        }
      }
    } else {
      // All known illustrations fit under the cap. Split only compatible groups
      // and give the largest remaining group the next available display sector.
      final allocations = {for (final asset in assets) asset: 1};
      var count = assets.length;
      while (count < maximumSectors) {
        String? next;
        var largest = 0.0;
        for (final asset in assets) {
          final allocated = allocations[asset]!;
          if (allocated >= groups[asset]!.length) continue;
          final load = groups[asset]!.length / allocated;
          if (load > largest) {
            largest = load;
            next = asset;
          }
        }
        if (next == null) break;
        allocations[next] = allocations[next]! + 1;
        count++;
      }
      for (final asset in assets) {
        final ids = groups[asset]!;
        final allocated = allocations[asset]!;
        for (var split = 0; split < allocated; split++) {
          members.add([
            for (var i = split; i < ids.length; i += allocated) ids[i],
          ]);
          sectorAssets.add(asset);
        }
      }
    }
    final mysteryCount = options.length < 10 ? 0 : (members.length / 3).round();
    final mysteryIndices = <int>{
      for (var i = 0; i < mysteryCount; i++)
        ((i + .5) * members.length / mysteryCount).floor(),
    };
    return WheelLayout._([
      for (var i = 0; i < members.length; i++)
        WheelSector(
          optionIds: members[i],
          assetName: sectorAssets[i],
          isMystery: mysteryIndices.contains(i),
        ),
    ]);
  }

  static const maximumSectors = 18;
  final List<WheelSector> sectors;
  final _sectorByOption = <String, int>{};

  /// Sector zero begins at the top; its center is half a sector clockwise.
  /// Rotate by -(index + .5) * 2*pi / sectors.length to face the fixed pointer.
  int sectorIndexFor(String optionId) {
    final index = _sectorByOption[optionId];
    if (index == null) throw StateError('Candidate is absent from this wheel.');
    return index;
  }

  static String _assetFor(FoodOption option) {
    // Registry order is the fixed priority when an option has multiple tags.
    final scenario = MealScenario.fromKey(option.scenario);
    final category = scenarioCategories[scenario]!.firstWhere(
      (category) => category != '未分类' && option.categories.contains(category),
      orElse: () => '未分类',
    );
    if (scenario == MealScenario.restaurant) {
      return switch (category) {
        '火锅' => 'shop-hotpot',
        '烧烤' => 'shop-barbecue',
        '中餐' => 'shop-chinese',
        '西餐' => 'shop-western',
        '快餐' => 'shop-fastfood',
        '自助餐' => 'shop-buffet',
        _ => 'storefront',
      };
    }
    if (scenario == MealScenario.cook) return 'plate';
    return switch (category) {
      '盖饭套餐' => 'rice',
      '面食' || '粉类' => 'noodle',
      '粥类' => 'porridge',
      '西式快餐' => 'burger',
      '饮品' => 'drink',
      // A bun would misrepresent pancakes, and noodles would misrepresent dumplings.
      _ => 'plate',
    };
  }
}

class MealWheel extends StatelessWidget {
  const MealWheel({
    super.key,
    required this.options,
    required this.angle,
    this.centerLabel = '开饭',
    this.layout,
  });

  final List<FoodOption> options;
  final double angle;
  final String centerLabel;
  final WheelLayout? layout;

  @override
  Widget build(BuildContext context) {
    final display = layout ?? WheelLayout.fromOptions(options);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth;
              final radius = side / 2 - 5;
              final count = display.sectors.length;
              final iconSize = count < 2
                  ? side * .17
                  : math.min(
                      side * .17,
                      radius * .73 * 2 * math.pi / count * .8,
                    );
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                    key: const ValueKey('wheel-rotor'),
                    angle: angle,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _WheelPainter(count)),
                        ),
                        for (var i = 0; i < count; i++)
                          Positioned(
                            left:
                                side / 2 +
                                math.cos(
                                      -math.pi / 2 +
                                          (i + .5) * 2 * math.pi / count,
                                    ) *
                                    radius *
                                    .73 -
                                iconSize / 2,
                            top:
                                side / 2 +
                                math.sin(
                                      -math.pi / 2 +
                                          (i + .5) * 2 * math.pi / count,
                                    ) *
                                    radius *
                                    .73 -
                                iconSize / 2,
                            child: SizedBox.square(
                              dimension: iconSize,
                              child: display.sectors[i].isMystery
                                  ? const CustomPaint(
                                      painter: _MysteryPainter(),
                                    )
                                  : display.sectors[i].assetName == 'plate'
                                  ? const CustomPaint(painter: _PlatePainter())
                                  : SvgPicture.asset(
                                      'assets/food/${display.sectors[i].assetName}.svg',
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      key: const ValueKey('wheel-fixed-pointer'),
                      painter: _HubPointerPainter(side * .12),
                    ),
                  ),
                  SizedBox.square(
                    dimension: side * .24,
                    child: Padding(
                      padding: EdgeInsets.all(side * .035),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerLabel,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.count);
  final int count;
  static const colors = [
    Color(0xffefca91),
    Color(0xffd9e5c3),
    Color(0xfff2bda9),
    Color(0xfff8e2a3),
    Color(0xffbcd6cb),
    Color(0xffdfc9dc),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (count == 0) canvas.drawCircle(center, radius, Paint()..color = soft);
    for (var i = 0; i < count; i++) {
      final sweep = 2 * math.pi / count;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      if (count > 1) {
        canvas.drawArc(
          rect,
          -math.pi / 2 + i * sweep,
          sweep,
          true,
          Paint()
            ..color = paper
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xffedcf97)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.count != count;
}

class _HubPointerPainter extends CustomPainter {
  const _HubPointerPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pointer = Path()
      ..moveTo(center.dx, center.dy - radius * 1.72)
      ..lineTo(center.dx + radius * .3, center.dy - radius * .8)
      ..lineTo(center.dx - radius * .3, center.dy - radius * .8)
      ..close();
    canvas.drawPath(pointer, Paint()..color = accent);
    canvas.drawCircle(center, radius, Paint()..color = paper);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xfff9ecd6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_HubPointerPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

class _MysteryPainter extends CustomPainter {
  const _MysteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 36);
    final stroke = Paint()
      ..color = const Color(0xff785582)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final star = Path()
      ..moveTo(0, -14)
      ..quadraticBezierTo(2, -2, 11, 0)
      ..quadraticBezierTo(2, 2, 0, 14)
      ..quadraticBezierTo(-2, 2, -11, 0)
      ..quadraticBezierTo(-2, -2, 0, -14);
    canvas.drawPath(star, stroke);
    canvas.drawCircle(const Offset(12, -12), 2, Paint()..color = stroke.color);
    canvas.drawLine(const Offset(-12, 12), const Offset(-6, 12), stroke);
    canvas.drawLine(const Offset(-9, 9), const Offset(-9, 15), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MysteryPainter oldDelegate) => false;
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .34;
    canvas.drawCircle(center, radius, Paint()..color = paper);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      radius * .72,
      Paint()
        ..color = const Color(0xffd6b88c)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => false;
}
