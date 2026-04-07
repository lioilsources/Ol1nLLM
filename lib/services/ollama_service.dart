import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class OllamaService {
  static const _baseUrl = 'https://llm.ol1n.com/api/chat';
  static const _model = 'llm-lab';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  final http.Client _client = http.Client();

  /// Streams assistant content chunks from Ollama.
  Stream<String> chat(List<Message> messages) async* {
    final request = http.Request('POST', Uri.parse(_baseUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    });
    request.body = jsonEncode({
      'model': _model,
      'messages': messages.map((m) => m.toOllamaJson()).toList(),
      'stream': true,
    });

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Ollama error ${response.statusCode}: $body');
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lineStream) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final done = json['done'] as bool? ?? false;
        if (done) break;
        final content =
            (json['message'] as Map<String, dynamic>?)?['content'] as String?;
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
