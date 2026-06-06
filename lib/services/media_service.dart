import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks to the AiStack gateway at llm.ol1n.com. Image generation/editing has
/// moved to ComfyUI ([ComfyUIService]); this service now only carries OCR.
class MediaService {
  static const _baseUrl = 'https://llm.ol1n.com';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _ocrTimeout = Duration(seconds: 90);

  final http.Client _client = _makeClient();

  static http.Client _makeClient() {
    try {
      if (Platform.isAndroid) return CronetClient.defaultCronetEngine();
    } catch (_) {}
    return http.Client();
  }

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

  /// OCR — synchronous, quick endpoint (no job model).
  Future<String> ocr({
    required String imageBase64,
    String? prompt,
    int maxNewTokens = 2048,
  }) async {
    debugPrint('[media] POST /v1/ocr');
    final body = <String, dynamic>{
      'image': imageBase64,
      'max_new_tokens': maxNewTokens,
      if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
    };
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/v1/ocr'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_ocrTimeout);
    debugPrint('[media] POST /v1/ocr → ${response.statusCode}');
    if (response.statusCode != 200) {
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated =
          snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
      throw Exception(
        'HTTP ${response.statusCode}${truncated.isNotEmpty ? ": $truncated" : ""}',
      );
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['text']
            as String? ??
        '';
  }

  void dispose() => _client.close();
}
