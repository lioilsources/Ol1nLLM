import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks to the AiStack gateway at llm.ol1n.com. Image generation/editing has
/// moved to ComfyUI ([ComfyUIService]); this service now only carries OCR.
///
/// OCR is served by Qwen2.5-VL (a VLM) via vLLM as the LiteLLM model `ocr`, so
/// it's a normal OpenAI `/v1/chat/completions` call with an image content part
/// (the nemotron-ocr NIM doesn't run on the GB10/arm64 host).
class MediaService {
  static const _baseUrl = 'https://llm.ol1n.com';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _ocrTimeout = Duration(seconds: 120);
  static const _ocrModel = 'ocr';

  /// Instruction sent alongside the image. Keep it strict so the model returns
  /// only the transcription, not a description.
  static const _ocrPrompt =
      'Přepiš veškerý text z tohoto obrázku přesně tak, jak je. Zachovej '
      'řádkování a pořadí. Vrať pouze přepsaný text, bez jakýchkoli komentářů, '
      'popisů nebo formátovacích značek. Neopakuj řádky. Pokud na obrázku není '
      'žádný text, vrať prázdnou odpověď.';

  final http.Client _client = _makeClient();

  static http.Client _makeClient() => http.Client();

  Map<String, String> get _headers {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }
    return {
      'Content-Type': 'application/json',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    };
  }

  /// OCR via the Qwen2.5-VL `ocr` model. Sends the image as a base64 data URL in
  /// a chat/completions request and returns the transcribed text. Synchronous.
  Future<String> ocr({required Uint8List imageBytes}) async {
    final mime = _sniffMime(imageBytes);
    final dataUrl = 'data:$mime;base64,${base64Encode(imageBytes)}';
    debugPrint('[media] POST /v1/chat/completions model=ocr (${imageBytes.length} B, $mime)');
    final body = <String, dynamic>{
      'model': _ocrModel,
      // Mírná teplota + penalty proti zacyklení Qwenu na tabulkových/matričních
      // skenech (greedy dekódování jinak opakuje řádky). TrOCR modely je ignorují.
      'temperature': 0.1,
      'max_tokens': 1500,
      'frequency_penalty': 0.6,
      'presence_penalty': 0.4,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _ocrPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
    };
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/v1/chat/completions'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_ocrTimeout);
    debugPrint('[media] OCR → ${response.statusCode}');
    if (response.statusCode != 200) {
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated = snippet.length > 160
          ? '${snippet.substring(0, 160)}…'
          : snippet;
      throw Exception(
        'HTTP ${response.statusCode}${truncated.isNotEmpty ? ": $truncated" : ""}',
      );
    }
    return _extractContent(jsonDecode(response.body));
  }

  /// Pull the assistant message text out of an OpenAI chat/completions response.
  static String _extractContent(dynamic decoded) {
    if (decoded is! Map) return '';
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    return content is String ? content.trim() : '';
  }

  /// Detect PNG vs JPEG from the magic bytes; default to JPEG (image_picker
  /// re-encodes to JPEG when imageQuality is set).
  static String _sniffMime(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  void dispose() => _client.close();
}
