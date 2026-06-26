import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'image_backend.dart';

const kBackendFluxKontextNim = 'flux_kontext_nim';

/// Calls the async FLUX.1-Kontext NIM wrapper in image-api.
///
/// POST /nim/flux-kontext/v1/infer → 202 + job_id (returns before the NIM
/// finishes, so the Cloudflare 100 s edge timeout is never hit).
/// Client then polls GET /nim/flux-kontext/jobs/{id} and downloads the PNG from
/// GET /nim/flux-kontext/jobs/{id}/result once status == "done".
///
/// The Cloudflare tunnel must route llm.ol1n.com/nim/flux-kontext/* to
/// nim-kontext-proxy:8004 (not directly to the NIM container).
class FluxKontextNimService implements ImageBackend {
  FluxKontextNimService();

  static const _baseUrl = String.fromEnvironment(
    'FLUX_KONTEXT_NIM_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _submitTimeout = Duration(seconds: 30);
  static const _pollInterval = Duration(seconds: 3);
  static const _pollTimeout = Duration(seconds: 15);
  static const _downloadTimeout = Duration(seconds: 120);

  final http.Client _client = http.Client();

  Map<String, String> get _authHeaders {
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

  @override
  String get id => kBackendFluxKontextNim;

  @override
  String get label => 'FLUX Kontext';

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    yield* _infer(prompt: prompt, imageB64: null, n: n);
  }

  // Dimensions supported by the Kontext TRT buffer. Input images must use
  // values from this set on both axes to avoid tensor size mismatch errors.
  static const _supportedDims = [
    672, 688, 720, 752, 800, 832, 880, 944, 1024,
    1104, 1184, 1248, 1328, 1392, 1456, 1504, 1568,
  ];

  static int _snap(int v) => _supportedDims.reduce(
        (a, b) => (a - v).abs() <= (b - v).abs() ? a : b,
      );

  static Uint8List _snapImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final sw = _snap(decoded.width);
    final sh = _snap(decoded.height);
    if (sw == decoded.width && sh == decoded.height) return bytes;
    final resized = img.copyResize(decoded, width: sw, height: sh,
        interpolation: img.Interpolation.cubic);
    return Uint8List.fromList(img.encodePng(resized));
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield* _infer(prompt: prompt, imageB64: base64Encode(_snapImage(image)), n: n);
  }

  Stream<GenEvent> _infer({
    required String prompt,
    required String? imageB64,
    required int n,
  }) async* {
    final images = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      try {
        // ── 1. Submit ──────────────────────────────────────────
        final bodyMap = <String, dynamic>{
          'prompt': prompt,
          'aspect_ratio': imageB64 != null ? 'match_input_image' : '1:1',
          'cfg_scale': 3.5,
          'steps': 30,
          'seed': Random().nextInt(1 << 31),
        };
        if (imageB64 != null) {
          bodyMap['image'] = 'data:image/png;base64,$imageB64';
        }

        final submitResp = await _client
            .post(
              Uri.parse('$_baseUrl/nim/flux-kontext/v1/infer'),
              headers: _authHeaders,
              body: jsonEncode(bodyMap),
            )
            .timeout(_submitTimeout);

        if (submitResp.statusCode != 202) {
          yield GenFailed('Kontext NIM chyba ${submitResp.statusCode}: ${submitResp.body}');
          return;
        }

        final submitted = jsonDecode(submitResp.body) as Map<String, dynamic>;
        final jobId = submitted['id'] as String;
        yield GenSubmitted(jobId);
        yield GenQueued(submitted['queue_position'] as int? ?? 0);

        // ── 2. Poll until done ─────────────────────────────────
        while (true) {
          await Future.delayed(_pollInterval);

          final pollResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId'),
                headers: _authHeaders,
              )
              .timeout(_pollTimeout);

          if (pollResp.statusCode != 200) {
            yield GenFailed('Kontext NIM poll chyba ${pollResp.statusCode}');
            return;
          }

          final p = jsonDecode(pollResp.body) as Map<String, dynamic>;
          final status = p['status'] as String;

          if (status == 'queued') {
            yield GenQueued(p['queue_position'] as int? ?? 0);
          } else if (status == 'running') {
            final step = p['step'] as int? ?? 0;
            final total = p['total'] as int? ?? 0;
            yield GenRunning(step, total);
          } else if (status == 'done') {
            break;
          } else if (status == 'error') {
            yield GenFailed('Kontext NIM chyba: ${p['error']}');
            return;
          }
        }

        // ── 3. Download result ─────────────────────────────────
        yield GenDownloading(i, n);
        final resultResp = await _client
            .get(
              Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId/result'),
              headers: _authHeaders,
            )
            .timeout(_downloadTimeout);

        if (resultResp.statusCode != 200) {
          yield GenFailed('Kontext NIM stahování chyba ${resultResp.statusCode}');
          return;
        }
        images.add(resultResp.bodyBytes);
      } catch (e) {
        yield GenFailed('Kontext NIM chyba: $e');
        return;
      }
    }
    yield GenComplete(images);
  }

  @override
  Stream<GenEvent> follow(String jobId) async* {
    yield GenSubmitted(jobId);
    while (true) {
      await Future.delayed(_pollInterval);
      try {
        final pollResp = await _client
            .get(
              Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId'),
              headers: _authHeaders,
            )
            .timeout(_pollTimeout);

        if (pollResp.statusCode == 404) {
          yield const GenFailed('Job expiroval nebo nebyl nalezen');
          return;
        }
        if (pollResp.statusCode != 200) {
          yield GenFailed('Kontext NIM poll chyba ${pollResp.statusCode}');
          return;
        }

        final p = jsonDecode(pollResp.body) as Map<String, dynamic>;
        final status = p['status'] as String;

        if (status == 'queued') {
          yield GenQueued(p['queue_position'] as int? ?? 0);
        } else if (status == 'running') {
          final step = p['step'] as int? ?? 0;
          final total = p['total'] as int? ?? 0;
          yield GenRunning(step, total);
        } else if (status == 'done') {
          final resultResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId/result'),
                headers: _authHeaders,
              )
              .timeout(_downloadTimeout);
          if (resultResp.statusCode != 200) {
            yield GenFailed('Kontext NIM stahování chyba ${resultResp.statusCode}');
            return;
          }
          yield GenComplete([resultResp.bodyBytes]);
          return;
        } else if (status == 'error') {
          yield GenFailed('Kontext NIM chyba: ${p['error']}');
          return;
        }
      } catch (e) {
        yield GenFailed('Kontext NIM chyba: $e');
        return;
      }
    }
  }

  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _client.close();
}
