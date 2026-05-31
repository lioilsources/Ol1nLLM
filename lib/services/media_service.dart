import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
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
    final url = '$_baseUrl$path';
    debugPrint('[media] POST $url');
    final response = await _client
        .post(
          Uri.parse(url),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_submitTimeout);
    debugPrint('[media] POST $path → ${response.statusCode}');
    if (response.statusCode != 202) {
      final snippet = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated =
          snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
      debugPrint('[media] error body: $truncated');
      throw Exception(
        'HTTP ${response.statusCode}${truncated.isNotEmpty ? ": $truncated" : ""}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = json['id'] as String;
    debugPrint('[media] job_id=$jobId');
    return jobId;
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
      } catch (e) {
        debugPrint('[media] poll network error: $e — retrying');
        continue;
      }

      if (response.statusCode == 404) {
        debugPrint('[media] poll $jobId → 404 expired');
        yield JobExpired();
        return;
      }
      if (response.statusCode != 200) {
        debugPrint('[media] poll $jobId → ${response.statusCode} retrying');
        continue;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String;
      switch (status) {
        case 'queued':
          final pos = json['queue_position'] as int? ?? 0;
          debugPrint('[media] poll $jobId → queued pos=$pos');
          yield JobQueued(pos);
        case 'running':
          final step = json['step'] as int? ?? 0;
          final total = json['total'] as int? ?? 1;
          debugPrint('[media] poll $jobId → running $step/$total');
          yield JobRunning(step, total);
        case 'done':
          final data = json['data'] as List;
          final images = data
              .map((e) => (e as Map<String, dynamic>)['b64_json'] as String)
              .toList();
          debugPrint('[media] poll $jobId → done (${images.length} image(s))');
          yield JobDone(images);
          return;
        case 'error':
          final msg = json['error'] as String? ?? 'Unknown error';
          debugPrint('[media] poll $jobId → error: $msg');
          yield JobFailed(msg);
          return;
        default:
          debugPrint('[media] poll $jobId → unknown status "$status"');
      }
    }
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
