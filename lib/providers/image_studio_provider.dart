import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gen_node.dart';
import '../models/image_session.dart';
import '../services/comfyui_service.dart';
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

  /// Active image backend id (always kBackendComfyUI — kept for forward
  /// compatibility if more backends return later).
  final String backendId;

  /// LoRAs available on the ComfyUI server.
  final List<String> availableLoras;

  /// Currently selected LoRA name, or null for no LoRA.
  final String? selectedLora;

  /// Active ComfyUI workflow / model family.
  final ComfyWorkflow workflow;

  /// Last error surfaced to the user (for a one-shot snackbar).
  final String? error;

  /// All persisted sessions (sorted newest-first).
  final List<ImageSession> sessions;

  /// ID of the session currently being edited (null = unsaved new session).
  final String? activeSessionId;

  const ImageStudioState({
    this.nodes = const [],
    this.currentNodeId,
    this.selectedImageId,
    this.backendId = kBackendComfyUI,
    this.availableLoras = const [],
    this.selectedLora,
    this.workflow = ComfyWorkflow.flux,
    this.error,
    this.sessions = const [],
    this.activeSessionId,
  });

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
    String? backendId,
    List<String>? availableLoras,
    String? selectedLora,
    bool clearLora = false,
    ComfyWorkflow? workflow,
    String? error,
    bool clearError = false,
    List<ImageSession>? sessions,
    String? activeSessionId,
    bool clearActiveSessionId = false,
  }) => ImageStudioState(
    nodes: nodes ?? this.nodes,
    currentNodeId: currentNodeId ?? this.currentNodeId,
    selectedImageId: clearSelected
        ? null
        : (selectedImageId ?? this.selectedImageId),
    backendId: backendId ?? this.backendId,
    availableLoras: availableLoras ?? this.availableLoras,
    selectedLora: clearLora ? null : (selectedLora ?? this.selectedLora),
    workflow: workflow ?? this.workflow,
    error: clearError ? null : (error ?? this.error),
    sessions: sessions ?? this.sessions,
    activeSessionId: clearActiveSessionId
        ? null
        : (activeSessionId ?? this.activeSessionId),
  );
}

class ImageStudioNotifier extends StateNotifier<ImageStudioState>
    with WidgetsBindingObserver {
  ImageStudioNotifier() : super(const ImageStudioState()) {
    WidgetsBinding.instance.addObserver(this);
    _loadLoras();
    _load();
    unawaited(_deleteLegacyBox());
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

  final ComfyUIService _comfyui = ComfyUIService();
  final FluxNimService _fluxNim = FluxNimService();
  final FluxKontextNimService _fluxKontextNim = FluxKontextNimService();

  StreamSubscription<GenEvent>? _activeSub;
  String? _activeNodeId;
  Completer<void>? _activeCompleter;

  late final Future<Directory> _dirFuture = _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/image_studio');
    await dir.create(recursive: true);
    return dir;
  }

  ImageBackend get _backend => switch (state.backendId) {
    kBackendFluxNim => _fluxNim,
    kBackendFluxKontextNim => _fluxKontextNim,
    _ => _comfyui,
  };

  /// Re-attach to an in-flight job after iOS suspension or app restart.
  ///
  /// Looks for the first generating node that has a persisted [GenNode.jobId]
  /// and calls the appropriate backend's [ImageBackend.follow]. A no-op if
  /// a generation is already active or no resumable node exists.
  void _resumeInFlightJob() {
    if (_activeSub != null) return;
    final node = state.nodes
        .where((n) => n.status == GenStatus.generating && n.jobId != null)
        .firstOrNull;
    if (node == null) return;
    final backend = switch (state.backendId) {
      kBackendFluxNim => _fluxNim,
      kBackendFluxKontextNim => _fluxKontextNim,
      _ => _comfyui,
    };
    unawaited(_runAsync(node.id, () => backend.follow(node.jobId!)));
  }

  void setBackend(String id) => state = state.copyWith(backendId: id);

  void selectImage(String imageId) =>
      state = state.copyWith(selectedImageId: imageId);

  void navigateTo(String nodeId) =>
      state = state.copyWith(currentNodeId: nodeId, clearSelected: true);

  void newSession() {
    _activeSub?.cancel();
    _activeSub = null;
    _activeNodeId = null;
    state = ImageStudioState(
      sessions: state.sessions,
      backendId: state.backendId,
      availableLoras: state.availableLoras,
      workflow: state.workflow,
      selectedLora: state.selectedLora,
    );
  }

  void selectSession(String id) {
    final session = state.sessions.firstWhere((s) => s.id == id);
    _comfyui.setLora(session.selectedLora);
    _comfyui.setWorkflow(session.workflow);
    state = ImageStudioState(
      sessions: state.sessions,
      activeSessionId: id,
      nodes: session.nodes.toList(),
      currentNodeId: session.currentNodeId,
      selectedLora: session.selectedLora,
      workflow: session.workflow,
      backendId: session.backendId,
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
        _comfyui.setLora(next.selectedLora);
        _comfyui.setWorkflow(next.workflow);
        state = ImageStudioState(
          sessions: updated,
          activeSessionId: next.id,
          nodes: next.nodes.toList(),
          currentNodeId: next.currentNodeId,
          selectedLora: next.selectedLora,
          workflow: next.workflow,
          backendId: next.backendId,
          availableLoras: state.availableLoras,
        );
      } else {
        state = ImageStudioState(
          sessions: const [],
          backendId: state.backendId,
          availableLoras: state.availableLoras,
          workflow: state.workflow,
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
        _comfyui.setLora(latest.selectedLora);
        _comfyui.setWorkflow(latest.workflow);
        state = ImageStudioState(
          sessions: sessions,
          activeSessionId: latest.id,
          nodes: latest.nodes.toList(),
          currentNodeId: latest.currentNodeId,
          selectedLora: latest.selectedLora,
          workflow: latest.workflow,
          backendId: latest.backendId,
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
    final session = ImageSession.create(
      id: state.activeSessionId,
      nodes: state.nodes,
      currentNodeId: state.currentNodeId,
      selectedLora: state.selectedLora,
      workflow: state.workflow,
      backendId: state.backendId,
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

  void setLora(String? loraName) {
    _comfyui.setLora(loraName);
    state = state.copyWith(selectedLora: loraName, clearLora: loraName == null);
  }

  void setWorkflow(ComfyWorkflow wf) {
    _comfyui.setWorkflow(wf);
    state = state.copyWith(workflow: wf);
  }

  Future<void> _loadLoras() async {
    final loras = await _comfyui.fetchLoras();
    state = state.copyWith(availableLoras: loras);
  }

  /// Round 1: [kVariantCount] text→image candidates from [prompt].
  Future<void> generate(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || state.isBusy) return;
    final node = GenNode.create(prompt: text);
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _backend.generate(prompt: text, n: _backend.variantCount),
    );
  }

  /// Start a new root from a user-supplied photo (camera or gallery) instead
  /// of a text→image generation. The photo becomes a ready root node holding
  /// that single image, and is auto-selected so the next message refines it
  /// (img2img) — i.e. the photo is uploaded to ComfyUI only once the user
  /// describes a change.
  Future<void> startFromImage(Uint8List bytes) async {
    if (state.isBusy) return;
    final dir = await _dirFuture;
    final image = await GenImage.save(bytes, dir);
    final node = GenNode.create(prompt: '').copyWith(
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

  /// Round 2+: [kVariantCount] edits of the selected image.
  Future<void> refine(String prompt) async {
    final text = prompt.trim();
    final base = _imageById(state.selectedImageId);
    if (text.isEmpty || base == null || state.isBusy) return;
    final node = GenNode.create(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: text,
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
        prompt: text,
        n: _backend.variantCount,
      ),
    );
  }

  /// Re-run a failed (or finished) node with its original prompt.
  Future<void> retry(String nodeId) async {
    if (state.isBusy) return;
    final node = _nodeById(nodeId);
    if (node == null || node.status == GenStatus.generating) return;
    _patch(
      nodeId,
      (n) => n.copyWith(
        status: GenStatus.generating,
        clearError: true,
        clearProgress: true,
      ),
    );
    if (node.isRoot) {
      await _runAsync(
        nodeId,
        () => _backend.generate(prompt: node.prompt, n: _backend.variantCount),
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
      await _runAsync(
        nodeId,
        () => _backend.edit(
          image: base.bytes,
          prompt: node.prompt,
          n: _backend.variantCount,
        ),
      );
    }
  }

  /// Cancel the in-flight generation: stop consuming events, ask the backend
  /// to interrupt server-side (ComfyUI supports this), and mark the node.
  void cancel() {
    final id = _activeNodeId;
    _activeSub?.cancel();
    _activeSub = null;
    _activeNodeId = null;
    unawaited(_backend.interrupt());
    if (id != null) {
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
      }
    }
    // Cancelling a subscription fires neither onDone nor onError, so release
    // the awaited future ourselves.
    if (!(_activeCompleter?.isCompleted ?? true)) _activeCompleter!.complete();
    _activeCompleter = null;
  }

  /// Consume a backend [GenEvent] stream, updating [nodeId] in place until a
  /// terminal event. Stored as the active subscription so [cancel] can stop it.
  Future<void> _runAsync(String nodeId, Stream<GenEvent> Function() run) async {
    await _activeSub?.cancel();
    _activeNodeId = nodeId;
    final completer = Completer<void>();
    _activeCompleter = completer;
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
      state = state.copyWith(error: msg);
    }

    _activeSub = run().listen(
      (event) {
        switch (event) {
          case GenSubmitted(:final jobId):
            // Persist jobId so follow() can resume after iOS suspension.
            _patch(nodeId, (n) => n.copyWith(jobId: jobId));
            unawaited(_save());
          case GenQueued(:final position):
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
        }
      },
      onError: (Object e) {
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        fail(msg);
        // cancelOnError stops the stream without an onDone — clean up here.
        _activeSub = null;
        if (_activeNodeId == nodeId) _activeNodeId = null;
        finish();
      },
      onDone: () {
        _activeSub = null;
        if (_activeNodeId == nodeId) _activeNodeId = null;
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
    _activeSub?.cancel();
    _comfyui.dispose();
    _fluxNim.dispose();
    _fluxKontextNim.dispose();
    super.dispose();
  }
}
