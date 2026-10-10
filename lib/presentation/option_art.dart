import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/meal.dart';

// Stable identities keep default artwork unchanged by display/category edits.
String defaultOptionArt(FoodOption option) {
  if (option.art != 'storefront') return option.art;
  return switch (option.id) {
    'restaurant-haidilao' || 'restaurant-xiabuxiabu' => 'shop-hotpot',
    'restaurant-wooden-house' || 'restaurant-long-ago' => 'shop-barbecue',
    'restaurant-xibei' || 'restaurant-grandmas-home' => 'shop-chinese',
    'restaurant-pizza-hut' || 'restaurant-saizeriya' => 'shop-western',
    'restaurant-kfc' || 'restaurant-mcdonalds' => 'shop-fastfood',
    'restaurant-big-pizza' || 'restaurant-han-ba-wei-de' => 'shop-buffet',
    _ => 'storefront',
  };
}

class OptionArt extends StatelessWidget {
  const OptionArt({super.key, required this.option, required this.size});
  final FoodOption option;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => SvgPicture.asset(
      'assets/food/${defaultOptionArt(option)}.svg',
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
