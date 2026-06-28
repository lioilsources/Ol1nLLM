import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'http_error.dart';
import 'image_backend.dart';

const kBackendFluxKontextNim = 'flux_kontext_nim';

/// Calls the async FLUX.1-Kontext NIM wrapper in gen-queue.
///
/// POST /nim/flux-kontext/v1/infer → 202 + job_id (returns before the NIM
/// finishes, so the Cloudflare 100 s edge timeout is never hit).
/// Client then polls GET /nim/flux-kontext/jobs/{id} and downloads the PNG from
/// GET /nim/flux-kontext/jobs/{id}/result once status == "done".
///
/// The Cloudflare tunnel must route llm.ol1n.com/nim/* to gen-queue:8091.
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
  int get variantCount => 1;

  /// FLUX.1-Kontext is an img2img-only model — the NIM API requires an `image`
  /// field in every request. txt2img is not supported.
  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    yield const GenFailed(
      '[FLUX Kontext] tento model vyžaduje vstupní obrázek (img2img pouze). '
      'Pro generování z textu použijte FLUX Schnell nebo ComfyUI.',
    );
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
    final resized = img.copyResize(
      decoded,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodePng(resized));
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield* _infer(
      prompt: prompt,
      imageB64: base64Encode(_snapImage(image)),
      n: n,
    );
  }

  Stream<GenEvent> _infer({
    required String prompt,
    required String imageB64,
    required int n,
  }) async* {
    final images = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      var step = 'submit';
      var currentTimeout = _submitTimeout;
      try {
        // ── 1. Submit ──────────────────────────────────────────
        final bodyMap = <String, dynamic>{
          'prompt': prompt,
          'image': 'data:image/png;base64,$imageB64',
          'aspect_ratio': 'match_input_image',
          'cfg_scale': 3.5,
          'steps': 30,
          'seed': Random().nextInt(1 << 31),
        };

        debugPrint('[kontext] #${i + 1}/$n submit → POST /nim/flux-kontext/v1/infer');
        final submitResp = await _client
            .post(
              Uri.parse('$_baseUrl/nim/flux-kontext/v1/infer'),
              headers: _authHeaders,
              body: jsonEncode(bodyMap),
            )
            .timeout(_submitTimeout);

        debugPrint('[kontext] submit ← ${submitResp.statusCode} (${submitResp.body.length} B)');
        if (submitResp.statusCode != 202) {
          debugPrint('[kontext] submit error body: ${submitResp.body}');
          yield GenFailed(HttpLayerError.parse(
            statusCode: submitResp.statusCode,
            body: submitResp.body,
            headers: submitResp.headers,
            step: 'submit',
            service: 'flux-kontext',
          ).toString());
          return;
        }

        final submitted = jsonDecode(submitResp.body) as Map<String, dynamic>;
        final jobId = submitted['id'] as String;
        final qpos = submitted['queue_position'] as int? ?? 0;
        debugPrint('[kontext] job=$jobId queue_position=$qpos');
        yield GenSubmitted(jobId);
        yield GenQueued(qpos);

        // ── 2. Poll until done ─────────────────────────────────
        step = 'poll';
        currentTimeout = _pollTimeout;
        while (true) {
          await Future.delayed(_pollInterval);

          final pollResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId'),
                headers: _authHeaders,
              )
              .timeout(_pollTimeout);

          debugPrint('[kontext] poll ← ${pollResp.statusCode} body=${pollResp.body}');
          if (pollResp.statusCode == 404) {
            debugPrint('[kontext] 404 — job=$jobId not found');
            yield const GenFailed(
              '[gen-queue] job nenalezen – queue byl restartován? Zkus generovat znovu.',
            );
            return;
          }
          if (pollResp.statusCode != 200) {
            debugPrint('[kontext] poll error ${pollResp.statusCode}: ${pollResp.body}');
            yield GenFailed(HttpLayerError.parse(
              statusCode: pollResp.statusCode,
              body: pollResp.body,
              headers: pollResp.headers,
              step: 'poll',
              service: 'flux-kontext',
            ).toString());
            return;
          }

          final p = jsonDecode(pollResp.body) as Map<String, dynamic>;
          final status = p['status'] as String;

          if (status == 'queued') {
            yield GenQueued(p['queue_position'] as int? ?? 0);
          } else if (status == 'running') {
            final runStep = p['step'] as int? ?? 0;
            final total = p['total'] as int? ?? 0;
            yield GenRunning(runStep, total);
          } else if (status == 'done') {
            debugPrint('[kontext] job=$jobId done → downloading result');
            break;
          } else if (status == 'error') {
            final jobErr = (p['error'] as String?) ?? 'neznámá chyba';
            debugPrint('[kontext] job=$jobId server error: $jobErr');
            yield GenFailed(HttpLayerError.parseJobError(jobErr));
            return;
          }
        }

        // ── 3. Download result ─────────────────────────────────
        step = 'download';
        currentTimeout = _downloadTimeout;
        yield GenDownloading(i, n);
        debugPrint('[kontext] GET /result job=$jobId');
        final resultResp = await _client
            .get(
              Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId/result'),
              headers: _authHeaders,
            )
            .timeout(_downloadTimeout);

        debugPrint('[kontext] result ← ${resultResp.statusCode} (${resultResp.bodyBytes.length} B)');
        if (resultResp.statusCode != 200) {
          debugPrint('[kontext] result error body: ${resultResp.body}');
          yield GenFailed(HttpLayerError.parse(
            statusCode: resultResp.statusCode,
            body: resultResp.body,
            headers: resultResp.headers,
            step: 'download',
            service: 'flux-kontext',
          ).toString());
          return;
        }
        images.add(resultResp.bodyBytes);
      } on TimeoutException catch (e) {
        debugPrint('[kontext] TIMEOUT step=$step after ${currentTimeout.inSeconds}s');
        yield GenFailed(
          HttpLayerError.fromException(
            e,
            step,
            'flux-kontext',
            timeout: currentTimeout,
          ).toString(),
        );
        return;
      } on SocketException catch (e) {
        debugPrint('[kontext] SocketException step=$step: $e');
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-kontext').toString(),
        );
        return;
      } catch (e) {
        debugPrint('[kontext] exception step=$step: $e');
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-kontext').toString(),
        );
        return;
      }
    }
    debugPrint('[kontext] all $n images done → GenComplete');
    yield GenComplete(images);
  }

  @override
  Stream<GenEvent> follow(String jobId) async* {
    debugPrint('[kontext] follow job=$jobId');
    yield GenSubmitted(jobId);
    var step = 'poll';
    var currentTimeout = _pollTimeout;
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
          debugPrint('[kontext/follow] 404 — job=$jobId not found (TTL expired or proxy restart)');
          yield const GenFailed(
            '[gen-queue] job nenalezen – queue byl restartován? Zkus generovat znovu.',
          );
          return;
        }
        if (pollResp.statusCode != 200) {
          debugPrint('[kontext/follow] poll error ${pollResp.statusCode}: ${pollResp.body}');
          yield GenFailed(HttpLayerError.parse(
            statusCode: pollResp.statusCode,
            body: pollResp.body,
            headers: pollResp.headers,
            step: 'poll',
            service: 'flux-kontext',
          ).toString());
          return;
        }

        debugPrint('[kontext/follow] poll ← ${pollResp.statusCode} body=${pollResp.body}');
        final p = jsonDecode(pollResp.body) as Map<String, dynamic>;
        final status = p['status'] as String;

        if (status == 'queued') {
          yield GenQueued(p['queue_position'] as int? ?? 0);
        } else if (status == 'running') {
          final runStep = p['step'] as int? ?? 0;
          final total = p['total'] as int? ?? 0;
          yield GenRunning(runStep, total);
        } else if (status == 'done') {
          debugPrint('[kontext/follow] done → downloading result');
          step = 'download';
          currentTimeout = _downloadTimeout;
          debugPrint('[kontext/follow] GET /result job=$jobId');
          final resultResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-kontext/jobs/$jobId/result'),
                headers: _authHeaders,
              )
              .timeout(_downloadTimeout);
          debugPrint('[kontext/follow] result ← ${resultResp.statusCode} (${resultResp.bodyBytes.length} B)');
          if (resultResp.statusCode != 200) {
            debugPrint('[kontext/follow] result error: ${resultResp.body}');
            yield GenFailed(HttpLayerError.parse(
              statusCode: resultResp.statusCode,
              body: resultResp.body,
              headers: resultResp.headers,
              step: 'download',
              service: 'flux-kontext',
            ).toString());
            return;
          }
          yield GenComplete([resultResp.bodyBytes]);
          return;
        } else if (status == 'error') {
          final jobErr = (p['error'] as String?) ?? 'neznámá chyba';
          debugPrint('[kontext/follow] server error: $jobErr');
          yield GenFailed(HttpLayerError.parseJobError(jobErr));
          return;
        }
      } on TimeoutException catch (e) {
        debugPrint('[kontext/follow] TIMEOUT step=$step after ${currentTimeout.inSeconds}s');
        yield GenFailed(
          HttpLayerError.fromException(
            e,
            step,
            'flux-kontext',
            timeout: currentTimeout,
          ).toString(),
        );
        return;
      } on SocketException catch (e) {
        debugPrint('[kontext/follow] SocketException step=$step: $e');
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-kontext').toString(),
        );
        return;
      } catch (e) {
        debugPrint('[kontext/follow] exception step=$step: $e');
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-kontext').toString(),
        );
        return;
      }
    }
  }

  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _client.close();
}
