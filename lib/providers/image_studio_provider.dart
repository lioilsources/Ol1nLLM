import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gen_node.dart';
import '../models/image_model.dart';
import '../models/image_session.dart';
import '../models/pose_template.dart';
import '../services/comfyui_service.dart';
import '../services/finetune_export_service.dart';
import '../services/flux_kontext_nim_service.dart';
import '../services/flux_nim_service.dart';
import '../services/image_backend.dart';

final imageStudioProvider =
    StateNotifierProvider<ImageStudioNotifier, ImageStudioState>(
      (ref) => ImageStudioNotifier(),
    );

/// How many candidates ComfyUI produces per round (native batch, free).
/// NIM backends override [ImageBackend.variantCount] to 1.
const kVariantCount = 4;

class ImageStudioState {
  /// Every round ever produced this session (the refinement tree).
  final List<GenNode> nodes;

  /// Node currently shown in the grid.
  final String? currentNodeId;

  /// Image selected within the current node — the base for the next refine.
  final String? selectedImageId;

  /// Active image model id (see [kImageModels]) — implies the backend.
  final String modelId;

  /// LoRAs available on the ComfyUI server (unfiltered).
  final List<String> availableLoras;

  /// Currently selected LoRA name, or null for no LoRA.
  final String? selectedLora;

  /// Selected ControlNet pose template id (see [kPoseTemplates]), or null.
  final String? selectedPoseId;

  /// Last error surfaced to the user (for a one-shot snackbar).
  final String? error;

  /// One-shot info message (e.g. export success snackbar).
  final String? info;

  /// All persisted sessions (sorted newest-first).
  final List<ImageSession> sessions;

  /// ID of the session currently being edited (null = unsaved new session).
  final String? activeSessionId;

  /// Session currently being exported to the FINETUNE gallery, and blob-upload
  /// progress in 0..1 (null = manifest phase / indeterminate).
  final String? exportingSessionId;
  final double? exportProgress;

  const ImageStudioState({
    this.nodes = const [],
    this.currentNodeId,
    this.selectedImageId,
    this.modelId = kDefaultImageModelId,
    this.availableLoras = const [],
    this.selectedLora,
    this.selectedPoseId,
    this.error,
    this.info,
    this.sessions = const [],
    this.activeSessionId,
    this.exportingSessionId,
    this.exportProgress,
  });

  ImageModelSpec get model => imageModelById(modelId);

  /// LoRAs compatible with the active model's family.
  List<String> get filteredLoras =>
      lorasForFamily(availableLoras, model.loraFamily);

  GenNode? get current {
    final id = currentNodeId;
    if (id == null) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// True while *any* node is generating — the studio runs one job at a time,
  /// so this globally locks input/new-session/retry until it finishes. (The
  /// per-node progress banner keys off the individual node's status instead.)
  bool get isBusy => nodes.any((n) => n.status == GenStatus.generating);

  /// Root→current chain, for the breadcrumb.
  List<GenNode> get path {
    final byId = {for (final n in nodes) n.id: n};
    final out = <GenNode>[];
    GenNode? node = current;
    while (node != null) {
      out.insert(0, node);
      final pid = node.parentId;
      node = pid == null ? null : byId[pid];
    }
    return out;
  }

  ImageStudioState copyWith({
    List<GenNode>? nodes,
    String? currentNodeId,
    String? selectedImageId,
    bool clearSelected = false,
    String? modelId,
    List<String>? availableLoras,
    String? selectedLora,
    bool clearLora = false,
    String? selectedPoseId,
    bool clearPose = false,
    String? error,
    bool clearError = false,
    String? info,
    bool clearInfo = false,
    List<ImageSession>? sessions,
    String? activeSessionId,
    bool clearActiveSessionId = false,
    String? exportingSessionId,
    double? exportProgress,
    bool clearExporting = false,
  }) => ImageStudioState(
    nodes: nodes ?? this.nodes,
    currentNodeId: currentNodeId ?? this.currentNodeId,
    selectedImageId: clearSelected
        ? null
        : (selectedImageId ?? this.selectedImageId),
    modelId: modelId ?? this.modelId,
    availableLoras: availableLoras ?? this.availableLoras,
    selectedLora: clearLora ? null : (selectedLora ?? this.selectedLora),
    selectedPoseId: clearPose ? null : (selectedPoseId ?? this.selectedPoseId),
    error: clearError ? null : (error ?? this.error),
    info: clearInfo ? null : (info ?? this.info),
    sessions: sessions ?? this.sessions,
    activeSessionId: clearActiveSessionId
        ? null
        : (activeSessionId ?? this.activeSessionId),
    exportingSessionId: clearExporting
        ? null
        : (exportingSessionId ?? this.exportingSessionId),
    exportProgress: clearExporting
        ? null
        : (exportProgress ?? this.exportProgress),
  );
}

class ImageStudioNotifier extends StateNotifier<ImageStudioState>
    with WidgetsBindingObserver {
  ImageStudioNotifier() : super(const ImageStudioState()) {
    WidgetsBinding.instance.addObserver(this);
    _loadLoras();
    unawaited(_init());
    unawaited(_deleteLegacyBox());
  }

  /// Resolve the image directory and publish it to [GenImage.baseDir] before
  /// loading sessions, so the first render of restored history resolves file
  /// paths against the current launch's container prefix.
  Future<void> _init() async {
    final dir = await _dirFuture;
    GenImage.baseDir = dir.path;
    await _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumeInFlightJob();
  }

  /// Silently removes the old v1 box file that stored full base64 PNG blobs.
  /// Uses direct file I/O to avoid triggering Hive reads (which would OOM).
  Future<void> _deleteLegacyBox() async {
    try {
      final dir = (await getApplicationDocumentsDirectory()).path;
      for (final suffix in ['.hive', '.hive.lock']) {
        try { await File('$dir/$_legacyBoxName$suffix').delete(); } catch (_) {}
      }
    } catch (_) {}
  }

  // v2: images stored as files, box holds only paths — old v1 box had full
  // base64 PNG blobs and caused OOM; new name sidesteps the old file entirely.
  static const _boxName = 'image_sessions_v2';
  static const _legacyBoxName = 'image_sessions';
  static const _key = 'all';

  /// Backoff before re-attaching to a job after a transient interruption
  /// (suspend / network blip), and the cap on consecutive resume attempts
  /// before we give up and surface a real error.
  static const _interruptBackoff = Duration(seconds: 4);
  static const _maxInterruptRetries = 5;

  final ComfyUIService _comfyui = ComfyUIService();
  final FluxNimService _fluxNim = FluxNimService();
  final FluxKontextNimService _fluxKontextNim = FluxKontextNimService();
  final FinetuneExportService _finetuneExport = FinetuneExportService();

  final Map<String, StreamSubscription<GenEvent>> _activeSubs = {};
  final Map<String, Completer<void>> _activeCompleters = {};

  /// Consecutive transient interruptions while trying to finish one job. Reset
  /// on any real progress; capped by [_maxInterruptRetries].
  int _interruptRetries = 0;

  late final Future<Directory> _dirFuture = _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/image_studio');
    await dir.create(recursive: true);
    return dir;
  }

  ImageBackend get _backend => switch (state.model.kind) {
    ImageBackendKind.fluxNim => _fluxNim,
    ImageBackendKind.fluxKontextNim => _fluxKontextNim,
    ImageBackendKind.comfyUi => _comfyui,
  };

  /// Re-attach to in-flight jobs after iOS suspension or app restart.
  void _resumeInFlightJob() {
    final backend = _backend;
    for (final node in state.nodes.where(
      (n) => n.status == GenStatus.generating && n.jobId != null,
    )) {
      if (_activeSubs.containsKey(node.id)) continue;
      unawaited(_runAsync(node.id, () => backend.follow(node.jobId!)));
    }
  }

  /// Push a model's ComfyUI preset + LoRA + pose down to the service. LoRAs
  /// that don't belong to the model's family are dropped (returned as null).
  /// Family membership is judged by name so it also works before the server
  /// LoRA list has loaded (session restore). Poses are dropped for models
  /// without OpenPose ControlNet support (NIM backends, flux-manga, SD 1.5).
  (String? lora, String? poseId) _applyModelToServices(
    String modelId,
    String? lora,
    String? poseId,
  ) {
    final spec = imageModelById(modelId);
    final keepLora =
        lora != null && lorasForFamily([lora], spec.loraFamily).isNotEmpty;
    final appliedLora = keepLora ? lora : null;
    final pose = spec.supportsPose ? poseById(poseId) : null;
    if (spec.kind == ImageBackendKind.comfyUi) {
      _comfyui.setPreset(spec.preset!);
    }
    _comfyui.setLora(appliedLora);
    _comfyui.setPose(pose?.asset);
    return (appliedLora, pose?.id);
  }

  void setModel(String id) {
    final (lora, poseId) =
        _applyModelToServices(id, state.selectedLora, state.selectedPoseId);
    state = state.copyWith(
      modelId: id,
      selectedLora: lora,
      clearLora: lora == null,
      selectedPoseId: poseId,
      clearPose: poseId == null,
    );
  }

  void selectImage(String imageId) =>
      state = state.copyWith(selectedImageId: imageId);

  void navigateTo(String nodeId) =>
      state = state.copyWith(currentNodeId: nodeId, clearSelected: true);

  void newSession() {
    for (final sub in _activeSubs.values) {
      sub.cancel();
    }
    _activeSubs.clear();
    for (final c in _activeCompleters.values) {
      if (!c.isCompleted) c.complete();
    }
    _activeCompleters.clear();
    state = ImageStudioState(
      sessions: state.sessions,
      modelId: state.modelId,
      availableLoras: state.availableLoras,
      selectedLora: state.selectedLora,
      selectedPoseId: state.selectedPoseId,
    );
  }

  void selectSession(String id) {
    final session = state.sessions.firstWhere((s) => s.id == id);
    final (lora, poseId) = _applyModelToServices(
      session.modelId,
      session.selectedLora,
      session.selectedPoseId,
    );
    state = ImageStudioState(
      sessions: state.sessions,
      activeSessionId: id,
      nodes: session.nodes.toList(),
      currentNodeId: session.currentNodeId,
      selectedLora: lora,
      selectedPoseId: poseId,
      modelId: session.modelId,
      availableLoras: state.availableLoras,
    );
  }

  Future<void> deleteSession(String id) async {
    final toDelete = state.sessions.where((s) => s.id == id).firstOrNull;
    if (toDelete != null) {
      for (final node in toDelete.nodes) {
        for (final image in node.images) {
          try { await File(image.filePath).delete(); } catch (_) {}
        }
      }
    }
    final updated = state.sessions.where((s) => s.id != id).toList();
    if (state.activeSessionId == id) {
      final next = updated.isNotEmpty ? updated.first : null;
      if (next != null) {
        final (lora, poseId) = _applyModelToServices(
          next.modelId,
          next.selectedLora,
          next.selectedPoseId,
        );
        state = ImageStudioState(
          sessions: updated,
          activeSessionId: next.id,
          nodes: next.nodes.toList(),
          currentNodeId: next.currentNodeId,
          selectedLora: lora,
          selectedPoseId: poseId,
          modelId: next.modelId,
          availableLoras: state.availableLoras,
        );
      } else {
        state = ImageStudioState(
          sessions: const [],
          modelId: state.modelId,
          availableLoras: state.availableLoras,
        );
      }
    } else {
      state = state.copyWith(sessions: updated);
    }
    await _persistSessions(updated);
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw == null) return;
      final sessions = (jsonDecode(raw as String) as List)
          .map((e) => ImageSession.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (sessions.isNotEmpty) {
        final latest = sessions.first;
        final (lora, poseId) = _applyModelToServices(
          latest.modelId,
          latest.selectedLora,
          latest.selectedPoseId,
        );
        state = ImageStudioState(
          sessions: sessions,
          activeSessionId: latest.id,
          nodes: latest.nodes.toList(),
          currentNodeId: latest.currentNodeId,
          selectedLora: lora,
          selectedPoseId: poseId,
          modelId: latest.modelId,
          availableLoras: state.availableLoras,
        );
        _resumeInFlightJob();
      } else {
        state = state.copyWith(sessions: sessions);
      }
    } catch (e) {
      debugPrint('ImageStudioNotifier._load error: $e');
    }
  }

  Future<void> _save() async {
    if (state.nodes.isEmpty) return;
    // Carry export bookkeeping over from the stored session — _save() rebuilds
    // the session object, and losing exportedAt would mark every saved session
    // as never-exported.
    final existing = state.sessions
        .where((s) => s.id == state.activeSessionId)
        .firstOrNull;
    final session = ImageSession.create(
      id: state.activeSessionId,
      nodes: state.nodes,
      currentNodeId: state.currentNodeId,
      selectedLora: state.selectedLora,
      selectedPoseId: state.selectedPoseId,
      modelId: state.modelId,
      exportedAt: existing?.exportedAt,
      exportedImageCount: existing?.exportedImageCount,
    );
    final updated = [
      session,
      ...state.sessions.where((s) => s.id != session.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(sessions: updated, activeSessionId: session.id);
    await _persistSessions(updated);
  }

  Future<void> _persistSessions(List<ImageSession> sessions) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_key, jsonEncode(sessions.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('ImageStudioNotifier._persistSessions error: $e');
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clearInfo() => state = state.copyWith(clearInfo: true);

  /// Export a session to the FINETUNE gallery backend. One export at a time;
  /// success stamps exportedAt/exportedImageCount on the session (persisted),
  /// failure surfaces through the standard error snackbar.
  Future<void> exportSession(String sessionId) async {
    if (state.exportingSessionId != null) return;
    // Exporting the live session: persist first so the stored session object
    // reflects the newest nodes.
    if (sessionId == state.activeSessionId) await _save();
    final session =
        state.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return;
    final imageCount = session.readyImageCount;
    if (imageCount == 0) {
      state = state.copyWith(error: 'Není co exportovat – žádné hotové obrázky');
      return;
    }
    state = state.copyWith(exportingSessionId: sessionId, clearError: true);
    try {
      final summary = await _finetuneExport.exportSession(
        session,
        onProgress: (done, total) {
          if (!mounted) return;
          state = state.copyWith(
            exportProgress: total == 0 ? 1.0 : done / total,
          );
        },
      );
      if (!mounted) return;
      final updated = [
        for (final s in state.sessions)
          s.id == sessionId
              ? s.copyWithExport(
                  exportedAt: DateTime.now(),
                  exportedImageCount: imageCount,
                )
              : s,
      ];
      state = state.copyWith(
        sessions: updated,
        clearExporting: true,
        info: 'Exportováno ${summary.images} obrázků '
            '(${summary.newBlobs} nových)',
      );
      await _persistSessions(updated);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        clearExporting: true,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void setLora(String? loraName) {
    _comfyui.setLora(loraName);
    state = state.copyWith(selectedLora: loraName, clearLora: loraName == null);
  }

  void setPose(String? poseId) {
    final pose = poseById(poseId);
    _comfyui.setPose(pose?.asset);
    state = state.copyWith(
      selectedPoseId: pose?.id,
      clearPose: pose == null,
    );
  }

  Future<void> _loadLoras() async {
    final loras = await _comfyui.fetchLoras();
    state = state.copyWith(availableLoras: loras);
  }

  /// Fresh base seed for one generation round. Owned by the provider (not the
  /// backends) so it can be persisted on the node before the request starts.
  static int _newSeed() => Random().nextInt(1 << 31);

  /// Build a generating node with a snapshot of everything the request will
  /// actually use. Sampler/latent fields are recorded only for generic-template
  /// ComfyUI models (ckptName != null) — dedicated workflows (flux-manga) and
  /// NIM services use baked-in/constant values recoverable from [modelId], so
  /// echoing preset defaults here would record values that were never applied.
  GenNode _createNodeWithMeta({
    String? id,
    String? parentId,
    String? sourceImageId,
    required String prompt,
    required int seed,
    required bool isImg2img,
  }) {
    final spec = state.model;
    final preset = spec.preset;
    final patched = preset?.ckptName != null;
    final poseId = state.selectedPoseId;
    final poseActive = poseId != null && patched;
    return GenNode.create(
      id: id,
      parentId: parentId,
      sourceImageId: sourceImageId,
      prompt: prompt,
      modelId: spec.id,
      loraName: state.selectedLora,
      poseId: poseId,
      seed: seed,
      negativePrompt: patched && preset!.negativePrompt.isNotEmpty
          ? preset.negativePrompt
          : null,
      positivePrefix:
          preset != null && preset.positivePrefix.isNotEmpty
              ? preset.positivePrefix
              : null,
      // img2img latents come from VAEEncode of the source image, so recorded
      // dimensions stay null (source-derived) even when a pose is active.
      width: patched && !isImg2img
          ? (poseActive ? kPoseWidth : preset!.width)
          : null,
      height: patched && !isImg2img
          ? (poseActive ? kPoseHeight : preset!.height)
          : null,
      steps: patched ? preset!.steps : null,
      cfg: patched ? preset!.cfg : null,
      denoise: patched
          ? (isImg2img
              ? (poseActive ? kPoseEditDenoise : preset!.img2imgDenoise)
              : 1.0)
          : null,
      samplerName: patched ? preset!.samplerName : null,
      scheduler: patched ? preset!.scheduler : null,
    );
  }

  /// Round 1: [kVariantCount] text→image candidates from [prompt].
  Future<void> generate(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _interruptRetries = 0;
    final seed = _newSeed();
    final node = _createNodeWithMeta(prompt: text, seed: seed, isImg2img: false);
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _backend.generate(prompt: text, n: _backend.variantCount, seed: seed),
    );
  }

  /// Start a new root from a user-supplied photo (camera or gallery) instead
  /// of a text→image generation. The photo becomes a ready root node holding
  /// that single image, and is auto-selected so the next message refines it
  /// (img2img) — i.e. the photo is uploaded to ComfyUI only once the user
  /// describes a change.
  Future<void> startFromImage(Uint8List bytes) async {
    final dir = await _dirFuture;
    final image = await GenImage.save(bytes, dir);
    final node = GenNode.create(prompt: '', origin: 'upload').copyWith(
      status: GenStatus.ready,
      images: [image],
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      selectedImageId: image.id,
      clearError: true,
    );
    await _save();
  }

  /// Effective img2img prompt: [text] first, then ancestor prompts walking
  /// parent→root — newest to oldest. Earlier tokens carry more CLIP weight,
  /// so the new instruction has the highest priority and can override what
  /// older rounds asked for. Only ancestors generated with the *same model*
  /// as the current one are included (other models' prompt styles are
  /// incompatible); empty prompts (photo roots) and exact duplicates are
  /// dropped, a duplicate keeping its newest (earliest) position. Nodes keep
  /// only their own [text] — the chain is recomposed at request time.
  String _chainedPrompt(String? parentId, String text) {
    final byId = {for (final n in state.nodes) n.id: n};
    final parts = <String>[];
    final seen = <String>{};
    final own = text.trim();
    if (own.isNotEmpty && seen.add(own)) parts.add(own);
    GenNode? node = parentId == null ? null : byId[parentId];
    while (node != null) {
      final p = node.prompt.trim();
      if (p.isNotEmpty && node.modelId == state.modelId && seen.add(p)) {
        parts.add(p);
      }
      final pid = node.parentId;
      node = pid == null ? null : byId[pid];
    }
    return parts.join(', ');
  }

  /// Round 2+: [kVariantCount] edits of the selected image.
  Future<void> refine(String prompt) async {
    final text = prompt.trim();
    final base = _imageById(state.selectedImageId);
    if (text.isEmpty || base == null) return;
    _interruptRetries = 0;
    final seed = _newSeed();
    final chained = _chainedPrompt(state.currentNodeId, text);
    final node = _createNodeWithMeta(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: text,
      seed: seed,
      isImg2img: true,
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _backend.edit(
        image: base.bytes,
        prompt: chained,
        n: _backend.variantCount,
        seed: seed,
      ),
    );
  }

  /// Re-run a failed (or finished) node with its original prompt.
  ///
  /// The retry runs against the *current* model/LoRA/pose (they may have
  /// changed since the node was created), so the node's metadata snapshot is
  /// rebuilt too — keeping it truthful — while id/parent links and any old
  /// images are preserved.
  Future<void> retry(String nodeId) async {
    final node = _nodeById(nodeId);
    if (node == null || node.status == GenStatus.generating) return;
    _interruptRetries = 0;
    final seed = _newSeed();
    final refreshed = _createNodeWithMeta(
      id: node.id,
      parentId: node.parentId,
      sourceImageId: node.sourceImageId,
      prompt: node.prompt,
      seed: seed,
      isImg2img: !node.isRoot,
    ).copyWith(images: node.images);
    _patch(nodeId, (_) => refreshed);
    if (node.isRoot) {
      await _runAsync(
        nodeId,
        () => _backend.generate(
          prompt: node.prompt,
          n: _backend.variantCount,
          seed: seed,
        ),
      );
    } else {
      final base = _imageById(node.sourceImageId);
      if (base == null) {
        _patch(
          nodeId,
          (n) =>
              n.copyWith(status: GenStatus.error, error: 'Source image gone'),
        );
        return;
      }
      // Recomposed against the *current* model, consistent with the metadata
      // snapshot rebuild above.
      final chained = _chainedPrompt(node.parentId, node.prompt);
      await _runAsync(
        nodeId,
        () => _backend.edit(
          image: base.bytes,
          prompt: chained,
          n: _backend.variantCount,
          seed: seed,
        ),
      );
    }
  }

  /// Cancel the in-flight generation: stop consuming events, ask the backend
  /// to interrupt server-side (ComfyUI supports this), and mark the node.
  void cancel() {
    _interruptRetries = 0;
    final ids = List<String>.from(_activeSubs.keys);
    for (final id in ids) {
      _activeSubs.remove(id)?.cancel();
      final c = _activeCompleters.remove(id);
      if (!(c?.isCompleted ?? true)) c!.complete();
      final node = _nodeById(id);
      if (node?.status == GenStatus.generating) {
        _patch(
          id,
          (n) => n.copyWith(
            status: GenStatus.error,
            error: 'Zrušeno',
            clearProgress: true,
            clearJobId: true,
          ),
        );
        // Persist so the cancellation sticks across an app restart instead of
        // resuming from a stale generating snapshot.
        unawaited(_save());
      }
    }
    unawaited(_backend.interrupt());
  }

  Future<void> _runAsync(String nodeId, Stream<GenEvent> Function() run) async {
    final completer = Completer<void>();
    _activeCompleters[nodeId] = completer;
    // Set to true when GenComplete schedules its async save so onDone skips
    // the redundant finish() call — the async save calls finish() itself.
    bool completedByEvent = false;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    void fail(String msg) {
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.error,
          error: msg,
          clearProgress: true,
          clearJobId: true,
        ),
      );
      // Persist the terminal error so a restart doesn't resurrect a dead job
      // from a stale (still-generating) Hive snapshot.
      unawaited(_save());
      state = state.copyWith(error: msg);
    }

    // Transient drop (iOS suspend / network blip): keep the node alive (status
    // stays generating), persist so resume/restart can re-attach, tear down the
    // dead stream, and re-attach after a backoff. No red error.
    void handleInterruption(String jobId) {
      _patch(
        nodeId,
        (n) => n.copyWith(
          jobId: jobId,
          clearProgress: true,
          progressLabel: 'Spojení přerušeno, obnovuji…',
        ),
      );
      unawaited(_save());
      _activeSubs.remove(nodeId);
      _activeCompleters.remove(nodeId);
      finish();
      if (_interruptRetries++ < _maxInterruptRetries) {
        Future.delayed(_interruptBackoff, () {
          if (mounted) _resumeInFlightJob();
        });
      } else {
        fail('[ImageStudio] nepodařilo se obnovit spojení – zkus to znovu');
      }
    }

    _activeSubs[nodeId] = run().listen(
      (event) {
        switch (event) {
          case GenSubmitted(:final jobId):
            // Persist jobId so follow() can resume after iOS suspension.
            _patch(nodeId, (n) => n.copyWith(jobId: jobId));
            unawaited(_save());
          case GenQueued(:final position):
            // A successful queue-position poll ⇒ the connection is healthy.
            _interruptRetries = 0;
            _patch(
              nodeId,
              (n) => n.copyWith(
                clearProgress: true,
                progressLabel: position > 0
                    ? 'Ve frontě: $position'
                    : 'Ve frontě…',
              ),
            );
          case GenRunning(:final fraction):
            // Real progress ⇒ the connection is healthy again.
            _interruptRetries = 0;
            _patch(
              nodeId,
              (n) => n.copyWith(
                progress: fraction,
                clearProgress: fraction == null,
                progressLabel: fraction == null
                    ? 'Generování…'
                    : 'Generování ${(fraction * 100).round()} %',
              ),
            );
          case GenDownloading(:final done, :final total):
            _patch(
              nodeId,
              (n) => n.copyWith(
                progress: total > 0 ? done / total : null,
                progressLabel: 'Stahování ${done + 1}/$total',
              ),
            );
          case GenComplete(:final images):
            completedByEvent = true;
            unawaited(() async {
              final dir = await _dirFuture;
              final genImages = await Future.wait([
                for (final bytes in images) GenImage.save(bytes, dir),
              ]);
              if (!mounted) return;
              _patch(
                nodeId,
                (n) => n.copyWith(
                  status: GenStatus.ready,
                  images: genImages,
                  clearError: true,
                  clearProgress: true,
                  clearJobId: true,
                ),
              );
              unawaited(_save());
              finish();
            }());
          case GenFailed(:final message):
            fail(message);
          case GenInterrupted(:final jobId):
            handleInterruption(jobId);
        }
      },
      onError: (Object e) {
        // A stray error reached the stream (should be rare — backends classify
        // transport errors as GenInterrupted). If the job is still alive, treat
        // it as a resumable interruption rather than nuking the jobId.
        final node = _nodeById(nodeId);
        final jobId = node?.jobId;
        if (node?.status == GenStatus.generating && jobId != null) {
          handleInterruption(jobId);
          return;
        }
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        fail(msg);
        _activeSubs.remove(nodeId);
        _activeCompleters.remove(nodeId);
        finish();
      },
      onDone: () {
        _activeSubs.remove(nodeId);
        _activeCompleters.remove(nodeId);
        if (!completedByEvent) finish();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  GenImage? _imageById(String? id) {
    if (id == null) return null;
    for (final n in state.nodes) {
      for (final img in n.images) {
        if (img.id == id) return img;
      }
    }
    return null;
  }

  GenNode? _nodeById(String id) {
    for (final n in state.nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _patch(String nodeId, GenNode Function(GenNode) f) {
    state = state.copyWith(
      nodes: [
        for (final n in state.nodes)
          if (n.id == nodeId) f(n) else n,
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _activeSubs.values) {
      sub.cancel();
    }
    _activeSubs.clear();
    _comfyui.dispose();
    _fluxNim.dispose();
    _fluxKontextNim.dispose();
    _finetuneExport.dispose();
    super.dispose();
  }
}
