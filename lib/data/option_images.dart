import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies validated picker bytes into app-owned storage before saving a row.
class OptionImages {
  OptionImages({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<void> discardUnreferenced(
    Iterable<String> candidates,
    Future<Set<String>> Function() readReferences,
  ) async {
    if (candidates.isEmpty) return;
    try {
      final references = await readReferences();
      final root = p.normalize(
        p.absolute(p.join((await _directory()).path, 'option-images')),
      );
      for (final candidate in candidates.toSet()) {
        final path = p.normalize(p.absolute(candidate));
        if (references.contains(candidate) || !p.isWithin(root, path)) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Retain the file when durable references cannot be verified or storage
      // is unavailable. Cleanup failure must not turn a saved option into failure.
    }
  }

  Future<String> persist(String source, {String? existingPath}) async {
    final bytes = await File(source).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = min(1.0, 1600 / max(width, height));
        return ui.TargetImageSize(
          width: max(1, (width * scale).round()),
          height: max(1, (height * scale).round()),
        );
      },
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    if (existingPath != null && await File(existingPath).exists()) {
      if (listEquals(bytes, await File(existingPath).readAsBytes())) {
        return existingPath;
      }
    }
    final directory = Directory(
      p.join((await _directory()).path, 'option-images'),
    );
    await directory.create(recursive: true);
    final token = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final target = File(p.join(directory.path, '$token.img'));
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
      return target.path;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
