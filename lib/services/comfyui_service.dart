import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, WebSocket;
import 'dart:math';
import 'dart:typed_data';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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

  static const _baseUrl = 'http://192.168.88.66:8188';
  static const _wsUrl = 'ws://192.168.88.66:8188/ws';
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _txt2imgAsset = 'assets/comfyui/flux_manga_txt2img.api.json';
  static const _img2imgAsset = 'assets/comfyui/flux_manga_img2img.api.json';

  static const _submitTimeout = Duration(seconds: 30);
  static const _pollTimeout = Duration(seconds: 15);
  static const _pollInterval = Duration(seconds: 2);
  static const _wsConnectTimeout = Duration(seconds: 10);
  static const _downloadTimeout = Duration(seconds: 120);

  final String _clientId = const Uuid().v4();
  final http.Client _client = _makeClient();
  final Map<String, Map<String, dynamic>> _templateCache = {};

  static http.Client _makeClient() {
    try {
      if (Platform.isAndroid) return CronetClient.defaultCronetEngine();
    } catch (_) {}
    return http.Client();
  }

  @override
  String get id => kBackendComfyUI;

  @override
  String get label => 'ComfyUI';

  // ── Auth headers ────────────────────────────────────────────
  Map<String, String> get _authHeaders {
    if (_cfId.isEmpty || _cfSecret.isEmpty) return const {};
    return {
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    };
  }

  Map<String, String> get _jsonHeaders =>
      {..._authHeaders, 'Content-Type': 'application/json'};

  // ── Public backend API ──────────────────────────────────────
  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    final tpl = await _template(_txt2imgAsset);
    final wf = _prepare(tpl, prompt: prompt, batch: n);
    yield* _run(wf);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    final imageName = await _uploadImage(image);
    final tpl = await _template(_img2imgAsset);
    final wf = _prepare(tpl, prompt: prompt, batch: n, imageName: imageName);
    yield* _run(wf);
  }

  // ── Orchestration: enqueue → progress (WS|poll) → download ───
  Stream<GenEvent> _run(Map<String, dynamic> workflow) async* {
    final promptId = await _queuePrompt(workflow);
    yield const GenQueued(0);

    // Prefer the websocket for true per-step progress; fall back to polling
    // /history + /queue if the WS can't be established (e.g. CF Access blocks
    // the upgrade, or on platforms without dart:io sockets).
    WebSocket? ws;
    try {
      ws = await WebSocket.connect('$_wsUrl?clientId=$_clientId',
              headers: _authHeaders)
          .timeout(_wsConnectTimeout);
    } catch (e) {
      debugPrint('[comfy] ws connect failed ($e) — polling instead');
      ws = null;
    }

    var finished = false;
    if (ws != null) {
      var started = false;
      try {
        await for (final raw in ws) {
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
                final remaining = ((data['status'] as Map?)?['exec_info']
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
    while (true) {
      await Future.delayed(_pollInterval);

      Map<String, dynamic>? hist;
      try {
        hist = await _history(promptId);
      } catch (e) {
        debugPrint('[comfy] poll /history error ($e) — retrying');
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
      yield const GenFailed('ComfyUI: výsledek nenalezen (history prázdná)');
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
      yield const GenFailed('ComfyUI: žádné výstupní obrázky ve workflow');
      return;
    }

    final out = <Uint8List>[];
    for (var i = 0; i < refs.length; i++) {
      yield GenDownloading(i, refs.length);
      final r = refs[i];
      out.add(await _view(
        r['filename'] as String,
        (r['subfolder'] as String?) ?? '',
        (r['type'] as String?) ?? 'output',
      ));
    }
    yield GenComplete(out);
  }

  // ── ComfyUI REST primitives ─────────────────────────────────
  Future<String> _queuePrompt(Map<String, dynamic> workflow) async {
    final resp = await _client
        .post(
          Uri.parse('$_baseUrl/prompt'),
          headers: _jsonHeaders,
          body: jsonEncode({'prompt': workflow, 'client_id': _clientId}),
        )
        .timeout(_submitTimeout);
    debugPrint('[comfy] POST /prompt → ${resp.statusCode}');
    if (resp.statusCode != 200) {
      throw Exception('ComfyUI /prompt HTTP ${resp.statusCode}: '
          '${_snippet(resp.body)}');
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
      String filename, String subfolder, String type) async {
    final uri = Uri.parse('$_baseUrl/view').replace(queryParameters: {
      'filename': filename,
      'subfolder': subfolder,
      'type': type,
    });
    final resp =
        await _client.get(uri, headers: _authHeaders).timeout(_downloadTimeout);
    debugPrint('[comfy] GET /view $filename → ${resp.statusCode} '
        '(${resp.bodyBytes.length} bytes)');
    if (resp.statusCode != 200) {
      throw Exception('ComfyUI /view HTTP ${resp.statusCode} for $filename');
    }
    return resp.bodyBytes;
  }

  Future<String> _uploadImage(Uint8List bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload/image'))
      ..headers.addAll(_authHeaders)
      ..fields['overwrite'] = 'true'
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: 'ol1n_input_${DateTime.now().millisecondsSinceEpoch}.png',
      ));
    final streamed = await _client.send(req).timeout(_submitTimeout);
    final resp = await http.Response.fromStream(streamed);
    debugPrint('[comfy] POST /upload/image → ${resp.statusCode}');
    if (resp.statusCode != 200) {
      throw Exception('ComfyUI /upload/image HTTP ${resp.statusCode}: '
          '${_snippet(resp.body)}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final name = json['name'] as String;
    final subfolder = json['subfolder'] as String? ?? '';
    return subfolder.isEmpty ? name : '$subfolder/$name';
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
            body: jsonEncode(
                {'free_memory': true, 'unload_models': unloadModels}),
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
  ///   • a latent batch node (EmptySD3LatentImage / EmptyLatentImage /
  ///     RepeatLatentBatch) whose batch size = number of variants
  ///   • a sampler node carrying `seed` / `noise_seed`
  Map<String, dynamic> _prepare(
    Map<String, dynamic> template, {
    required String prompt,
    required int batch,
    String? imageName,
  }) {
    final wf = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
    final seed = Random().nextInt(1 << 31);

    for (final entry in wf.values) {
      final node = (entry as Map).cast<String, dynamic>();
      final cls = node['class_type'] as String?;
      final inputs = (node['inputs'] as Map?)?.cast<String, dynamic>();
      if (inputs == null) continue;

      inputs.forEach((key, value) {
        if (value == '__PROMPT__') inputs[key] = prompt;
        if (value == '__IMAGE__' && imageName != null) inputs[key] = imageName;
      });

      switch (cls) {
        case 'EmptySD3LatentImage':
        case 'EmptyLatentImage':
          if (inputs.containsKey('batch_size')) inputs['batch_size'] = batch;
        case 'RepeatLatentBatch':
          if (inputs.containsKey('amount')) inputs['amount'] = batch;
      }
      if (inputs.containsKey('seed')) inputs['seed'] = seed;
      if (inputs.containsKey('noise_seed')) inputs['noise_seed'] = seed;
    }
    return wf;
  }

  // ── Small helpers ───────────────────────────────────────────
  String _wsErrorMessage(Map<String, dynamic> data) {
    final type = data['exception_type'] ?? '';
    final msg = data['exception_message'] ?? data['node_type'] ?? 'unknown';
    final prefix = type.toString().isEmpty ? '' : '$type: ';
    return 'ComfyUI chyba — $prefix$msg';
  }

  String _historyErrorMessage(Map<String, dynamic> hist) {
    final messages = ((hist['status'] as Map?)?['messages'] as List?) ?? const [];
    for (final m in messages.reversed) {
      if (m is List && m.isNotEmpty && '${m[0]}'.contains('error')) {
        return 'ComfyUI chyba — ${jsonEncode(m.length > 1 ? m[1] : m[0])}';
      }
    }
    return 'ComfyUI: generování selhalo';
  }

  String _snippet(String body) {
    final s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  @override
  void dispose() => _client.close();
}
