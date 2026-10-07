import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/meal.dart';

const paper = Color(0xfffffaf1);
const ink = Color(0xff372e25);
const accent = Color(0xffb94320);
const muted = Color(0xff776658);
const soft = Color(0xfff4e9d8);

class MealWheel extends StatelessWidget {
  const MealWheel({
    super.key,
    required this.options,
    required this.angle,
    this.centerLabel = '开饭',
  });
  final List<FoodOption> options;
  final double angle;
  final String centerLabel;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Transform.rotate(
              angle: angle,
              child: CustomPaint(
                painter: _WheelPainter(options),
                size: Size.infinite,
              ),
            ),
          ),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: paper,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
            ),
            child: Center(
              child: Text(
                centerLabel,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            child: Icon(Icons.arrow_drop_down_rounded, color: accent, size: 54),
          ),
        ],
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.options);
  final List<FoodOption> options;
  static const colors = [
    Color(0xffefca91),
    Color(0xffd9e5c3),
    Color(0xfff2bda9),
    Color(0xfff8e2a3),
    Color(0xffbcd6cb),
    Color(0xffdfc9dc),
    Color(0xfff3d3af),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (options.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi / options.length;
    for (var i = 0; i < options.length; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
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
      final middle = (i + .5) * sweep;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(middle);
      final label = TextPainter(
        text: TextSpan(
          text: options[i].name,
          style: TextStyle(
            color: ink,
            fontSize: options.length > 6 ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: options.length > 6 ? radius - 48 : radius);
      if (options.length > 6) {
        // Radial labels fit dense candidate pools; the result shows the full name.
        canvas.translate(0, -radius * .7);
        canvas.rotate(-math.pi / 2);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      } else {
        label.paint(canvas, Offset(-label.width / 2, -radius * .73));
        canvas.drawCircle(
          Offset(0, -radius * .49),
          2.5,
          Paint()..color = muted,
        );
      }
      canvas.restore();
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xfff0d5a3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.options != options;
}
