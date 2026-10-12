import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/online_recognition.dart';

abstract class OnlineRecognitionTransport {
  Future<String?> send(String body, String apiKey);
  void cancel();
}

/// One reusable instance per editor; every send owns a fresh HTTP client.
class HttpOnlineRecognitionTransport implements OnlineRecognitionTransport {
  HttpOnlineRecognitionTransport({
    Uri? endpoint,
    HttpClient Function()? clientFactory,
  }) : endpoint =
           endpoint ??
           Uri.parse('https://api.xiaomimimo.com/v1/chat/completions'),
       _clientFactory = clientFactory ?? HttpClient.new;

  static const deadline = Duration(seconds: 3);
  static const maxResponseBytes = 65536;
  final Uri endpoint;
  final HttpClient Function() _clientFactory;
  _PendingRequest? _pending;

  @override
  Future<String?> send(String body, String apiKey) {
    cancel();
    if (apiKey.trim().isEmpty ||
        utf8.encode(body).length > OnlineRecognitionRequest.maxBytes) {
      return Future.value(null);
    }
    final pending = _PendingRequest();
    _pending = pending;
    pending.timer = Timer(deadline, () => _finish(pending, null));
    unawaited(_perform(pending, body, apiKey));
    return pending.completer.future;
  }

  Future<void> _perform(
    _PendingRequest pending,
    String body,
    String apiKey,
  ) async {
    try {
      final client = pending.client = _clientFactory();
      final request = await client.postUrl(endpoint);
      pending.request = request;
      if (pending.completer.isCompleted) {
        request.abort();
        return;
      }
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set('api-key', apiKey);
      request.add(utf8.encode(body));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > maxResponseBytes) {
        _finish(pending, null);
        return;
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (pending.completer.isCompleted ||
            bytes.length + chunk.length > maxResponseBytes) {
          _finish(pending, null);
          return;
        }
        bytes.addAll(chunk);
      }
      _finish(pending, utf8.decode(bytes));
    } catch (_) {
      // Credentials, request names and provider errors never enter logs.
      _finish(pending, null);
    }
  }

  void _finish(_PendingRequest pending, String? result) {
    pending.timer?.cancel();
    pending.request?.abort();
    pending.client?.close(force: true);
    if (!pending.completer.isCompleted) pending.completer.complete(result);
    if (identical(_pending, pending)) _pending = null;
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending != null) _finish(pending, null);
  }
}

class _PendingRequest {
  final completer = Completer<String?>();
  HttpClient? client;
  HttpClientRequest? request;
  Timer? timer;
}
