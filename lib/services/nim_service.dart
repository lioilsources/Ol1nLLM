import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class NimService {
  static const _baseUrl = 'https://llm.ol1n.com/v1/chat/completions';
  static const _model = 'llm-lab';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _connectTimeout = Duration(seconds: 30);
  static const _streamTimeout = Duration(seconds: 120);

  final http.Client _client = _makeClient();

  static http.Client _makeClient() {
    try {
      if (Platform.isAndroid) return CronetClient.defaultCronetEngine();
    } catch (_) {
      // Cronet unavailable — fall back to dart:io
    }
    return http.Client();
  }

  /// Streams assistant content chunks from NIM via LiteLLM.
  Stream<String> chat(List<Message> messages) async* {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }

    final request = http.Request('POST', Uri.parse(_baseUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer dummy',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': messages.map((m) => m.toOllamaJson()).toList(),
      'stream': true,
      'temperature': 0.7,
      'max_tokens': 1024,
    });

    final response = await _client.send(request).timeout(_connectTimeout);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      final diagHeaders = response.headers.entries
          .where((e) => const {
                'server',
                'cf-ray',
                'x-powered-by',
                'content-type',
              }.contains(e.key.toLowerCase()))
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      final bodySnippet =
          body.isNotEmpty ? body.replaceAll(RegExp(r'\s+'), ' ').trim() : '';
      final truncated =
          bodySnippet.length > 120 ? '${bodySnippet.substring(0, 120)}…' : bodySnippet;
      throw Exception(
        'HTTP ${response.statusCode}'
        '${truncated.isNotEmpty ? ": $truncated" : ""}'
        '${diagHeaders.isNotEmpty ? " [$diagHeaders]" : ""}',
      );
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_streamTimeout);

    await for (final line in lineStream) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
      final payload = trimmed.substring(6);
      if (payload == '[DONE]') break;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final delta = ((json['choices'] as List?)?.first
            as Map<String, dynamic>?)?['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // Skip malformed lines
      }
    }
  }

  void dispose() => _client.close();
}
