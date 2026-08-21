import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import 'chat_backend.dart';
import 'http_error.dart';

/// Default chat backend: the AiStack LiteLLM gateway, OpenAI-compatible SSE.
/// Stateless — the whole branch goes up on every turn.
class VllmService extends ChatBackend {
  static const _baseUrl = String.fromEnvironment(
    'VLLM_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _model = 'lab';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _connectTimeout = Duration(seconds: 30);
  static const _streamTimeout = Duration(seconds: 120);

  final http.Client _client = _makeClient();

  static http.Client _makeClient() => http.Client();

  @override
  String get id => 'vllm';

  /// Streams assistant events (deltas + a final ChatDone with finish_reason)
  /// from the vLLM OpenAI-compatible endpoint.
  ///
  /// [remoteSessionId] is ignored — this endpoint keeps no server-side state.
  @override
  Stream<ChatEvent> chat(
    List<Message> thread, {
    String? systemPrompt,
    String? remoteSessionId,
  }) async* {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }

    final payload = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...thread.map((m) => m.toOllamaJson()),
    ];

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/v1/chat/completions'),
    );
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer dummy',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': payload,
      'stream': true,
      'temperature': 0.7,
      'max_tokens': 4096,
    });

    final response = await _client.send(request).timeout(_connectTimeout);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      final err = HttpLayerError.parse(
        statusCode: response.statusCode,
        body: body,
        headers: response.headers,
        step: 'chat',
        service: 'vllm',
      );
      throw Exception(err.toString());
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_streamTimeout);

    String? finishReason;
    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
      final payload = trimmed.substring(6);
      if (payload == '[DONE]') break;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final errorField = json['error'];
        if (errorField != null) {
          final msg = errorField is Map
              ? '${errorField['message'] ?? errorField}'
              : errorField.toString();
          debugPrint('[vllm] SSE error event: $msg');
          throw Exception(msg);
        }
        final choice =
            (json['choices'] as List?)?.first as Map<String, dynamic>?;
        final content =
            (choice?['delta'] as Map<String, dynamic>?)?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield ChatDelta(content);
        }
        final fr = choice?['finish_reason'];
        if (fr is String) finishReason = fr;
      } catch (e) {
        if (e is Exception) rethrow;
        // Skip malformed JSON lines
      }
    }
    yield ChatDone(finishReason);
  }

  @override
  void dispose() => _client.close();
}
