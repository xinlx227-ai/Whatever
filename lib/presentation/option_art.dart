import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/meal.dart';

class OptionArt extends StatelessWidget {
  const OptionArt({super.key, required this.option, required this.size});
  final FoodOption option;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => option.art == 'plate'
        ? Icon(
            Icons.restaurant_outlined,
            size: size * .65,
            color: Theme.of(context).colorScheme.primary,
          )
        : SvgPicture.asset(
            'assets/food/${option.art}.svg',
            width: size,
            height: size,
          );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: option.imagePath == null
            ? fallback()
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(option.imagePath!),
                  width: size,
                  height: size,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback(),
                ),
              ),
      ),
    );
  }
}
