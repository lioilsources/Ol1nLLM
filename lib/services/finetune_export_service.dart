import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, SocketException;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/gen_node.dart';
import '../models/image_session.dart';
import 'http_error.dart';

/// Result of one [FinetuneExportService.exportSession] run.
class ExportSummary {
  final int images;
  final int newBlobs;
  const ExportSummary({required this.images, required this.newBlobs});
}

/// Pushes a session (its generation tree + PNGs) to the FINETUNE gallery
/// backend on the NAS, where outputs are rated and turned into LoRA datasets.
///
/// Two-phase, content-addressed protocol — idempotent, so re-exporting a
/// session that grew since the last export uploads only the new images, and an
/// interrupted export resumes where it died:
///   1. POST /api/ingest/manifest   — session + nodes + per-image sha256
///                                    → {"needed": [sha…]} (blobs the server lacks)
///   2. PUT  /api/ingest/images/{sha} — raw PNG body, one per needed blob,
///                                    with the same transient-retry semantics
///                                    as ComfyUIService._uploadImage
///   3. POST /api/ingest/sessions/{id}/finalize → {"images": N, "newBlobs": M}
class FinetuneExportService {
  FinetuneExportService();

  static const _baseUrl = String.fromEnvironment(
    'FINETUNE_URL',
    defaultValue: 'https://finetune.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _submitTimeout = Duration(seconds: 30);
  // Blobs are full PNGs (bigger than ComfyUI pose/input uploads) — allow more.
  static const _uploadTimeout = Duration(seconds: 60);
  static const _uploadMaxAttempts = 3;

  final http.Client _client = http.Client();

  Map<String, String> get _authHeaders {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }
    return {'CF-Access-Client-Id': _cfId, 'CF-Access-Client-Secret': _cfSecret};
  }

  Map<String, String> get _jsonHeaders => {
    ..._authHeaders,
    'Content-Type': 'application/json',
  };

  /// Export [session]'s ready nodes. [onProgress] reports blob uploads
  /// (done/total of *missing* blobs — 0/0 when the server already has all).
  Future<ExportSummary> exportSession(
    ImageSession session, {
    void Function(int done, int total)? onProgress,
  }) async {
    // ── Build the manifest, hashing image files one at a time.
    // Files are read via File directly (not GenImage.bytes) so the bytes are
    // not cached on the long-lived GenImage instances — a large session would
    // otherwise pin tens of MB in memory after the export.
    final shaToPath = <String, String>{};
    final nodesJson = <Map<String, dynamic>>[];
    var imageCount = 0;
    for (final node in session.nodes) {
      if (node.status != GenStatus.ready) continue;
      final imagesJson = <Map<String, dynamic>>[];
      for (var i = 0; i < node.images.length; i++) {
        final img = node.images[i];
        Uint8List bytes;
        try {
          bytes = await File(img.filePath).readAsBytes();
        } catch (e) {
          debugPrint('[finetune] skipping unreadable ${img.fileName}: $e');
          continue;
        }
        final sha = sha256.convert(bytes).toString();
        shaToPath[sha] = img.filePath;
        imagesJson.add({
          'id': img.id,
          'sha256': sha,
          'size': bytes.length,
          'idx': i,
        });
        imageCount++;
      }
      // Node metadata rides on GenNode.toJson so future fields flow through;
      // runtime-only / server-irrelevant keys are stripped.
      final nj = node.toJson()
        ..remove('images')
        ..remove('status')
        ..remove('error')
        ..remove('jobId')
        ..['images'] = imagesJson;
      nodesJson.add(nj);
    }

    final manifest = {
      'session': {
        'id': session.id,
        'title': session.title,
        'modelId': session.modelId,
        'updatedAt': session.updatedAt.toIso8601String(),
      },
      'nodes': nodesJson,
    };

    // ── 1. Manifest → which blobs the server is missing.
    final manifestResp = await _client
        .post(
          Uri.parse('$_baseUrl/api/ingest/manifest'),
          headers: _jsonHeaders,
          body: jsonEncode(manifest),
        )
        .timeout(_submitTimeout);
    if (manifestResp.statusCode != 200) {
      throw Exception(HttpLayerError.parse(
        statusCode: manifestResp.statusCode,
        body: manifestResp.body,
        headers: manifestResp.headers,
        step: 'manifest',
        service: 'finetune',
      ).toString());
    }
    final needed =
        (((jsonDecode(manifestResp.body) as Map<String, dynamic>)['needed']
                    as List?) ??
                const [])
            .cast<String>();

    // ── 2. Upload missing blobs (re-read from disk, one at a time).
    var done = 0;
    onProgress?.call(0, needed.length);
    for (final sha in needed) {
      final path = shaToPath[sha];
      if (path == null) continue; // server asked for a hash we didn't offer
      await _uploadBlob(sha, await File(path).readAsBytes());
      onProgress?.call(++done, needed.length);
    }

    // ── 3. Finalize.
    final finalizeResp = await _client
        .post(
          Uri.parse('$_baseUrl/api/ingest/sessions/${session.id}/finalize'),
          headers: _jsonHeaders,
          body: '{}',
        )
        .timeout(_submitTimeout);
    if (finalizeResp.statusCode != 200) {
      throw Exception(HttpLayerError.parse(
        statusCode: finalizeResp.statusCode,
        body: finalizeResp.body,
        headers: finalizeResp.headers,
        step: 'finalize',
        service: 'finetune',
      ).toString());
    }
    final fin = jsonDecode(finalizeResp.body) as Map<String, dynamic>;
    return ExportSummary(
      images: (fin['images'] as int?) ?? imageCount,
      newBlobs: (fin['newBlobs'] as int?) ?? needed.length,
    );
  }

  /// PUT one PNG blob, retrying transient network failures like
  /// ComfyUIService._uploadImage (3 attempts, linear backoff; non-2xx is a
  /// hard server rejection and fails immediately).
  Future<void> _uploadBlob(String sha, Uint8List bytes) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= _uploadMaxAttempts; attempt++) {
      try {
        final resp = await _client
            .put(
              Uri.parse('$_baseUrl/api/ingest/images/$sha'),
              headers: {..._authHeaders, 'Content-Type': 'image/png'},
              body: bytes,
            )
            .timeout(_uploadTimeout);
        debugPrint(
          '[finetune] PUT blob ${sha.substring(0, 8)}… → ${resp.statusCode} '
          '(pokus $attempt/$_uploadMaxAttempts)',
        );
        if (resp.statusCode != 200 && resp.statusCode != 201) {
          throw Exception(HttpLayerError.parse(
            statusCode: resp.statusCode,
            body: resp.body,
            headers: resp.headers,
            step: 'upload',
            service: 'finetune',
          ).toString());
        }
        return;
      } on SocketException catch (e) {
        lastErr = e;
      } on TimeoutException catch (e) {
        lastErr = e;
      } on http.ClientException catch (e) {
        lastErr = e;
      }
      debugPrint('[finetune] upload pokus $attempt selhal: $lastErr');
      if (attempt < _uploadMaxAttempts) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    throw Exception(
      '[Finetune] nahrání obrázku selhalo po $_uploadMaxAttempts pokusech '
      '(síť/Wi-Fi): $lastErr',
    );
  }

  void dispose() => _client.close();
}
