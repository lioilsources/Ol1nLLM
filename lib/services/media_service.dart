import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

sealed class JobStatus {}

class JobQueued extends JobStatus {
  final int position;
  JobQueued(this.position);
}

class JobRunning extends JobStatus {
  final int step;
  final int total;
  JobRunning(this.step, this.total);
}

class JobDone extends JobStatus {
  final List<String> images; // base64 strings
  JobDone(this.images);
}

class JobFailed extends JobStatus {
  final String message;
  JobFailed(this.message);
}

class JobExpired extends JobStatus {}

class MediaService {
  static const _baseUrl = 'https://llm.ol1n.com';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _submitTimeout = Duration(seconds: 30);
  static const _ocrTimeout = Duration(seconds: 90);
  static const _pollTimeout = Duration(seconds: 15);
  static const _pollInterval = Duration(seconds: 2);

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

  /// Submit a text→image generation job. Returns the job id.
  Future<String> submitGeneration({
    required String prompt,
    int n = 1,
    String size = '1024x1024',
  }) =>
      _submitJob('/v1/images/generations', {
        'prompt': prompt,
        'n': n,
        'size': size,
      });

  /// Submit an image-edit job. Returns the job id.
  Future<String> submitEdit({
    required String imageBase64,
    required String prompt,
    int n = 1,
    String size = '1024x1024',
  }) =>
      _submitJob('/v1/images/edits', {
        'image': imageBase64,
        'prompt': prompt,
        'n': n,
        'size': size,
      });

  Future<String> _submitJob(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_submitTimeout);
    if (response.statusCode != 202) {
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated =
          snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
      throw Exception(
        'HTTP ${response.statusCode}${truncated.isNotEmpty ? ": $truncated" : ""}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  /// Poll a job until it reaches a terminal state.
  /// Yields status updates; on network errors retries silently.
  Stream<JobStatus> pollJob(String jobId) async* {
    while (true) {
      await Future.delayed(_pollInterval);

      http.Response response;
      try {
        response = await _client
            .get(
              Uri.parse('$_baseUrl/v1/images/jobs/$jobId'),
              headers: _headers,
            )
            .timeout(_pollTimeout);
      } catch (_) {
        continue; // network hiccup — retry
      }

      if (response.statusCode == 404) {
        yield JobExpired();
        return;
      }
      if (response.statusCode != 200) {
        continue; // transient server error — retry
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      switch (json['status'] as String) {
        case 'queued':
          yield JobQueued(json['queue_position'] as int? ?? 0);
        case 'running':
          yield JobRunning(
            json['step'] as int? ?? 0,
            json['total'] as int? ?? 1,
          );
        case 'done':
          final data = json['data'] as List;
          final images = data
              .map((e) => (e as Map<String, dynamic>)['b64_json'] as String)
              .toList();
          yield JobDone(images);
          return;
        case 'error':
          yield JobFailed(json['error'] as String? ?? 'Unknown error');
          return;
      }
    }
  }

  /// OCR — synchronous, quick endpoint (no job model).
  Future<String> ocr({
    required String imageBase64,
    String? prompt,
    int maxNewTokens = 2048,
  }) async {
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
