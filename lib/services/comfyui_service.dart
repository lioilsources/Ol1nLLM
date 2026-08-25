import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, WebSocket;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/image_model.dart';
import '../models/latent_bucket.dart';
import '../models/pose_template.dart';
import 'http_error.dart';
import 'image_backend.dart';

/// Talks to a ComfyUI instance behind Cloudflare Access at comfyui.ol1n.com,
/// reusing the same CF service-token credentials as the chat/diffusers paths.
///
/// It leans on ComfyUI's native API as much as possible:
///   • POST /prompt        — enqueue a workflow (the async job queue)
///   • WS  /ws             — live per-step progress + completion events
///   • GET /history/{id}   — polling fallback + output image refs
///   • GET /queue          — queue position when WS is unavailable
///   • GET /view           — download a finished/existing output image
///   • POST /upload/image  — push an input image for img2img edits
///   • POST /interrupt     — cancel the running job
///   • POST /free          — free VRAM / unload models (housekeeping nicety)
///
/// Workflows are shipped as ComfyUI API-format JSON assets and patched per
/// request (prompt text, batch size, seed, input image) before enqueueing.
class ComfyUIService implements ImageBackend {
  ComfyUIService();

  static const _baseUrl = String.fromEnvironment(
    'COMFYUI_URL',
    defaultValue: 'https://comfyui.ol1n.com',
  );
  static final _wsUrl = '${_baseUrl.replaceFirst('http', 'ws')}/ws';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _submitTimeout = Duration(seconds: 30);
  static const _pollTimeout = Duration(seconds: 15);
  static const _pollInterval = Duration(seconds: 2);
  static const _wsConnectTimeout = Duration(seconds: 10);

  /// No message at all for this long ⇒ stop trusting the socket and poll.
  static const _wsSilenceTimeout = Duration(seconds: 90);
  static const _downloadTimeout = Duration(seconds: 120);

  /// ComfyUI keys its websockets by `clientId` and **evicts** an existing
  /// socket when a second one connects with the same id ("reusing existing
  /// session, remove old"). One id per service instance therefore meant that
  /// starting a second job silently starved the first job's socket: its
  /// progress froze and, since the socket stayed open without erroring, it
  /// never fell through to polling either. So each run gets its own id, used
  /// for both the enqueue and its socket (verified against the server: with
  /// a shared id the first socket goes dead the instant the second connects;
  /// with distinct ids it keeps receiving every message).
  static String _newClientId() => const Uuid().v4();
  final http.Client _client = _makeClient();
  final Map<String, Map<String, dynamic>> _templateCache = {};

  String? _activeLora;

  /// LoRA strength for both model and clip. Negative values invert the
  /// learned direction — the intended usage of "slider" LoRAs (e.g. a realism
  /// slider pushes back toward anime below zero).
  double _loraStrength = kDefaultLoraStrength;
  String? _activePoseAsset;
  bool _autoPose = false;
  double? _editDenoise;
  ComfyPreset _preset = imageModelById(kDefaultImageModelId).preset!;

  /// Pose asset → server-side filename, so each skeleton uploads at most once
  /// per app run (uploads use overwrite=true, so a re-upload is harmless).
  final Map<String, String> _poseUploadCache = {};

  void setLora(String? loraName) => _activeLora = loraName;
  void setLoraStrength(double strength) => _loraStrength = strength;
  void setPose(String? poseAsset) => _activePoseAsset = poseAsset;

  /// Whether img2img should carry the source image's own structure over via a
  /// depth→ControlNet splice, so the user doesn't have to describe the pose.
  /// Set to the active model's `supportsPose` (the ControlNet is SDXL-only). A
  /// pose picked from a template ([setPose]) overrides this — see [edit].
  ///
  /// Depth (not OpenPose) for the source path on purpose: a stick-figure
  /// skeleton drops the facing direction, so refining a front-facing photo can
  /// flip the subject around; the depth map keeps orientation, proportions and
  /// stance while the prompt still restyles freely (verified on the server).
  void setAutoPose(bool enabled) => _autoPose = enabled;
  void setPreset(ComfyPreset preset) => _preset = preset;

  /// Denoise for the next [edit], overriding the preset's `img2imgDenoise`.
  /// Null = the preset value. This is the difference between "retouch the
  /// photo" and "repaint it in another visual language": at the preset's 0.72
  /// the source latent carries palette and lighting through, so an art style
  /// barely lands (measured over 10 models × 25 styles), while 0.9 lets the
  /// style through and the depth ControlNet still holds the pose. A picked
  /// pose template keeps [kPoseEditDenoise] regardless — it needs the high
  /// value to move limbs at all.
  void setEditDenoise(double? denoise) => _editDenoise = denoise;

  // OpenPose ControlNet for the template-override path (pre-made skeletons).
  // SDXL-only — callers must not set a template pose for non-SDXL presets.
  static const _openPoseControlNet =
      'controlnet-openpose-sdxl-xinsir.safetensors';

  // Auto source-structure path: DepthAnything v2 → xinsir Union ControlNet in
  // depth mode. 0.7 keeps the source stance without pinning it so hard the
  // prompt can't restyle (verified end-to-end on the server).
  static const _depthPreprocessorCkpt = 'depth_anything_v2_vitl.pth';
  static const _depthResolution = 768;
  static const _unionControlNet =
      'controlnet-union-sdxl-promax-xinsir.safetensors';
  static const _depthStrength = 0.7;

  // Repose: the depth hint drives a txt2img render at denoise 1.0, where
  // (unlike img2img) no source latent carries structure — so a touch more
  // strength than the auto-depth path, but not 1.0: at full strength over
  // the whole schedule the reference's *body volume* (hair mass, clothing
  // bulk, the flat shading of the depth map) gets baked in and fights the
  // new character. Releasing the last 10 % of steps lets textures and
  // details settle without the hint. 0.75 / 0.9 are the values proven on
  // this server for exactly this template shape (MangaPrompts repose). If
  // poses drift in practice, step strength to 0.85 first.
  static const _reposeDepthStrength = 0.75;
  static const _reposeDepthEndPercent = 0.9;

  // Full strength for the whole schedule: at 0.9/0.8 the xinsir ControlNet
  // lost against prompts that imply a different pose (verified on server).
  static const _poseStrength = 1.0;
  static const _poseStartPercent = 0.0;
  static const _poseEndPercent = 1.0;

  String get _txt2imgAsset => _preset.txt2imgAsset;
  String get _img2imgAsset => _preset.img2imgAsset;

  Future<List<String>> fetchLoras() =>
      _fetchComboOptions('LoraLoader', 'lora_name');

  /// Checkpoints installed on the server. Used to hide models whose .safetensors
  /// is gone; an empty result (offline / error) means "unknown", not "none".
  Future<List<String>> fetchCheckpoints() =>
      _fetchComboOptions('CheckpointLoaderSimple', 'ckpt_name');

  /// Reads one combo-widget's option list out of `/object_info/{node}`. ComfyUI
  /// nests it as `{node: {input: {required: {field: [[…options], {…meta}]}}}}` —
  /// the per-node endpoint keeps this cheap (the full /object_info is megabytes).
  Future<List<String>> _fetchComboOptions(String node, String field) async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseUrl/object_info/$node'), headers: _authHeaders)
          .timeout(_pollTimeout);
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final names =
          ((json[node]?['input']?['required']?[field] as List?)?.first as List?)
              ?.cast<String>();
      return names ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static http.Client _makeClient() => http.Client();

  @override
  String get id => kBackendComfyUI;

  @override
  String get label => 'ComfyUI';

  // 2 variants per round: flux-dev on GB10 runs ~79 s/image, so batch 4 was
  // ~278 s (and pushed long jobs toward the client poll deadline). Batch 2 ≈
  // 140 s keeps a real choice without the wait. _prepare() patches batch_size.
  @override
  int get variantCount => 2;

  // ── Auth headers ────────────────────────────────────────────
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

  // ── Public backend API ──────────────────────────────────────
  @override
  Stream<GenEvent> generate({
    required String prompt,
    required int n,
    required int seed,
    String? negativePrompt,
  }) async* {
    final pose = _activePoseAsset;
    final poseImageName = (pose != null && _preset.ckptName != null)
        ? await _ensurePoseUploaded(pose)
        : null;
    final tpl = await _template(_txt2imgAsset);
    final wf = _prepare(
      tpl,
      prompt: prompt,
      batch: n,
      seed: seed,
      poseImageName: poseImageName,
      userNegative: negativePrompt,
    );
    yield* _run(wf);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
    required int seed,
    String? negativePrompt,
    Uint8List? mask,
    Uint8List? refImage,
    bool refIsFace = false,
  }) async* {
    if (mask != null) {
      yield* _inpaint(
        image: image,
        mask: mask,
        refImage: refImage,
        refIsFace: refIsFace,
        prompt: prompt,
        n: n,
        seed: seed,
        negativePrompt: negativePrompt,
      );
      return;
    }
    final pose = _activePoseAsset;
    final poseImageName = (pose != null && _preset.ckptName != null)
        ? await _ensurePoseUploaded(pose)
        : null;
    final editDenoise = _editDenoise;
    final imageName = await _uploadImage(image);
    // Carry the source's own structure over via depth ControlNet, unless a
    // template pose was picked (that overrides) — see [setAutoPose].
    final sourceDepth =
        poseImageName == null && _autoPose && _preset.ckptName != null;
    final tpl = await _template(_img2imgAsset);
    final wf = _prepare(
      tpl,
      prompt: prompt,
      batch: n,
      seed: seed,
      imageName: imageName,
      poseImageName: poseImageName,
      sourceDepth: sourceDepth,
      userNegative: negativePrompt,
      editDenoise: editDenoise,
    );
    yield* _run(wf);
  }

  /// Masked edit: repaint only where [mask] is white (see the inpaint assets).
  /// With [refImage] the ref-guided template runs instead — IPAdapter feeds
  /// the reference's appearance into the masked region (attn_mask-limited).
  /// No pose/depth ControlNet — the mask already pins everything outside it,
  /// and constraining the repainted region would defeat the point.
  Stream<GenEvent> _inpaint({
    required Uint8List image,
    required Uint8List mask,
    Uint8List? refImage,
    bool refIsFace = false,
    required String prompt,
    required int n,
    required int seed,
    String? negativePrompt,
  }) async* {
    final asset = refImage == null
        ? _preset.inpaintAsset
        : refIsFace
            ? _preset.inpaintFaceAsset
            : _preset.inpaintRefAsset;
    if (asset == null) {
      yield GenFailed(
        refImage == null
            ? '[ComfyUI] Aktivní model nepodporuje inpaint.'
            : refIsFace
                ? '[ComfyUI] Aktivní model nepodporuje face inpaint.'
                : '[ComfyUI] Aktivní model nepodporuje referenční inpaint.',
      );
      return;
    }
    final imageName = await _uploadImage(image);
    final maskName = await _uploadImage(mask, filename: 'mask_${_uuidV4()}.png');
    final refName = refImage == null
        ? null
        : await _uploadImage(refImage, filename: 'ref_${_uuidV4()}.png');
    final tpl = await _template(asset);
    final wf = _prepare(
      tpl,
      prompt: prompt,
      batch: n,
      seed: seed,
      imageName: imageName,
      maskName: maskName,
      refName: refName,
      userNegative: negativePrompt,
    );
    yield* _run(wf);
  }

  static String _uuidV4() => const Uuid().v4();

  @override
  Stream<GenEvent> follow(String jobId) => _run(null, promptId: jobId);

  // ── Repose ──────────────────────────────────────────────────

  /// Repose: a *fresh* txt2img render of [prompt] whose silhouette/stance is
  /// pinned to [image] via DepthAnything → union ControlNet (depth). No
  /// source latent (EmptyLatentImage, denoise 1.0) and no identity transfer
  /// — character and style come entirely from the prompt; only the pose is
  /// kept. SDXL only (generic template + union CN). A picked template pose
  /// is ignored: the reference *is* the pose. The latent bucket follows the
  /// reference's aspect so the depth hint isn't center-cropped; the caller
  /// may pass [latentSize] to keep node metadata and the request in sync.
  /// Resume is the plain [follow] — the job is an ordinary prompt.
  Stream<GenEvent> repose({
    required Uint8List image,
    required String prompt,
    required int n,
    required int seed,
    String? negativePrompt,
    LatentSize? latentSize,
  }) async* {
    if (_preset.ckptName == null) {
      yield const GenFailed('[ComfyUI] Repose umí jen SDXL modely.');
      return;
    }
    final refName = await _uploadImage(
      image,
      filename: 'repose_${_uuidV4()}.png',
    );
    final tpl = await _template(_txt2imgAsset);
    final wf = _prepare(
      tpl,
      prompt: prompt,
      batch: n,
      seed: seed,
      depthImageName: refName,
      latentSize: latentSize ??
          reposeLatentFor(
            image,
            fallback: (w: _preset.width, h: _preset.height),
          ),
      userNegative: negativePrompt,
    );
    yield* _run(wf);
  }

  // ── 3D mesh (img2print / Trellis2) ──────────────────────────
  //
  // The Trellis2 export node writes files but reports no paths in history, so
  // the contract is deterministic instead: the client generates a mesh id and
  // patches it into the filename prefixes (`3D/app/<id>` / `3D/app/<id>g`),
  // making the outputs downloadable at known names. That also makes resume
  // history-independent: followMesh first just tries to download the files —
  // if they exist the job is done, even if the server restarted meanwhile.
  static const _meshAsset = 'assets/comfyui/img2print.api.json';
  static const _meshSubfolder = '3D/app';

  // Mesh downloads are heavy (STL ~15 MB) and run over the CF tunnel, so they
  // get their own budget instead of the image-sized one.
  static const _meshDownloadTimeout = Duration(minutes: 5);
  static const _meshDownloadAttempts = 3;
  static const _meshDownloadBackoff = Duration(seconds: 3);

  String _meshStlName(String meshId) => '${meshId}_00001_.stl';
  String _meshGlbName(String meshId) => '${meshId}g_00001_.glb';

  /// Image → printable STL + viewer GLB via the Trellis2 pipeline. Slow
  /// (~4 min warm, ~7 min after a server restart) — progress is coarse
  /// (queue position + indeterminate run), ending in [GenMeshComplete].
  Stream<GenEvent> generateMesh({
    required Uint8List image,
    required int seed,
  }) async* {
    final imageName = await _uploadImage(image);
    final meshId = const Uuid().v4().replaceAll('-', '');
    final raw = jsonEncode(await _template(_meshAsset))
        .replaceAll('__IMAGE__', imageName)
        .replaceAll('__MESHID__', meshId);
    final wf = jsonDecode(raw) as Map<String, dynamic>;
    for (final node in wf.values) {
      final inputs =
          ((node as Map)['inputs'] as Map?)?.cast<String, dynamic>();
      if (inputs != null && inputs.containsKey('seed')) {
        inputs['seed'] = seed;
      }
    }
    // Mesh progress is polled (no per-step events), so this id only tags the
    // submission — but it must still be unique per job.
    final promptId = await _queuePrompt(wf, clientId: _newClientId());
    yield* _runMesh(promptId, meshId);
  }

  /// Re-attach to a mesh job. [jobId] is `promptId|meshId` as emitted by
  /// [generateMesh]'s [GenSubmitted].
  Stream<GenEvent> followMesh(String jobId) async* {
    final parts = jobId.split('|');
    if (parts.length != 2) {
      yield const GenFailed('[ComfyUI] Neplatné id 3D jobu.');
      return;
    }
    yield* _runMesh(parts[0], parts[1], resuming: true);
  }

  Stream<GenEvent> _runMesh(
    String promptId,
    String meshId, {
    bool resuming = false,
  }) async* {
    yield GenSubmitted('$promptId|$meshId');

    // Mesh files are big (STL ~15 MB, GLB ~5 MB) and go through the CF tunnel:
    // ~17 s for the STL on a fast desktop link, several times that on mobile.
    // Distinguish "not there (yet)" — a plain 404, the only legitimate null —
    // from a transport failure, which must NOT be reported as a dead job: the
    // files are durable server-side, so a retry (or the next resume) can still
    // pick them up.
    Future<Uint8List?> download(String filename) async {
      Object? lastError;
      for (var attempt = 1; attempt <= _meshDownloadAttempts; attempt++) {
        try {
          final uri = Uri.parse('$_baseUrl/view').replace(queryParameters: {
            'filename': filename,
            'subfolder': _meshSubfolder,
            'type': 'output',
          });
          final resp = await _client
              .get(uri, headers: _authHeaders)
              .timeout(_meshDownloadTimeout);
          if (resp.statusCode == 200) return resp.bodyBytes;
          if (resp.statusCode == 404) return null; // genuinely absent
          lastError = 'HTTP ${resp.statusCode}';
        } catch (e) {
          lastError = e;
        }
        if (attempt < _meshDownloadAttempts) {
          await Future.delayed(_meshDownloadBackoff * attempt);
        }
      }
      throw _MeshDownloadFailure('$filename: $lastError');
    }

    Future<GenEvent?> tryComplete() async {
      final stl = await download(_meshStlName(meshId));
      if (stl == null) return null;
      final glb = await download(_meshGlbName(meshId));
      if (glb == null) return null;
      return GenMeshComplete(stl: stl, glb: glb);
    }

    // Resume shortcut: the files are durable even when history is not.
    if (resuming) {
      final done = await tryComplete();
      if (done != null) {
        yield done;
        return;
      }
    }

    var missingFromHistory = 0;
    while (true) {
      await Future.delayed(_pollInterval);
      try {
        // Queue position while pending.
        final qResp = await _client
            .get(Uri.parse('$_baseUrl/queue'), headers: _authHeaders)
            .timeout(_pollTimeout);
        if (qResp.statusCode == 200) {
          final q = jsonDecode(qResp.body) as Map<String, dynamic>;
          final pending = (q['queue_pending'] as List?) ?? const [];
          final running = (q['queue_running'] as List?) ?? const [];
          final pos = pending.indexWhere((e) => (e as List)[1] == promptId);
          if (pos >= 0) {
            missingFromHistory = 0;
            yield GenQueued(pos + 1);
            continue;
          }
          if (running.any((e) => (e as List)[1] == promptId)) {
            // Still executing. ComfyUI only writes the history entry AFTER
            // completion, so the history check below would see "missing" for
            // the whole (many-minute) run and falsely declare the job lost —
            // skip it while the queue itself confirms the job is alive.
            missingFromHistory = 0;
            yield const GenRunning(0, 0);
            continue;
          }
        }

        final hResp = await _client
            .get(
              Uri.parse('$_baseUrl/history/$promptId'),
              headers: _authHeaders,
            )
            .timeout(_pollTimeout);
        if (hResp.statusCode != 200) continue;
        final h = jsonDecode(hResp.body) as Map<String, dynamic>;
        final entry = h[promptId] as Map<String, dynamic>?;
        if (entry == null) {
          // Not queued, not running, not in history: either a race right
          // after submit, or the server restarted and lost the job. Files
          // may still exist (job finished before the restart).
          if (++missingFromHistory >= 3) {
            final done = await tryComplete();
            if (done != null) {
              yield done;
              return;
            }
            yield const GenFailed(
              '[ComfyUI] 3D job se na serveru ztratil (restart?) — '
              'zkus to znovu.',
            );
            return;
          }
          continue;
        }
        missingFromHistory = 0;
        final status =
            (entry['status'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (status['status_str'] == 'error') {
          yield const GenFailed('[ComfyUI] 3D generování selhalo na serveru.');
          return;
        }
        if (status['completed'] == true ||
            (entry['outputs'] as Map?)?.isNotEmpty == true) {
          yield const GenDownloading(0, 2);
          final done = await tryComplete();
          if (done != null) {
            yield done;
            return;
          }
          // History says done but the files are absent (404) — the export
          // node never wrote them, so regenerating is the only way out.
          yield const GenFailed(
            '[ComfyUI] 3D výstup na serveru chybí — zkus vygenerovat znovu.',
          );
          return;
        }
      } on _MeshDownloadFailure catch (e) {
        // Transport hiccup while pulling a finished mesh (slow mobile link,
        // app suspended mid-transfer). The files stay on the server, so this
        // is resumable — never a dead job.
        debugPrint('[comfy] mesh download failed: $e');
        yield GenInterrupted('$promptId|$meshId');
        return;
      } on TimeoutException {
        yield GenInterrupted('$promptId|$meshId');
        return;
      } on SocketException {
        yield GenInterrupted('$promptId|$meshId');
        return;
      } catch (_) {
        // iOS suspend kills sockets as http.ClientException/HttpException
        // (not Socket/Timeout) — same classification as the NIM backends:
        // resumable interruption, not a failure. The job id is durable and
        // followMesh can even complete from the output files later.
        yield GenInterrupted('$promptId|$meshId');
        return;
      }
    }
  }

  // ── Orchestration: enqueue → progress (WS|poll) → download ───
  //
  // When [workflow] is null, [promptId] must be supplied — we re-attach to an
  // already-queued job (resume) instead of enqueueing a new one.
  Stream<GenEvent> _run(
    Map<String, dynamic>? workflow, {
    String? promptId,
  }) async* {
    // Validate credentials upfront. When workflow is null (follow() path),
    // _queuePrompt is skipped so _authHeaders is never called — without this
    // check the WS try/catch swallows the auth error and _pollUntilDone retries
    // forever.
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      yield const GenFailed(
        '[ComfyUI] CF Access credentials not configured. '
        'Rebuild with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
      return;
    }
    final clientId = _newClientId();
    final resuming = workflow == null;
    promptId ??= await _queuePrompt(workflow!, clientId: clientId);
    yield GenSubmitted(promptId);
    yield const GenQueued(0);

    // Prefer the websocket for true per-step progress; fall back to polling
    // /history + /queue if the WS can't be established (e.g. CF Access blocks
    // the upgrade, or on platforms without dart:io sockets).
    //
    // On the follow() path there is nothing to listen to: the running job was
    // enqueued under a client id from before the suspend/restart, and ComfyUI
    // addresses execution messages to *that* socket — a fresh one would sit
    // silent forever. Straight to polling.
    WebSocket? ws;
    if (!resuming) {
      try {
        ws = await WebSocket.connect(
          '$_wsUrl?clientId=$clientId',
          headers: _authHeaders,
        ).timeout(_wsConnectTimeout);
      } catch (e) {
        debugPrint('[comfy] ws connect failed ($e) — polling instead');
        ws = null;
      }
    }

    var finished = false;
    if (ws != null) {
      var started = false;
      try {
        // A socket that goes quiet must not freeze the node: half-open
        // connections and any future message-routing surprise would otherwise
        // hang here with no error to fall back from. The timeout throws into
        // the catch below, which switches to polling. Generous, because a job
        // queued behind a long one legitimately hears nothing meanwhile.
        await for (final raw in ws.timeout(_wsSilenceTimeout)) {
          if (raw is! String) continue; // binary frames = preview images
          Map<String, dynamic> msg;
          try {
            msg = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final type = msg['type'] as String?;
          final data =
              (msg['data'] as Map?)?.cast<String, dynamic>() ?? const {};
          final pid = data['prompt_id'] as String?;

          switch (type) {
            case 'status':
              if (!started) {
                final remaining =
                    ((data['status'] as Map?)?['exec_info']
                        as Map?)?['queue_remaining'];
                if (remaining is int) {
                  yield GenQueued(remaining > 0 ? remaining - 1 : 0);
                }
              }
            case 'execution_start':
              if (pid == promptId) {
                started = true;
                yield const GenRunning(0, 0);
              }
            case 'progress':
              if (pid == null || pid == promptId) {
                started = true;
                final v = data['value'];
                final mx = data['max'];
                if (v is int && mx is int) yield GenRunning(v, mx);
              }
            case 'executing':
              if (pid == promptId && data['node'] == null) finished = true;
            case 'execution_error':
              if (pid == promptId) {
                yield GenFailed(_wsErrorMessage(data));
                await ws.close();
                return;
              }
            case 'execution_interrupted':
              if (pid == promptId) {
                yield const GenFailed('Zrušeno');
                await ws.close();
                return;
              }
          }
          if (finished) break;
        }
      } catch (e) {
        debugPrint('[comfy] ws stream error ($e) — falling back to polling');
      } finally {
        await ws.close();
      }
    }

    if (!finished) {
      // WS unavailable or closed before completion — poll to the terminal
      // state, then download.
      yield* _pollUntilDone(promptId);
      return;
    }
    yield* _downloadOutputs(promptId);
  }

  // ── HTTP polling fallback ───────────────────────────────────
  Stream<GenEvent> _pollUntilDone(String promptId) async* {
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    // Consecutive transient poll failures (network blip / iOS suspend). After
    // a few in a row we bail out with GenInterrupted so the provider re-attaches
    // via follow() on resume — instead of silently spinning for 10 minutes.
    var consecutiveErrors = 0;
    const maxConsecutiveErrors = 3;
    while (true) {
      await Future.delayed(_pollInterval);
      if (DateTime.now().isAfter(deadline)) {
        yield const GenFailed('[ComfyUI] timeout – generování trvá příliš dlouho (>15 min)');
        return;
      }

      Map<String, dynamic>? hist;
      try {
        hist = await _history(promptId);
      } catch (e) {
        debugPrint('[comfy] poll /history error ($e) — retrying');
        if (++consecutiveErrors >= maxConsecutiveErrors) {
          debugPrint('[comfy] $consecutiveErrors consecutive poll errors — interrupting, will resume');
          yield GenInterrupted(promptId);
          return;
        }
        continue;
      }

      if (hist != null) {
        final status = (hist['status'] as Map?)?.cast<String, dynamic>();
        if (status?['status_str'] == 'error') {
          yield GenFailed(_historyErrorMessage(hist));
          return;
        }
        yield* _downloadOutputs(promptId, hist: hist);
        return;
      }

      // /history reached the server (job just not finished yet) → reset counter.
      consecutiveErrors = 0;

      // Not in history yet → still queued or running. Surface a coarse status.
      try {
        final q = await _queueState();
        final running = (q['queue_running'] as List?) ?? const [];
        final pending = (q['queue_pending'] as List?) ?? const [];
        bool isThis(dynamic e) => e is List && e.length > 1 && e[1] == promptId;
        if (running.any(isThis)) {
          yield const GenRunning(0, 0); // running, no per-step info via poll
        } else {
          final idx = pending.toList().indexWhere(isThis);
          yield GenQueued(idx < 0 ? 0 : idx);
        }
      } catch (_) {
        // transient — keep polling
      }
    }
  }

  // ── Download finished/existing outputs via /view ────────────
  Stream<GenEvent> _downloadOutputs(
    String promptId, {
    Map<String, dynamic>? hist,
  }) async* {
    hist ??= await _history(promptId);
    if (hist == null) {
      yield const GenFailed('[ComfyUI] výsledek nenalezen (history prázdná)');
      return;
    }
    final outputs =
        (hist['outputs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final refs = <Map<String, dynamic>>[];
    for (final node in outputs.values) {
      final images = ((node as Map?)?['images'] as List?) ?? const [];
      for (final img in images) {
        final m = (img as Map).cast<String, dynamic>();
        if (m['type'] == 'temp') continue; // skip live-preview temps
        refs.add(m);
      }
    }
    if (refs.isEmpty) {
      yield const GenFailed('[ComfyUI] žádné výstupní obrázky ve workflow');
      return;
    }

    final out = <Uint8List>[];
    for (var i = 0; i < refs.length; i++) {
      yield GenDownloading(i, refs.length);
      final r = refs[i];
      out.add(
        await _view(
          r['filename'] as String,
          (r['subfolder'] as String?) ?? '',
          (r['type'] as String?) ?? 'output',
        ),
      );
    }
    yield GenComplete(out);
  }

  // ── ComfyUI REST primitives ─────────────────────────────────
  Future<String> _queuePrompt(
    Map<String, dynamic> workflow, {
    required String clientId,
  }) async {
    final resp = await _client
        .post(
          Uri.parse('$_baseUrl/prompt'),
          headers: _jsonHeaders,
          body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
        )
        .timeout(_submitTimeout, onTimeout: () {
      throw Exception(
        '[ComfyUI] timeout při odesílání workflow (${_submitTimeout.inSeconds}s)',
      );
    });
    debugPrint('[comfy] POST /prompt → ${resp.statusCode}');
    if (resp.statusCode != 200) {
      throw Exception(HttpLayerError.parse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
        step: 'submit',
        service: 'ComfyUI',
      ).toString());
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final nodeErrors = json['node_errors'];
    if (nodeErrors is Map && nodeErrors.isNotEmpty) {
      throw Exception('ComfyUI workflow error: ${jsonEncode(nodeErrors)}');
    }
    final promptId = json['prompt_id'] as String?;
    if (promptId == null) {
      throw Exception('ComfyUI /prompt returned no prompt_id');
    }
    debugPrint('[comfy] prompt_id=$promptId');
    return promptId;
  }

  Future<Map<String, dynamic>?> _history(String promptId) async {
    final resp = await _client
        .get(Uri.parse('$_baseUrl/history/$promptId'), headers: _authHeaders)
        .timeout(_pollTimeout);
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return (json[promptId] as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _queueState() async {
    final resp = await _client
        .get(Uri.parse('$_baseUrl/queue'), headers: _authHeaders)
        .timeout(_pollTimeout);
    if (resp.statusCode != 200) return const {};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Uint8List> _view(
    String filename,
    String subfolder,
    String type,
  ) async {
    final uri = Uri.parse('$_baseUrl/view').replace(
      queryParameters: {
        'filename': filename,
        'subfolder': subfolder,
        'type': type,
      },
    );
    final resp = await _client
        .get(uri, headers: _authHeaders)
        .timeout(_downloadTimeout, onTimeout: () {
      throw Exception(
        '[ComfyUI] timeout při stahování $filename (${_downloadTimeout.inSeconds}s)',
      );
    });
    debugPrint(
      '[comfy] GET /view $filename → ${resp.statusCode} '
      '(${resp.bodyBytes.length} bytes)',
    );
    if (resp.statusCode != 200) {
      throw Exception(HttpLayerError.parse(
        statusCode: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
        step: 'download',
        service: 'ComfyUI',
      ).toString());
    }
    return resp.bodyBytes;
  }

  /// Number of upload attempts before giving up. Flaky Wi-Fi throws transient
  /// `Failed host lookup` / `Connection reset` / timeouts mid-upload; a couple
  /// of quick retries usually rides over the blip instead of failing the edit.
  static const _uploadMaxAttempts = 3;

  /// Upload a bundled pose skeleton and remember its server-side name. The
  /// deterministic filename + overwrite=true make this idempotent across app
  /// runs; the cache just skips the round-trip within one run.
  Future<String> _ensurePoseUploaded(String asset) async {
    final cached = _poseUploadCache[asset];
    if (cached != null) return cached;
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final name = await _uploadImage(
      bytes,
      filename: 'ol1n_pose_${asset.split('/').last}',
    );
    return _poseUploadCache[asset] = name;
  }

  Future<String> _uploadImage(Uint8List bytes, {String? filename}) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= _uploadMaxAttempts; attempt++) {
      try {
        // MultipartRequest is single-use (its body stream is consumed on send),
        // so a fresh request must be built for each attempt.
        final req =
            http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload/image'))
              ..headers.addAll(_authHeaders)
              ..fields['overwrite'] = 'true'
              ..files.add(
                http.MultipartFile.fromBytes(
                  'image',
                  bytes,
                  filename: filename ??
                      'ol1n_input_${DateTime.now().millisecondsSinceEpoch}.png',
                ),
              );
        final streamed = await _client.send(req).timeout(_submitTimeout);
        final resp = await http.Response.fromStream(streamed);
        debugPrint(
          '[comfy] POST /upload/image → ${resp.statusCode} (pokus $attempt/$_uploadMaxAttempts)',
        );
        // A non-200 is a server-side rejection — retrying won't help, fail now.
        if (resp.statusCode != 200) {
          throw Exception(HttpLayerError.parse(
            statusCode: resp.statusCode,
            body: resp.body,
            headers: resp.headers,
            step: 'upload',
            service: 'ComfyUI',
          ).toString());
        }
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final name = json['name'] as String;
        final subfolder = json['subfolder'] as String? ?? '';
        return subfolder.isEmpty ? name : '$subfolder/$name';
      } on SocketException catch (e) {
        lastErr = e; // Failed host lookup / Connection reset — transient
      } on TimeoutException catch (e) {
        lastErr = e; // upload didn't finish within _submitTimeout
      } on http.ClientException catch (e) {
        lastErr = e; // connection closed mid-flight, etc.
      }
      debugPrint('[comfy] upload pokus $attempt selhal: $lastErr');
      if (attempt < _uploadMaxAttempts) {
        // Linear backoff: 1 s, then 2 s — short enough to stay responsive.
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    throw Exception(
      '[ComfyUI] nahrání obrázku selhalo po $_uploadMaxAttempts pokusech '
      '(síť/Wi-Fi): $lastErr',
    );
  }

  @override
  Future<void> interrupt() async {
    try {
      await _client
          .post(Uri.parse('$_baseUrl/interrupt'), headers: _authHeaders)
          .timeout(_pollTimeout);
    } catch (e) {
      debugPrint('[comfy] interrupt failed: $e');
    }
  }

  /// Housekeeping nicety: ask ComfyUI to free VRAM (and optionally unload
  /// models). Best-effort; never throws.
  Future<void> freeMemory({bool unloadModels = false}) async {
    try {
      await _client
          .post(
            Uri.parse('$_baseUrl/free'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'free_memory': true,
              'unload_models': unloadModels,
            }),
          )
          .timeout(_pollTimeout);
    } catch (e) {
      debugPrint('[comfy] free failed: $e');
    }
  }

  // ── Workflow templating ─────────────────────────────────────
  Future<Map<String, dynamic>> _template(String asset) async {
    final cached = _templateCache[asset];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(asset);
    final tpl = jsonDecode(raw) as Map<String, dynamic>;
    _templateCache[asset] = tpl;
    return tpl;
  }

  /// Deep-copy [template] and substitute the per-request values.
  ///
  /// Substitution is by sentinel/class_type rather than hard-coded node ids so
  /// the shipped workflows can be edited freely as long as they keep:
  ///   • a `__PROMPT__` sentinel in the positive prompt text
  ///   • an `__IMAGE__` sentinel in the LoadImage input (img2img only)
  ///   • `__CKPT__` / `__NEGATIVE__` sentinels (generic templates only)
  ///   • a latent batch node (EmptySD3LatentImage / EmptyLatentImage /
  ///     RepeatLatentBatch) whose batch size = number of variants
  ///   • a sampler node carrying `seed` / `noise_seed`
  ///
  /// Sampler/latent parameters are patched from the active [ComfyPreset] only
  /// for generic-template models (ckptName != null) — dedicated workflows like
  /// flux-manga keep their baked-in values.
  /// Test seam: exposes the private [_prepare] graph transform so tests can
  /// assert LoRA/pose injection against the real workflow assets. Set the
  /// preset/lora/pose via the public setters first.
  @visibleForTesting
  Map<String, dynamic> prepareForTest(
    Map<String, dynamic> template, {
    required String prompt,
    required int batch,
    required int seed,
    String? imageName,
    String? maskName,
    String? refName,
    String? poseImageName,
    bool sourceDepth = false,
    String? userNegative,
    String? depthImageName,
    LatentSize? latentSize,
    double? editDenoise,
  }) => _prepare(
    template,
    prompt: prompt,
    batch: batch,
    seed: seed,
    imageName: imageName,
    maskName: maskName,
    refName: refName,
    poseImageName: poseImageName,
    sourceDepth: sourceDepth,
    userNegative: userNegative,
    depthImageName: depthImageName,
    latentSize: latentSize,
    editDenoise: editDenoise,
  );

  Map<String, dynamic> _prepare(
    Map<String, dynamic> template, {
    required String prompt,
    required int batch,
    required int seed,
    String? imageName,
    String? maskName,
    String? refName,
    String? poseImageName,
    bool sourceDepth = false,
    String? userNegative,
    // Repose: explicit depth-hint source, independent of [imageName] (which
    // also drives __IMAGE__ / VAEEncode / denoise), so a txt2img template
    // can be pose-pinned to an uploaded reference.
    String? depthImageName,
    // Repose: overrides the preset/pose latent so the bucket matches the
    // reference's aspect.
    LatentSize? latentSize,
    // img2img edit strength, overriding the preset (see [setEditDenoise]).
    double? editDenoise,
  }) {
    final wf = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
    final lora = _activeLora;
    final preset = _preset;
    final fullPrompt = preset.positivePrefix.isEmpty
        ? prompt
        : '${preset.positivePrefix}, $prompt';
    // Preset negative + user ALL-CAPS negatives. Only applied where the
    // template carries a __NEGATIVE__ sentinel (generic SDXL workflows);
    // dedicated flux workflows run cfg=1 and have no usable negative input.
    final fullNegative = [
      preset.negativePrompt,
      if (userNegative != null) userNegative,
    ].where((s) => s.trim().isNotEmpty).join(', ');

    // Inject a LoraLoader and re-route model/clip references. Works for both
    // Flux (UNETLoader + DualCLIPLoader) and Pony (CheckpointLoaderSimple).
    // Skipped for dedicated inpaint workflows (flux-fill): Fill + style LoRA
    // produces artefacts — pending the M5 experiment it stays banned. SDXL
    // inpaint (ckptName != null) keeps LoRA support.
    final loraAllowed = maskName == null || preset.ckptName != null;
    if (lora != null && loraAllowed) {
      final src = _findModelClipSources(wf);
      if (src != null) {
        const loraId = '__lora__';
        wf[loraId] = {
          'class_type': 'LoraLoader',
          '_meta': {'title': 'LoRA: $lora'},
          'inputs': {
            'lora_name': lora,
            'strength_model': _loraStrength,
            'strength_clip': _loraStrength,
            'model': [src.$1, src.$2],
            'clip': [src.$3, src.$4],
          },
        };
        for (final entry in wf.entries) {
          if (entry.key == loraId) continue;
          final inputs =
              ((entry.value as Map).cast<String, dynamic>()['inputs'] as Map?)
                  ?.cast<String, dynamic>();
          if (inputs == null) continue;
          for (final k in inputs.keys.toList()) {
            final v = inputs[k];
            if (v is! List || v.length != 2) continue;
            if (v[0] == src.$1 && v[1] == src.$2) inputs[k] = [loraId, 0];
            if (v[0] == src.$3 && v[1] == src.$4) inputs[k] = [loraId, 1];
          }
        }
      }
    }

    // Splice a ControlNet between the prompt encoders and the sampler.
    // Orthogonal to the LoRA injection above: LoRA rewires model/clip edges,
    // this rewires positive/negative conditioning edges. An explicit repose
    // reference always wins (the reference *is* the pose, so a template pose
    // can't override it); then a picked template pose (OpenPose skeleton);
    // otherwise img2img keeps the source's own structure via a depth map.
    // Mutually exclusive — only one runs.
    if (depthImageName != null) {
      _injectSourceDepthControlNet(
        wf,
        depthImageName,
        strength: _reposeDepthStrength,
        endPercent: _reposeDepthEndPercent,
      );
    } else if (poseImageName != null) {
      _injectPoseControlNet(wf, poseImageName);
    } else if (sourceDepth && imageName != null) {
      _injectSourceDepthControlNet(wf, imageName);
    }

    for (final entry in wf.values) {
      final node = (entry as Map).cast<String, dynamic>();
      final cls = node['class_type'] as String?;
      final inputs = (node['inputs'] as Map?)?.cast<String, dynamic>();
      if (inputs == null) continue;

      inputs.forEach((key, value) {
        if (value is! String) return;
        var v = value;
        if (v.contains('__PROMPT__')) v = v.replaceAll('__PROMPT__', fullPrompt);
        if (v.contains('__NEGATIVE__')) v = v.replaceAll('__NEGATIVE__', fullNegative);
        if (v.contains('__CKPT__') && preset.ckptName != null) v = v.replaceAll('__CKPT__', preset.ckptName!);
        if (imageName != null && v.contains('__IMAGE__')) v = v.replaceAll('__IMAGE__', imageName);
        if (maskName != null && v.contains('__MASK__')) v = v.replaceAll('__MASK__', maskName);
        if (refName != null && v.contains('__REF__')) v = v.replaceAll('__REF__', refName);
        if (!identical(v, value)) inputs[key] = v;
      });

      switch (cls) {
        case 'EmptySD3LatentImage':
        case 'EmptyLatentImage':
          if (inputs.containsKey('batch_size')) inputs['batch_size'] = batch;
          if (preset.ckptName != null) {
            // Pose skeletons are 2:3 portrait — generate in a matching
            // bucket instead of the preset's default so they don't distort.
            inputs['width'] = latentSize?.w ??
                (poseImageName != null ? kPoseWidth : preset.width);
            inputs['height'] = latentSize?.h ??
                (poseImageName != null ? kPoseHeight : preset.height);
          }
        case 'RepeatLatentBatch':
        case 'RepeatImageBatch':
          if (inputs.containsKey('amount')) inputs['amount'] = batch;
        case 'KSampler':
          if (preset.ckptName != null) {
            inputs['steps'] = preset.steps;
            inputs['cfg'] = preset.cfg;
            inputs['sampler_name'] = preset.samplerName;
            inputs['scheduler'] = preset.scheduler;
            // Inpaint always runs full denoise — the mask (not the denoise)
            // limits the change. Pose during an edit needs high denoise,
            // otherwise the source structure overrides the ControlNet skeleton.
            inputs['denoise'] = imageName == null || maskName != null
                ? 1.0
                : (poseImageName != null
                    ? kPoseEditDenoise
                    : (editDenoise ?? preset.img2imgDenoise));
          }
      }
      if (inputs.containsKey('seed')) inputs['seed'] = seed;
      if (inputs.containsKey('noise_seed')) inputs['noise_seed'] = seed;
    }
    return wf;
  }

  // ── ControlNet injection ────────────────────────────────────
  // Two flavours splice a ControlNet between the CLIPTextEncode outputs and
  // the sampler, sharing [_spliceControlNet] for the sampler lookup + edge
  // rewiring (template-agnostic, like the sentinel patching):
  //   • template pose  — a pre-made OpenPose skeleton, fed straight in
  //   • source depth   — a depth map derived from the img2img source photo

  /// Template-override path: a pre-skeletonised OpenPose image → xinsir CN.
  void _injectPoseControlNet(Map<String, dynamic> wf, String poseImageName) {
    wf['__pose_image__'] = {
      'class_type': 'LoadImage',
      '_meta': {'title': 'Pose: $poseImageName'},
      'inputs': {'image': poseImageName, 'upload': 'image'},
    };
    wf['__pose_cn__'] = {
      'class_type': 'ControlNetLoader',
      '_meta': {'title': 'OpenPose ControlNet'},
      'inputs': {'control_net_name': _openPoseControlNet},
    };
    _spliceControlNet(
      wf,
      controlNet: ['__pose_cn__', 0],
      controlImage: ['__pose_image__', 0],
      strength: _poseStrength,
    );
  }

  /// Auto img2img path: DepthAnything v2 on the source photo → xinsir Union CN
  /// in depth mode. Keeps the source's stance/orientation without the user
  /// describing it; [setPose] overrides this. [sourceImageName] is the already
  /// uploaded img2img source — loaded again here so the injector stays
  /// independent of which node the template wires the source through (which
  /// is also what lets [repose] run it over the txt2img template, with its
  /// own [strength] / [endPercent]).
  void _injectSourceDepthControlNet(
    Map<String, dynamic> wf,
    String sourceImageName, {
    double strength = _depthStrength,
    double endPercent = _poseEndPercent,
  }) {
    wf['__depth_src__'] = {
      'class_type': 'LoadImage',
      '_meta': {'title': 'Depth source: $sourceImageName'},
      'inputs': {'image': sourceImageName, 'upload': 'image'},
    };
    wf['__depth_pre__'] = {
      'class_type': 'DepthAnythingV2Preprocessor',
      '_meta': {'title': 'Depth map from source'},
      'inputs': {
        'image': ['__depth_src__', 0],
        'ckpt_name': _depthPreprocessorCkpt,
        'resolution': _depthResolution,
      },
    };
    wf['__depth_cn__'] = {
      'class_type': 'ControlNetLoader',
      '_meta': {'title': 'Union ControlNet'},
      'inputs': {'control_net_name': _unionControlNet},
    };
    wf['__depth_type__'] = {
      'class_type': 'SetUnionControlNetType',
      '_meta': {'title': 'Union type: depth'},
      'inputs': {
        'control_net': ['__depth_cn__', 0],
        'type': 'depth',
      },
    };
    _spliceControlNet(
      wf,
      controlNet: ['__depth_type__', 0],
      controlImage: ['__depth_pre__', 0],
      strength: strength,
      endPercent: endPercent,
    );
  }

  /// Inserts a ControlNetApplyAdvanced reading the sampler's current
  /// positive/negative conditioning, then rewires the sampler through it. No-op
  /// if the graph has no KSampler with List positive/negative refs.
  void _spliceControlNet(
    Map<String, dynamic> wf, {
    required List<dynamic> controlNet,
    required List<dynamic> controlImage,
    required double strength,
    double endPercent = _poseEndPercent,
  }) {
    Map<String, dynamic>? sampler;
    for (final e in wf.entries) {
      if ((e.value as Map)['class_type'] == 'KSampler') {
        sampler = (e.value as Map).cast<String, dynamic>();
        break;
      }
    }
    final inputs = (sampler?['inputs'] as Map?)?.cast<String, dynamic>();
    final positive = inputs?['positive'];
    final negative = inputs?['negative'];
    if (inputs == null || positive is! List || negative is! List) return;

    wf['__cn_apply__'] = {
      'class_type': 'ControlNetApplyAdvanced',
      '_meta': {'title': 'Apply ControlNet'},
      'inputs': {
        'positive': positive,
        'negative': negative,
        'control_net': controlNet,
        'image': controlImage,
        'strength': strength,
        'start_percent': _poseStartPercent,
        'end_percent': endPercent,
      },
    };
    inputs['positive'] = ['__cn_apply__', 0];
    inputs['negative'] = ['__cn_apply__', 1];
  }

  // ── LoRA source detection ───────────────────────────────────
  // Returns (modelNodeId, modelOutput, clipNodeId, clipOutput), or null if
  // no recognisable model loader is present in the workflow.
  //
  // Flux:  UNETLoader[0]=model, DualCLIPLoader[0]=clip (separate nodes)
  // Pony:  CheckpointLoaderSimple[0]=model, [1]=clip, [2]=vae (same node)
  (String, int, String, int)? _findModelClipSources(
    Map<String, dynamic> wf,
  ) {
    String? unetId, dualClipId, ckptId;
    for (final e in wf.entries) {
      final cls = (e.value as Map?)?['class_type'] as String?;
      if (cls == 'UNETLoader') unetId = e.key;
      if (cls == 'DualCLIPLoader') dualClipId = e.key;
      if (cls == 'CheckpointLoaderSimple') ckptId = e.key;
    }
    if (unetId != null && dualClipId != null) {
      return (unetId, 0, dualClipId, 0);
    }
    if (ckptId != null) {
      return (ckptId, 0, ckptId, 1);
    }
    return null;
  }

  // ── Small helpers ───────────────────────────────────────────
  String _wsErrorMessage(Map<String, dynamic> data) {
    final type = data['exception_type'] ?? '';
    final msg = data['exception_message'] ?? data['node_type'] ?? 'unknown';
    final prefix = type.toString().isEmpty ? '' : '$type: ';
    return '[ComfyUI] chyba — $prefix$msg';
  }

  String _historyErrorMessage(Map<String, dynamic> hist) {
    final messages =
        ((hist['status'] as Map?)?['messages'] as List?) ?? const [];
    for (final m in messages.reversed) {
      if (m is List && m.isNotEmpty && '${m[0]}'.contains('error')) {
        return '[ComfyUI] chyba — ${jsonEncode(m.length > 1 ? m[1] : m[0])}';
      }
    }
    return '[ComfyUI] generování selhalo';
  }

  @override
  void dispose() => _client.close();
}

/// Transport failure while downloading a finished mesh — resumable, because
/// the artifacts are durable on the server (see [ComfyUIService.followMesh]).
class _MeshDownloadFailure implements Exception {
  final String detail;
  const _MeshDownloadFailure(this.detail);
  @override
  String toString() => 'MeshDownloadFailure($detail)';
}
