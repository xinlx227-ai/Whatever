import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
    // Bound both decoded dimensions, including unusually tall user photos.
    // A two-times display budget preserves detail for ordinary cover crops.
    final decodeExtent = (size * MediaQuery.devicePixelRatioOf(context) * 2)
        .ceil()
        .clamp(1, 2048);
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
                child: Image(
                  image: _BoundedFileImage(
                    File(option.imagePath!),
                    decodeExtent,
                  ),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback(),
                ),
              ),
      ),
    );
  }
}

// ResizeImagePolicy.fit can round the short side of extreme images to zero.
// Keep aspect ratio to pixel precision with a positive bounded decode size.
class _BoundedFileImage extends FileImage {
  const _BoundedFileImage(super.file, this.extent);

  final int extent;

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) =>
      super.loadImage(
        key,
        (buffer, {getTargetSize}) => decode(
          buffer,
          getTargetSize: (width, height) {
            final scale = math.min(1.0, extent / math.max(width, height));
            return ui.TargetImageSize(
              width: math.max(1, (width * scale).round()),
              height: math.max(1, (height * scale).round()),
            );
          },
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is _BoundedFileImage &&
      other.file.path == file.path &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(file.path, extent);
}
