import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/figure_clip.dart';
import 'image_backend.dart';

/// „Tančící figurka" — a still image becomes a rigged, dancing 3D figure via
/// the fantasy-character pipeline of UGCFactory on the NAS
/// (`ugc.ol1n.com/v1/fc`, same Cloudflare Access service token as the rest).
///
/// Server side it is a queue of steps: background removal and TRELLIS mesh on
/// SPARK, then cleanup, rig (template or MIA, whichever deforms less), dance
/// retarget and GLB export in Blender on the NAS — 6–10 minutes. This client
/// only creates the character and polls it, emitting the usual [GenEvent]s so
/// the Image Studio treats it like a 3D mesh round, and finally
/// [GenFigureComplete] with the GLB whose glTF animations are named by clip id.
class FigureService {
  static const _root = String.fromEnvironment(
    'UGC_FC_URL',
    defaultValue: 'https://ugc.ol1n.com',
  );
  static const _baseUrl = '$_root/v1/fc';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(minutes: 2);
  static const _downloadTimeout = Duration(minutes: 3);
  static const _pollInterval = Duration(seconds: 5);

  /// Figures created from the app are tagged, so the UGCFactory gallery can
  /// tell them apart from its own uploads.
  static const ownerId = 'ol1nllm';

  /// Consecutive failed polls tolerated before a [GenInterrupted].
  static const _maxPollFailures = 6;

  final http.Client _client = http.Client();

  Map<String, String> get _auth {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }
    return {'CF-Access-Client-Id': _cfId, 'CF-Access-Client-Secret': _cfSecret};
  }

  static String _snippet(http.Response r) {
    String msg = r.body;
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) msg = j['error'] as String;
    } catch (_) {}
    msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return 'HTTP ${r.statusCode}${msg.isNotEmpty ? ": $msg" : ""}';
  }

  /// Dances the figure can learn. Throws on network/HTTP failure — the studio
  /// then just doesn't offer the figure.
  Future<List<FigureClip>> fetchDances() async {
    final r = await _client
        .get(Uri.parse('$_baseUrl/animations?category=dance'), headers: _auth)
        .timeout(_timeout);
    if (r.statusCode != 200) throw Exception(_snippet(r));
    final list = jsonDecode(r.body) as List;
    return [
      for (final a in list) FigureClip.fromJson(a as Map<String, dynamic>),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Create a figure from [image] (PNG/JPEG bytes) that knows all [clipIds],
  /// and stream it to completion. Every clip ends up in the one GLB, so the
  /// viewer switches dances without another round.
  Stream<GenEvent> create({
    required Uint8List image,
    required String name,
    required List<String> clipIds,
  }) async* {
    if (clipIds.isEmpty) {
      yield const GenFailed('Knihovna tanců je prázdná');
      return;
    }
    debugPrint('[figure] POST /characters clips=${clipIds.length}');
    final http.Response r;
    try {
      final req =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/characters'))
            ..headers.addAll(_auth)
            ..fields['name'] = name
            ..fields['owner_id'] = ownerId
            ..fields['animation_ids'] = clipIds.join(',')
            ..files.add(
              http.MultipartFile.fromBytes(
                'image',
                image,
                filename: _looksLikePng(image) ? 'image.png' : 'image.jpg',
              ),
            );
      r = await http.Response.fromStream(
        await _client.send(req).timeout(_uploadTimeout),
      );
    } on Exception catch (e) {
      yield GenFailed('Server figurek nedostupný: $e');
      return;
    }
    if (r.statusCode != 202) {
      yield GenFailed(_snippet(r));
      return;
    }
    final id = (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
    debugPrint('[figure] character $id accepted');
    yield GenSubmitted(id);
    yield* follow(id);
  }

  /// Poll character [id] until the pipeline is done, then download the GLB.
  /// Progress is a [GenRunning] of the stage index (see [figureProgress]); the
  /// provider turns it into a stage label via [figureStageLabel].
  Stream<GenEvent> follow(String id) async* {
    int failures = 0;
    while (true) {
      FigureProgress p;
      try {
        final r = await _client
            .get(Uri.parse('$_baseUrl/characters/$id'), headers: _auth)
            .timeout(_timeout);
        if (r.statusCode == 404) {
          yield const GenFailed('Figurka na serveru už neexistuje');
          return;
        }
        if (r.statusCode != 200) throw Exception(_snippet(r));
        p = figureProgress(jsonDecode(r.body) as Map<String, dynamic>);
        failures = 0;
      } on Exception catch (e) {
        if (++failures >= _maxPollFailures) {
          debugPrint('[figure] $id: poll failed $failures× ($e)');
          yield GenInterrupted(id);
          return;
        }
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      if (p.error != null) {
        yield GenFailed(p.error!);
        return;
      }
      if (!p.done) {
        yield p.queued
            ? const GenQueued(0)
            : GenRunning(p.stage, kFigureStageCount);
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      yield const GenDownloading(0, 1);
      try {
        Uint8List? glb;
        // Dvakrát, stejně jako mp4 u videa: uříznuté stažení projde jako 200.
        for (var attempt = 0; attempt < 2; attempt++) {
          final r = await _client
              .get(
                Uri.parse('$_baseUrl/characters/$id/file/final_glb'),
                headers: _auth,
              )
              .timeout(_downloadTimeout);
          if (r.statusCode != 200) throw Exception(_snippet(r));
          if (glbLooksComplete(r.bodyBytes)) {
            glb = r.bodyBytes;
            break;
          }
          debugPrint(
            '[figure] $id: neúplné GLB (${r.bodyBytes.length} B), '
            'pokus ${attempt + 1}',
          );
        }
        if (glb == null) throw Exception('stažená figurka je neúplná');
        debugPrint('[figure] $id: ${glb.length} B, klipy ${p.clipIds}');
        yield GenFigureComplete(glb: glb, clipIds: p.clipIds);
      } on Exception catch (e) {
        debugPrint('[figure] $id: download failed ($e)');
        yield GenInterrupted(id);
      }
      return;
    }
  }

  void dispose() => _client.close();
}

/// Stages the user waits through, in pipeline order. The server status names
/// the last *finished* step, so the running stage is the one after it.
const kFigureStageLabels = [
  'Odstraňuji pozadí',
  'Stavím 3D model · 3–6 min',
  'Uhlazuji model',
  'Stavím kostru',
  'Učím ji tančit',
  'Balím figurku',
];
const kFigureStageCount = 6;

const _statusStage = {
  'uploaded': 0,
  'preprocessed': 1,
  'meshed': 2,
  'cleaned': 3,
  'rigged': 4,
  'animated': 5,
  'exported': 5,
};

String figureStageLabel(int stage) =>
    kFigureStageLabels[stage.clamp(0, kFigureStageCount - 1)];

/// One poll of `GET /v1/fc/characters/{id}`, reduced to what the studio needs.
class FigureProgress {
  final bool done;

  /// Waiting for a worker (the step exists but nobody claimed it yet).
  final bool queued;
  final int stage;
  final String? error;

  /// Clip ids in timeline order — the names of the GLB's animations.
  final List<String> clipIds;

  const FigureProgress({
    required this.done,
    required this.queued,
    required this.stage,
    required this.error,
    required this.clipIds,
  });
}

/// Pure mapping of the character detail JSON; see [FigureService.follow].
///
/// A failed character carries its error. A step re-queued by retry leaves the
/// character in the status before it, so the stage never runs backwards past
/// what the server actually redoes.
FigureProgress figureProgress(Map<String, dynamic> detail) {
  final c = detail['character'] as Map<String, dynamic>;
  final status = c['status'] as String? ?? '';
  final steps = (detail['steps'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final last = steps.isEmpty ? null : steps.last;
  final anims =
      (detail['animations'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .toList()
        ..sort(
          (a, b) => ((a['frame_start'] as int?) ?? 0).compareTo(
            (b['frame_start'] as int?) ?? 0,
          ),
        );
  final error = status == 'failed'
      ? ((c['error'] as String?)?.trim().isNotEmpty == true
            ? c['error'] as String
            : 'Figurka se nepovedla')
      : null;
  return FigureProgress(
    done: status == 'done',
    queued: last != null && last['status'] == 'queued' && status == 'uploaded',
    stage: _statusStage[status] ?? 0,
    error: error,
    clipIds: [for (final a in anims) a['animation_id'] as String],
  );
}

/// Whether [bytes] are a structurally complete binary glTF: the 12-byte header
/// declares the total length, so a truncated download is caught before it is
/// saved and handed to the viewer (which would just show nothing).
bool glbLooksComplete(Uint8List bytes) {
  if (bytes.length < 20) return false;
  final data = ByteData.sublistView(bytes);
  final magic = data.getUint32(0, Endian.little);
  final length = data.getUint32(8, Endian.little);
  return magic == 0x46546C67 && length == bytes.length; // 'glTF'
}

bool _looksLikePng(Uint8List b) =>
    b.length > 4 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4E &&
    b[3] == 0x47;
