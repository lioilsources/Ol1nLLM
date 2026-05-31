import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

/// Calls the ai-stack gateway image + OCR endpoints (non-streaming JSON).
///
/// The two image flows are split by endpoint, not by a `model` field:
/// `/v1/images/generations` runs FLUX (text→image), `/v1/images/edits` runs
/// Qwen-Image-Edit (image+prompt). The gateway returns HTTP 503 when the
/// requested pipeline is not loaded.
class MediaService {
  static const _baseUrl = 'https://llm.ol1n.com';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  // Image generation/editing can take a while; OCR is quicker.
  static const _imageTimeout = Duration(seconds: 180);
  static const _ocrTimeout = Duration(seconds: 90);

  final http.Client _client = _makeClient();

  static http.Client _makeClient() {
    try {
      if (Platform.isAndroid) return CronetClient.defaultCronetEngine();
    } catch (_) {
      // Cronet unavailable — fall back to dart:io
    }
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
      'Authorization': 'Bearer dummy',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    };
  }

  /// FLUX text→image. Returns base64-encoded PNG(s).
  Future<List<String>> generateImage({
    required String prompt,
    int n = 1,
    String size = '1024x1024',
    int? steps,
  }) async {
    final body = <String, dynamic>{
      'prompt': prompt,
      'n': n,
      'size': size,
      'response_format': 'b64_json',
      'model': 'flux-1-dev',
      if (steps != null) 'num_inference_steps': steps,
    };
    final json = await _post('/v1/images/generations', body, _imageTimeout);
    return _extractImages(json);
  }

  /// Qwen-Image-Edit: edit [imageBase64] according to [prompt].
  Future<List<String>> editImage({
    required String imageBase64,
    required String prompt,
    int n = 1,
    String size = '1024x1024',
    int? steps,
  }) async {
    final body = <String, dynamic>{
      'image': imageBase64,
      'prompt': prompt,
      'n': n,
      'size': size,
      'response_format': 'b64_json',
      'model': 'qwen-image-edit',
      if (steps != null) 'num_inference_steps': steps,
    };
    final json = await _post('/v1/images/edits', body, _imageTimeout);
    return _extractImages(json);
  }

  /// OCR: extract text from [imageBase64].
  Future<String> ocr({
    required String imageBase64,
    String? languageHint,
    int maxNewTokens = 2048,
    String? prompt,
  }) async {
    final body = <String, dynamic>{
      'image': imageBase64,
      'max_new_tokens': maxNewTokens,
      if (languageHint != null) 'language_hint': languageHint,
      if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
    };
    final json = await _post('/v1/ocr', body, _ocrTimeout);
    return (json['text'] as String?) ?? '';
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated =
          snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
      throw Exception(
        'HTTP ${response.statusCode}${truncated.isNotEmpty ? ": $truncated" : ""}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static List<String> _extractImages(Map<String, dynamic> json) {
    final data = json['data'] as List?;
    if (data == null || data.isEmpty) {
      throw Exception('No image returned by server');
    }
    return data
        .map((e) => (e as Map<String, dynamic>)['b64_json'] as String?)
        .whereType<String>()
        .toList();
  }

  void dispose() => _client.close();
}
