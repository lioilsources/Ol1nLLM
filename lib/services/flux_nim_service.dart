import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_error.dart';
import 'image_backend.dart';

/// Calls the FLUX Schnell async job queue exposed by gen-queue at
/// /nim/flux-schnell/v1/infer (202 + job_id), polls status, and downloads
/// the PNG result when done.
///
/// gen-queue wraps the synchronous NIM /v1/infer call so the Cloudflare 100 s
/// edge timeout is never hit and jobs survive iOS app suspension (follow() works).
class FluxNimService implements ImageBackend {
  FluxNimService();

  static const _baseUrl = String.fromEnvironment(
    'FLUX_NIM_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _submitTimeout   = Duration(seconds: 30);
  static const _pollInterval    = Duration(seconds: 3);
  static const _pollTimeout     = Duration(seconds: 15);
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
  String get id => kBackendFluxNim;

  @override
  String get label => 'FLUX NIM';

  @override
  int get variantCount => 1;

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    yield* _infer(prompt: prompt, n: n);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield const GenFailed('[FLUX NIM] tento model podporuje pouze txt2img. Pro img2img použijte FLUX Kontext nebo ComfyUI.');
  }

  Stream<GenEvent> _infer({required String prompt, required int n}) async* {
    final images = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      var step = 'submit';
      var currentTimeout = _submitTimeout;
      String? currentJobId;
      try {
        // ── 1. Submit ──────────────────────────────────────────
        final bodyMap = {
          'prompt': prompt,
          'width': 1024,
          'height': 1024,
          'steps': 4,
          'seed': Random().nextInt(1 << 31),
        };

        final submitResp = await _client
            .post(
              Uri.parse('$_baseUrl/nim/flux-schnell/v1/infer'),
              headers: _authHeaders,
              body: jsonEncode(bodyMap),
            )
            .timeout(_submitTimeout);

        if (submitResp.statusCode != 202) {
          yield GenFailed(HttpLayerError.parse(
            statusCode: submitResp.statusCode,
            body: submitResp.body,
            headers: submitResp.headers,
            step: 'submit',
            service: 'flux-nim',
          ).toString());
          return;
        }

        final submitted = jsonDecode(submitResp.body) as Map<String, dynamic>;
        final jobId = submitted['id'] as String;
        currentJobId = jobId;
        final qpos  = submitted['queue_position'] as int? ?? 0;
        yield GenSubmitted(jobId);
        yield GenQueued(qpos);

        // ── 2. Poll until done ─────────────────────────────────
        step = 'poll';
        currentTimeout = _pollTimeout;
        while (true) {
          await Future.delayed(_pollInterval);

          final pollResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-schnell/jobs/$jobId'),
                headers: _authHeaders,
              )
              .timeout(_pollTimeout);

          if (pollResp.statusCode == 404) {
            yield const GenFailed(
              '[gen-queue] job nenalezen – queue byl restartován? Zkus generovat znovu.',
            );
            return;
          }
          if (pollResp.statusCode != 200) {
            yield GenFailed(HttpLayerError.parse(
              statusCode: pollResp.statusCode,
              body: pollResp.body,
              headers: pollResp.headers,
              step: 'poll',
              service: 'flux-nim',
            ).toString());
            return;
          }

          final p      = jsonDecode(pollResp.body) as Map<String, dynamic>;
          final status = p['status'] as String;

          if (status == 'queued') {
            yield GenQueued(p['queue_position'] as int? ?? 0);
          } else if (status == 'running') {
            // NIM Schnell je synchronní — gen-queue nevidí per-step progress.
            yield const GenRunning(0, 0);
          } else if (status == 'done') {
            break;
          } else if (status == 'error') {
            final jobErr = (p['error'] as String?) ?? 'neznámá chyba';
            yield GenFailed(HttpLayerError.parseJobError(jobErr));
            return;
          }
        }

        // ── 3. Download result ─────────────────────────────────
        step = 'download';
        currentTimeout = _downloadTimeout;
        yield GenDownloading(i, n);
        final resultResp = await _client
            .get(
              Uri.parse('$_baseUrl/nim/flux-schnell/jobs/$jobId/result'),
              headers: _authHeaders,
            )
            .timeout(_downloadTimeout);

        if (resultResp.statusCode != 200) {
          yield GenFailed(HttpLayerError.parse(
            statusCode: resultResp.statusCode,
            body: resultResp.body,
            headers: resultResp.headers,
            step: 'download',
            service: 'flux-nim',
          ).toString());
          return;
        }
        images.add(resultResp.bodyBytes);
      } on TimeoutException catch (e) {
        // Suspend/network blip mid-poll: the job is still alive server-side,
        // so signal a resumable interruption instead of a hard failure.
        if (currentJobId != null) {
          yield GenInterrupted(currentJobId);
          return;
        }
        yield GenFailed(
          HttpLayerError.fromException(
            e,
            step,
            'flux-nim',
            timeout: currentTimeout,
          ).toString(),
        );
        return;
      } on SocketException catch (e) {
        if (currentJobId != null) {
          yield GenInterrupted(currentJobId);
          return;
        }
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-nim').toString(),
        );
        return;
      } catch (e) {
        // iOS suspend kills the socket as http.ClientException / HttpException
        // (not Socket/Timeout). With a known jobId it's resumable, not fatal.
        if (currentJobId != null) {
          yield GenInterrupted(currentJobId);
          return;
        }
        yield GenFailed(
          HttpLayerError.fromException(e, step, 'flux-nim').toString(),
        );
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
              Uri.parse('$_baseUrl/nim/flux-schnell/jobs/$jobId'),
              headers: _authHeaders,
            )
            .timeout(_pollTimeout);

        if (pollResp.statusCode == 404) {
          yield const GenFailed(
            '[gen-queue] job nenalezen – queue byl restartován? Zkus generovat znovu.',
          );
          return;
        }
        if (pollResp.statusCode != 200) {
          yield GenFailed(HttpLayerError.parse(
            statusCode: pollResp.statusCode,
            body: pollResp.body,
            headers: pollResp.headers,
            step: 'poll',
            service: 'flux-nim',
          ).toString());
          return;
        }

        final p      = jsonDecode(pollResp.body) as Map<String, dynamic>;
        final status = p['status'] as String;

        if (status == 'queued') {
          yield GenQueued(p['queue_position'] as int? ?? 0);
        } else if (status == 'running') {
          yield const GenRunning(0, 0);
        } else if (status == 'done') {
          final resultResp = await _client
              .get(
                Uri.parse('$_baseUrl/nim/flux-schnell/jobs/$jobId/result'),
                headers: _authHeaders,
              )
              .timeout(_downloadTimeout);
          if (resultResp.statusCode != 200) {
            yield GenFailed(HttpLayerError.parse(
              statusCode: resultResp.statusCode,
              body: resultResp.body,
              headers: resultResp.headers,
              step: 'download',
              service: 'flux-nim',
            ).toString());
            return;
          }
          yield GenComplete([resultResp.bodyBytes]);
          return;
        } else if (status == 'error') {
          final jobErr = (p['error'] as String?) ?? 'neznámá chyba';
          yield GenFailed(HttpLayerError.parseJobError(jobErr));
          return;
        }
      } catch (_) {
        // Any transport error (Socket/Timeout/ClientException on iOS suspend):
        // the job keeps running server-side, so resume instead of failing.
        yield GenInterrupted(jobId);
        return;
      }
    }
  }

  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _client.close();
}
