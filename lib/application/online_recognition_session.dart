import 'dart:async';

import '../data/online_recognition_transport.dart';
import '../domain/online_recognition.dart';

/// A form owns one session. Revision checks also guard uncancellable transports.
class OnlineRecognitionSession {
  OnlineRecognitionSession({
    required this.transport,
    required this.apiKey,
    required this.reserve,
    required this.enabled,
  });

  final OnlineRecognitionTransport transport;
  final String apiKey;
  final Future<bool> Function() reserve;
  final bool Function() enabled;
  int _revision = 0;
  bool _disposed = false;

  void invalidate() {
    _revision++;
    transport.cancel();
  }

  Future<OnlineRecognitionResult?> recognize(
    OnlineRecognitionRequest request,
  ) async {
    invalidate();
    final revision = _revision;
    if (_disposed || !enabled() || apiKey.isEmpty) return null;
    bool current() => !_disposed && revision == _revision && enabled();
    Future<OnlineRecognitionResult?> run() async {
      if (!await reserve() || !current()) return null;
      final response = await transport.send(request.body, apiKey);
      if (!current() || response == null) return null;
      return request.parse(response);
    }

    try {
      return await run().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (revision == _revision) invalidate();
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
