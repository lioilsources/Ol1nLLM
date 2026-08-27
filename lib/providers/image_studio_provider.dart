import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gen_node.dart';
import '../models/image_model.dart';
import '../models/image_session.dart';
import '../models/latent_bucket.dart';
import '../models/pose_template.dart';
import '../models/prompt_negatives.dart';
import '../models/style_preset.dart';
import '../models/video_scene.dart';
import '../services/comfyui_service.dart';
import '../services/finetune_export_service.dart';
import '../services/flux_kontext_nim_service.dart';
import '../services/flux_nim_service.dart';
import '../services/image_backend.dart';
import '../services/video_service.dart';

final imageStudioProvider =
    StateNotifierProvider<ImageStudioNotifier, ImageStudioState>(
      (ref) => ImageStudioNotifier(),
    );

/// How many candidates ComfyUI produces per round (native batch, free).
/// NIM backends override [ImageBackend.variantCount] to 1.
const kVariantCount = 4;

/// img2img denoise steps offered in the UI. The preset's own value (~0.72)
/// is the middle "běžná" option and stays the default; [kStyleEditDenoise]
/// is the one that actually lets an art style through — measured across
/// 10 models × 25 styles, at 0.72 the style barely lands, at 0.9 it does,
/// and the pose still holds because auto-depth keeps carrying it.
const kGentleEditDenoise = 0.5;
const kStyleEditDenoise = 0.9;

/// Model/LoRA/pose a node was generated with, reduced to what the app can
/// actually apply right now.
typedef NodeSettings = ({
  String modelId,
  String? lora,
  double loraStrength,
  String? poseId,
});

/// What the chips should show when the user navigates to [node].
///
/// Null means "leave the chips alone": the node carries no snapshot (a photo
/// root, or a session from before per-node metadata), or its model is gone
/// from the server — adopting a model the server can't run would put a chip
/// in front of the user that fails at enqueue time.
///
/// [installedLoras] empty means "unknown" (catalog not fetched yet), which
/// keeps the node's LoRA rather than dropping it; a LoRA that no longer fits
/// the model's lineage is dropped the same way [_applyModelToServices] does
/// it on a model switch.
NodeSettings? adoptableSettings(
  GenNode node, {
  required List<ImageModelSpec> availableModels,
  required List<String> installedLoras,
}) {
  final modelId = node.modelId;
  if (modelId == null) return null;
  if (!availableModels.any((m) => m.id == modelId)) return null;
  final spec = imageModelById(modelId);
  final lora = node.loraName;
  final loraUsable = lora != null &&
      (installedLoras.isEmpty || installedLoras.contains(lora)) &&
      lorasForFamily([lora], spec.loraFamily).isNotEmpty;
  return (
    modelId: modelId,
    lora: loraUsable ? lora : null,
    // Nodes from before v1.5.1 recorded the LoRA but not its strength.
    loraStrength: node.loraStrength ?? kDefaultLoraStrength,
    poseId: spec.supportsPose ? node.poseId : null,
  );
}

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
  ///
  /// This, [availableCheckpoints] and [availableScenes] are app-scoped, not
  /// session-scoped: every site that rebuilds the state from scratch
  /// (new/select/delete session, restore) has to carry ALL THREE over by hand,
  /// or the chips/actions silently empty out. Dropping [availableScenes] here
  /// is what hid the „Rozhýbat" button in 1.12.0 — the catalog loaded fine and
  /// _load() then rebuilt the state without it.
  final List<String> availableLoras;

  /// Checkpoints installed on the ComfyUI server. Empty = not (yet) known.
  final List<String> availableCheckpoints;

  /// Animation presets served by the video server („Rozhýbat"). Empty = the
  /// server is unreachable or has none; the studio then hides the action.
  /// App-scoped like [availableLoras] — carried over on every state rebuild.
  final List<VideoScene> availableScenes;

  /// Currently selected LoRA name, or null for no LoRA.
  final String? selectedLora;

  /// Strength the selected LoRA is applied with (model + clip).
  final double loraStrength;

  /// Selected ControlNet pose template id (see [kPoseTemplates]), or null.
  final String? selectedPoseId;

  /// Selected art-style preset id (see [kStylePresets]), or null. The block
  /// is appended to the prompt at request time and only the id is persisted.
  final String? selectedStyleId;

  /// img2img denoise chosen by the user, or null for the model preset's
  /// value. See [ComfyUIService.setEditDenoise].
  final double? editDenoise;

  /// Reference image for a pending repose round (the input bar is in repose
  /// mode while non-null). Transient UI state — never persisted, dropped by
  /// any full state rebuild (session switch/restore) — and mutually
  /// exclusive with [selectedImageId] (refine); the notifier keeps the two
  /// apart.
  final String? reposeSourceImageId;

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
    this.availableCheckpoints = const [],
    this.availableScenes = const [],
    this.selectedLora,
    this.loraStrength = kDefaultLoraStrength,
    this.selectedPoseId,
    this.selectedStyleId,
    this.editDenoise,
    this.reposeSourceImageId,
    this.error,
    this.info,
    this.sessions = const [],
    this.activeSessionId,
    this.exportingSessionId,
    this.exportProgress,
  });

  ImageModelSpec get model => imageModelById(modelId);

  /// Models offerable in the picker — curated registry minus entries whose
  /// checkpoint is missing on the server (the active one always stays).
  List<ImageModelSpec> get availableModels =>
      imageModelsFor(availableCheckpoints, keepId: modelId);

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

  /// Image with [id] anywhere in the tree, or null.
  GenImage? imageById(String? id) {
    if (id == null) return null;
    for (final n in nodes) {
      for (final img in n.images) {
        if (img.id == id) return img;
      }
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
    List<String>? availableCheckpoints,
    List<VideoScene>? availableScenes,
    String? selectedLora,
    bool clearLora = false,
    double? loraStrength,
    String? selectedPoseId,
    bool clearPose = false,
    String? selectedStyleId,
    bool clearStyle = false,
    double? editDenoise,
    bool clearEditDenoise = false,
    String? reposeSourceImageId,
    bool clearRepose = false,
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
    availableCheckpoints: availableCheckpoints ?? this.availableCheckpoints,
    availableScenes: availableScenes ?? this.availableScenes,
    selectedLora: clearLora ? null : (selectedLora ?? this.selectedLora),
    loraStrength: loraStrength ?? this.loraStrength,
    selectedPoseId: clearPose ? null : (selectedPoseId ?? this.selectedPoseId),
    selectedStyleId:
        clearStyle ? null : (selectedStyleId ?? this.selectedStyleId),
    editDenoise:
        clearEditDenoise ? null : (editDenoise ?? this.editDenoise),
    reposeSourceImageId: clearRepose
        ? null
        : (reposeSourceImageId ?? this.reposeSourceImageId),
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
    unawaited(_loadServerCatalog());
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
  final VideoService _video = VideoService();
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
    // Fresh interruption budget on every wake: the previous budget typically
    // burnt out during the ~30 s background grace period (rapid-fire socket
    // errors while iOS was suspending us), which must not poison the resume.
    _interruptRetries = 0;
    final backend = _backend;
    for (final node in state.nodes.where(
      (n) => n.status == GenStatus.generating && n.jobId != null,
    )) {
      if (_activeSubs.containsKey(node.id)) continue;
      // 3D mesh jobs resume through the ComfyUI mesh path regardless of the
      // currently selected model — followMesh is history-independent (it can
      // finish from the durable output files even after a server restart).
      // Repose is a ComfyUI-only round too: the user may have switched the
      // model chip to a NIM backend meanwhile, so don't resolve the backend
      // from the current selection.
      final run = node.isVideo
          ? () => _video.follow(node.jobId!)
          : node.is3D
              ? () => _comfyui.followMesh(node.jobId!)
              : node.isRepose
                  ? () => _comfyui.follow(node.jobId!)
                  : () => backend.follow(node.jobId!);
      unawaited(_runAsync(node.id, run));
    }
  }

  /// Push a model's ComfyUI preset + LoRA + pose down to the service. LoRAs
  /// that don't belong to the model's family are dropped (returned as null).
  /// Family membership is judged by name so it also works before the server
  /// LoRA list has loaded (session restore). Poses are dropped for models
  /// without OpenPose ControlNet support (NIM backends, flux-manga, SD 1.5).
  /// [strength] defaults to the current state, but session restore must pass
  /// the incoming session's value explicitly — at that point `state` still
  /// holds the *previous* session and would push a stale strength.
  (String? lora, String? poseId) _applyModelToServices(
    String modelId,
    String? lora,
    String? poseId, {
    double? strength,
    double? editDenoise,
  }) {
    final spec = imageModelById(modelId);
    final keepLora =
        lora != null && lorasForFamily([lora], spec.loraFamily).isNotEmpty;
    final appliedLora = keepLora ? lora : null;
    final pose = spec.supportsPose ? poseById(poseId) : null;
    if (spec.kind == ImageBackendKind.comfyUi) {
      _comfyui.setPreset(spec.preset!);
    }
    _comfyui.setLora(appliedLora);
    _comfyui.setLoraStrength(strength ?? state.loraStrength);
    _comfyui.setPose(pose?.asset);
    // img2img carries the source's own structure over via depth ControlNet for
    // pose-capable (SDXL) models; a template pose picked above overrides it.
    _comfyui.setAutoPose(spec.supportsPose);
    // Session restore calls this *before* the new state exists, so the
    // caller passes the session's value; null falls back to the live state.
    _comfyui.setEditDenoise(editDenoise ?? state.editDenoise);
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

  /// Pick the art style appended to every prompt in this session, or null.
  void setStyle(String? styleId) {
    final style = styleById(styleId);
    state = state.copyWith(
      selectedStyleId: style?.id,
      clearStyle: style == null,
    );
  }

  /// How hard an img2img round repaints. Null returns the model preset's
  /// value; [kStyleEditDenoise] is what actually lets an art style through
  /// (the preset's ~0.72 keeps the source's palette and lighting).
  void setEditDenoise(double? denoise) {
    _comfyui.setEditDenoise(denoise);
    state = state.copyWith(
      editDenoise: denoise,
      clearEditDenoise: denoise == null,
    );
  }

  void selectImage(String imageId) =>
      state = state.copyWith(selectedImageId: imageId, clearRepose: true);

  /// Move the grid to [nodeId] and bring the chips in line with how that node
  /// was actually generated, so stepping around the tree restores the setup
  /// you were working in — a refine or retry from here then continues with
  /// the same model/LoRA/pose instead of whatever was picked last.
  void navigateTo(String nodeId) {
    state = state.copyWith(
      currentNodeId: nodeId,
      clearSelected: true,
      clearRepose: true,
    );
    final node = _nodeById(nodeId);
    if (node != null) _adoptNodeSettings(node);
  }

  void _adoptNodeSettings(GenNode node) {
    final s = adoptableSettings(
      node,
      availableModels: state.availableModels,
      installedLoras: state.availableLoras,
    );
    if (s == null) return;
    if (s.modelId != state.modelId) setModel(s.modelId);
    if (s.lora != state.selectedLora) setLora(s.lora);
    if (s.lora != null && s.loraStrength != state.loraStrength) {
      setLoraStrength(s.loraStrength);
    }
    if (s.poseId != state.selectedPoseId) setPose(s.poseId);
  }

  /// Enter repose mode with [imageId] as the pose reference: the input bar
  /// then takes the prompt for [repose]. Repose is SDXL-only (depth
  /// ControlNet); if the active model can't, switch to the SDXL model last
  /// used in this session (else the first available) — like the inpaint flow
  /// picks its model for the user — and say so.
  void startRepose(String imageId) {
    if (_imageById(imageId) == null) return;
    String? info;
    if (!state.model.supportsPose) {
      final candidates =
          state.availableModels.where((m) => m.supportsPose).toList();
      if (candidates.isEmpty) {
        state = state.copyWith(
          error: '„Zachovej pózu“ vyžaduje SDXL model — na serveru žádný není.',
        );
        return;
      }
      final lastUsed = state.nodes.reversed
          .map((n) => n.modelId)
          .firstWhere(
            (id) => candidates.any((m) => m.id == id),
            orElse: () => candidates.first.id,
          )!;
      setModel(lastUsed);
      info = 'Přepnuto na ${imageModelById(lastUsed).label} — '
          '„zachovej pózu“ funguje jen na SDXL modelech.';
    }
    state = state.copyWith(
      reposeSourceImageId: imageId,
      clearSelected: true,
      clearError: true,
      info: info,
    );
  }

  void cancelRepose() => state = state.copyWith(clearRepose: true);

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
      availableCheckpoints: state.availableCheckpoints,
      availableScenes: state.availableScenes,
      selectedLora: state.selectedLora,
      loraStrength: state.loraStrength,
      selectedPoseId: state.selectedPoseId,
      selectedStyleId: state.selectedStyleId,
      editDenoise: state.editDenoise,
    );
  }

  void selectSession(String id) {
    final session = state.sessions.firstWhere((s) => s.id == id);
    final (lora, poseId) = _applyModelToServices(
      session.modelId,
      session.selectedLora,
      session.selectedPoseId,
      strength: session.loraStrength,
      editDenoise: session.editDenoise,
    );
    state = ImageStudioState(
      sessions: state.sessions,
      activeSessionId: id,
      nodes: session.nodes.toList(),
      currentNodeId: session.currentNodeId,
      selectedLora: lora,
      loraStrength: session.loraStrength ?? kDefaultLoraStrength,
      selectedPoseId: poseId,
      selectedStyleId: session.selectedStyleId,
      editDenoise: session.editDenoise,
      modelId: session.modelId,
      availableLoras: state.availableLoras,
      availableCheckpoints: state.availableCheckpoints,
      availableScenes: state.availableScenes,
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
          strength: next.loraStrength,
          editDenoise: next.editDenoise,
        );
        state = ImageStudioState(
          sessions: updated,
          activeSessionId: next.id,
          nodes: next.nodes.toList(),
          currentNodeId: next.currentNodeId,
          selectedLora: lora,
          loraStrength: next.loraStrength ?? kDefaultLoraStrength,
          selectedPoseId: poseId,
          selectedStyleId: next.selectedStyleId,
          editDenoise: next.editDenoise,
          modelId: next.modelId,
          availableLoras: state.availableLoras,
          availableCheckpoints: state.availableCheckpoints,
          availableScenes: state.availableScenes,
        );
      } else {
        state = ImageStudioState(
          sessions: const [],
          modelId: state.modelId,
          availableLoras: state.availableLoras,
          availableCheckpoints: state.availableCheckpoints,
          availableScenes: state.availableScenes,
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
          strength: latest.loraStrength,
          editDenoise: latest.editDenoise,
        );
        state = ImageStudioState(
          sessions: sessions,
          activeSessionId: latest.id,
          nodes: latest.nodes.toList(),
          currentNodeId: latest.currentNodeId,
          selectedLora: lora,
          loraStrength: latest.loraStrength ?? kDefaultLoraStrength,
          selectedPoseId: poseId,
          selectedStyleId: latest.selectedStyleId,
          editDenoise: latest.editDenoise,
          modelId: latest.modelId,
          availableLoras: state.availableLoras,
          availableCheckpoints: state.availableCheckpoints,
          availableScenes: state.availableScenes,
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
      loraStrength: state.loraStrength,
      selectedPoseId: state.selectedPoseId,
      selectedStyleId: state.selectedStyleId,
      editDenoise: state.editDenoise,
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

  void setLoraStrength(double strength) {
    final v = strength.clamp(kMinLoraStrength, kMaxLoraStrength).toDouble();
    _comfyui.setLoraStrength(v);
    state = state.copyWith(loraStrength: v);
  }

  void setPose(String? poseId) {
    final pose = poseById(poseId);
    _comfyui.setPose(pose?.asset);
    state = state.copyWith(
      selectedPoseId: pose?.id,
      clearPose: pose == null,
    );
  }

  /// What the ComfyUI server currently has installed, read once at startup:
  /// LoRAs feed the LoRA chip, checkpoints prune the model picker. Both fetches
  /// swallow their errors and yield an empty list, which every consumer reads
  /// as "unknown" — an offline start keeps the full registry rather than an
  /// empty picker.
  ///
  /// Sequential, and each result is published on its own: LoRAs must not share
  /// a fate with the checkpoint list. Under one `Future.wait` a hiccup on the
  /// second request (two parallel CF Access handshakes are enough) delayed or
  /// took down the LoRA chip that used to load on its own.
  /// Each result is awaited into a local before touching [state]: in
  /// `state = state.copyWith(x: await f())` Dart evaluates the receiver first,
  /// so the write would land on the pre-await snapshot and silently undo
  /// whatever _load() restored while the request was in flight.
  Future<void> _loadServerCatalog() async {
    final loras = await _comfyui.fetchLoras();
    state = state.copyWith(availableLoras: loras);
    debugPrint('ComfyUI catalog: ${loras.length} LoRAs');

    final checkpoints = await _comfyui.fetchCheckpoints();
    state = state.copyWith(availableCheckpoints: checkpoints);
    debugPrint('ComfyUI catalog: ${checkpoints.length} checkpoints');

    // Separate server; a failure here must not take the image catalog down
    // with it — the animate action just stays hidden.
    try {
      final scenes = await _video.fetchScenes();
      if (!mounted) return;
      state = state.copyWith(availableScenes: scenes);
      debugPrint('Video catalog: ${scenes.length} scenes');
    } catch (e) {
      debugPrint('Video catalog unavailable: $e');
    }
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
    String userNegative = '',
    String? maskFileName,
    String? refFileName,
    bool refIsFace = false,
    bool isRepose = false,
    LatentSize? latentSize,
  }) {
    final spec = state.model;
    final preset = spec.preset;
    final patched = preset?.ckptName != null;
    final isInpaint = maskFileName != null;
    // Pose/depth ControlNet never applies to inpaint rounds (see
    // ComfyUIService._inpaint) — don't record a pose that won't run. Repose
    // ignores a template pose too: the reference is the pose.
    final poseId = (isInpaint || isRepose) ? null : state.selectedPoseId;
    // Inpaint describes only the masked area — a whole-image art style would
    // fight it, so the style block is not applied (nor recorded) there.
    final styleId = isInpaint ? null : state.selectedStyleId;
    final appliedLora = isInpaint && !patched ? null : state.selectedLora;
    final poseActive = poseId != null && patched;
    // Effective negative = preset negative + user ALL-CAPS tags. Recorded only
    // for generic-template models — elsewhere no negative is actually applied.
    final negative = patched
        ? [preset!.negativePrompt, userNegative]
            .where((s) => s.isNotEmpty)
            .join(', ')
        : '';
    return GenNode.create(
      id: id,
      parentId: parentId,
      sourceImageId: sourceImageId,
      prompt: prompt,
      maskFileName: maskFileName,
      refFileName: refFileName,
      refIsFace: refIsFace,
      isRepose: isRepose,
      modelId: spec.id,
      // flux-fill: LoRA is banned for the dedicated Fill workflow (M5
      // experiment pending) — mirror what the service actually applies.
      loraName: appliedLora,
      // Strength only where a LoRA actually runs — otherwise the snapshot
      // would claim a setting that had no effect on this round.
      loraStrength: appliedLora != null ? state.loraStrength : null,
      styleId: styleId,
      poseId: poseId,
      seed: seed,
      negativePrompt: negative.isNotEmpty ? negative : null,
      positivePrefix:
          preset != null && preset.positivePrefix.isNotEmpty
              ? preset.positivePrefix
              : null,
      // img2img latents come from VAEEncode of the source image, so recorded
      // dimensions stay null (source-derived) even when a pose is active.
      // Repose records the bucket snapped to the reference's aspect.
      width: patched && !isImg2img
          ? (isRepose
              ? latentSize?.w
              : (poseActive ? kPoseWidth : preset!.width))
          : null,
      height: patched && !isImg2img
          ? (isRepose
              ? latentSize?.h
              : (poseActive ? kPoseHeight : preset!.height))
          : null,
      steps: patched ? preset!.steps : null,
      cfg: patched ? preset!.cfg : null,
      // Inpaint always samples at full denoise — the mask limits the change.
      denoise: patched
          ? (isImg2img && !isInpaint
              ? (poseActive
                  ? kPoseEditDenoise
                  : (state.editDenoise ?? preset!.img2imgDenoise))
              : 1.0)
          : null,
      samplerName: patched ? preset!.samplerName : null,
      scheduler: patched ? preset!.scheduler : null,
    );
  }

  /// Round 1: [kVariantCount] text→image candidates from [prompt]. ALL-CAPS
  /// tags/words are routed to the negative prompt (see [splitPromptNegatives]);
  /// the node keeps the original text so retry/UI stay faithful to the input.
  Future<void> generate(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _interruptRetries = 0;
    final parts = splitPromptNegatives(text);
    final seed = _newSeed();
    final node = _createNodeWithMeta(
      prompt: text,
      seed: seed,
      isImg2img: false,
      userNegative: parts.negative,
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _backend.generate(
        prompt: applyStyle(parts.positive, state.selectedStyleId),
        n: _backend.variantCount,
        seed: seed,
        negativePrompt: parts.negative.isEmpty ? null : parts.negative,
      ),
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
  ///
  /// ALL-CAPS negative tags are stripped from every segment ([text] and each
  /// ancestor prompt) via [splitPromptNegatives], so the chained positive never
  /// carries negatives; the caller passes the current text's negatives to the
  /// backend separately.
  String _chainedPrompt(String? parentId, String text) {
    final byId = {for (final n in state.nodes) n.id: n};
    final parts = <String>[];
    final seen = <String>{};
    final own = splitPromptNegatives(text).positive.trim();
    if (own.isNotEmpty && seen.add(own)) parts.add(own);
    GenNode? node = parentId == null ? null : byId[parentId];
    while (node != null) {
      final p = splitPromptNegatives(node.prompt).positive.trim();
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
    final parts = splitPromptNegatives(text);
    final seed = _newSeed();
    final chained = _chainedPrompt(state.currentNodeId, text);
    final node = _createNodeWithMeta(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: text,
      seed: seed,
      isImg2img: true,
      userNegative: parts.negative,
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
        prompt: applyStyle(chained, state.selectedStyleId),
        n: _backend.variantCount,
        seed: seed,
        negativePrompt: parts.negative.isEmpty ? null : parts.negative,
      ),
    );
  }

  /// Masked edit of the selected image: repaint only where [maskPng] is white.
  ///
  /// Unlike [refine], the prompt is NOT chained with ancestors — it describes
  /// only the masked region, and inherited whole-image tokens would drag the
  /// repaint elsewhere. With [refPng] the appearance of the reference guides
  /// the repaint (IPAdapter, SDXL models only). Mask and reference are
  /// persisted next to the session images so retry can re-send them and the
  /// UI can badge the node.
  Future<void> inpaint(String prompt, Uint8List maskPng,
      {Uint8List? refPng, bool refIsFace = false}) async {
    final text = prompt.trim();
    final base = _imageById(state.selectedImageId);
    if (text.isEmpty || base == null) return;
    if (!state.model.inpaint) {
      state = state.copyWith(
        error: 'Model ${state.model.label} nepodporuje inpaint.',
      );
      return;
    }
    if (refPng != null && !state.model.inpaintRef) {
      state = state.copyWith(
        error:
            'Model ${state.model.label} nepodporuje referenční inpaint.',
      );
      return;
    }
    if (refPng != null && refIsFace && !state.model.inpaintFace) {
      state = state.copyWith(
        error: 'Model ${state.model.label} nepodporuje face inpaint.',
      );
      return;
    }
    _interruptRetries = 0;
    final parts = splitPromptNegatives(text);
    final seed = _newSeed();
    final dir = await _dirFuture;
    final maskImage = await GenImage.save(maskPng, dir);
    final refImage = refPng == null ? null : await GenImage.save(refPng, dir);
    final node = _createNodeWithMeta(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: text,
      seed: seed,
      isImg2img: true,
      userNegative: parts.negative,
      maskFileName: maskImage.fileName,
      refFileName: refImage?.fileName,
      refIsFace: refPng != null && refIsFace,
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
        prompt: parts.positive,
        n: _backend.variantCount,
        seed: seed,
        negativePrompt: parts.negative.isEmpty ? null : parts.negative,
        mask: maskPng,
        refImage: refPng,
        refIsFace: refPng != null && refIsFace,
      ),
    );
  }

  /// Turn the selected image into a printable 3D model (Trellis2 on the
  /// server): STL for slicing + GLB for the in-app 360° viewer. Slow round
  /// (~4–7 min server-side) — the node survives app suspension via
  /// [ComfyUIService.followMesh], which can complete from the durable output
  /// files even if the server restarts after the job finished.
  Future<void> make3D() async {
    final base = _imageById(state.selectedImageId);
    if (base == null) return;
    _interruptRetries = 0;
    final seed = _newSeed();
    final node = GenNode.create(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: '3D model',
      is3D: true,
      seed: seed,
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _comfyui.generateMesh(image: base.bytes, seed: seed),
    );
  }

  /// Animation round („Rozhýbat"): the selected image becomes a short clip
  /// rendered server-side from the [sceneId] preset (see [VideoService]).
  /// Mirrors [make3D]: a child node flagged [GenNode.isVideo], resumable by
  /// job id after an app suspension.
  Future<void> animate(String sceneId) async {
    final base = _imageById(state.selectedImageId);
    if (base == null) return;
    final scene = state.availableScenes.where((s) => s.id == sceneId).firstOrNull;
    _interruptRetries = 0;
    final seed = _newSeed();
    final node = GenNode.create(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: scene?.label ?? sceneId,
      isVideo: true,
      sceneId: sceneId,
      seed: seed,
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _video.animate(image: base.bytes, sceneId: sceneId, seed: seed),
    );
  }

  /// Repose round: a new character/style from [prompt] in the pose of the
  /// reference picked via [startRepose] (depth ControlNet over a txt2img
  /// render, denoise 1.0 — see [ComfyUIService.repose]).
  ///
  /// Like [inpaint], the prompt is NOT chained with ancestors: inherited
  /// tokens would drag the *old* character back in, and the whole point is
  /// to replace it. Preset prefix/negative and ALL-CAPS negatives apply as
  /// usual. SDXL models only.
  Future<void> repose(String prompt) async {
    final text = prompt.trim();
    final base = _imageById(state.reposeSourceImageId);
    if (text.isEmpty || base == null) return;
    if (!state.model.supportsPose) {
      state = state.copyWith(
        error: '„Zachovej pózu“ funguje jen na SDXL modelech — vyber jiný.',
      );
      return;
    }
    _interruptRetries = 0;
    final parts = splitPromptNegatives(text);
    final seed = _newSeed();
    final latent = _reposeLatent(base);
    final node = _createNodeWithMeta(
      parentId: state.currentNodeId,
      sourceImageId: base.id,
      prompt: text,
      seed: seed,
      isImg2img: false,
      isRepose: true,
      latentSize: latent,
      userNegative: parts.negative,
    );
    state = state.copyWith(
      nodes: [...state.nodes, node],
      currentNodeId: node.id,
      clearSelected: true,
      clearRepose: true,
      clearError: true,
    );
    await _runAsync(
      node.id,
      () => _comfyui.repose(
        image: base.bytes,
        prompt: applyStyle(parts.positive, state.selectedStyleId),
        n: _comfyui.variantCount,
        seed: seed,
        negativePrompt: parts.negative.isEmpty ? null : parts.negative,
        latentSize: latent,
      ),
    );
  }

  /// Latent bucket for a repose of [base] under the active (SDXL) preset —
  /// computed once per round so node metadata and the request agree.
  LatentSize _reposeLatent(GenImage base) {
    final p = state.model.preset!;
    return reposeLatentFor(base.bytes, fallback: (w: p.width, h: p.height));
  }

  /// Re-run a failed (or finished) node with its original prompt.
  ///
  /// The retry runs against the *current* model/LoRA/pose (they may have
  /// changed since the node was created), so the node's metadata snapshot is
  /// rebuilt too — keeping it truthful — while id/parent links and any old
  /// images are preserved. Inpaint nodes re-send their persisted mask; if the
  /// current model can't inpaint the retry fails instead of silently running
  /// an unmasked edit.
  Future<void> retry(String nodeId) async {
    final node = _nodeById(nodeId);
    if (node == null) return;
    // A stuck 3D node may legitimately sit in `generating` (its job outlived
    // an app suspension); re-attaching to it is safe and is the whole point
    // of the manual retry there. Everything else stays guarded.
    final durableJob = node.is3D || node.isVideo;
    if (node.status == GenStatus.generating && !durableJob) return;
    if (durableJob && _activeSubs.containsKey(nodeId)) {
      // Already re-attached and working — don't stack a second stream.
      return;
    }
    if (node.maskFileName != null &&
        (!state.model.inpaint ||
            (node.refFileName != null && !state.model.inpaintRef) ||
            (node.refIsFace && !state.model.inpaintFace))) {
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.error,
          error: node.refFileName != null
              ? 'Model ${state.model.label} nepodporuje referenční inpaint.'
              : 'Model ${state.model.label} nepodporuje inpaint.',
        ),
      );
      return;
    }
    _interruptRetries = 0;
    // Video retry: same shape as 3D — with a job id the mp4 is (or will be)
    // on the server, so just re-attach; without one re-submit from the
    // source image with the original scene and seed.
    if (node.isVideo) {
      final jobId = node.jobId;
      if (jobId != null) {
        _patch(
          nodeId,
          (n) => n.copyWith(
            status: GenStatus.generating,
            clearError: true,
            clearProgress: true,
            progressLabel: 'Obnovuji video…',
          ),
        );
        await _runAsync(nodeId, () => _video.follow(jobId));
        return;
      }
      final base = _imageById(node.sourceImageId);
      if (base == null || node.sceneId == null) {
        _patch(
          nodeId,
          (n) => n.copyWith(status: GenStatus.error, error: 'Source image gone'),
        );
        return;
      }
      final seed = node.seed ?? _newSeed();
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.generating,
          clearError: true,
          clearProgress: true,
        ),
      );
      await _runAsync(
        nodeId,
        () => _video.animate(image: base.bytes, sceneId: node.sceneId!, seed: seed),
      );
      return;
    }
    // 3D mesh retry. With a job id the artifacts are (or will be) on the
    // server — followMesh downloads them directly, which takes seconds
    // instead of regenerating the mesh for another 4 minutes.
    if (node.is3D && node.jobId != null) {
      final jobId = node.jobId!;
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.generating,
          clearError: true,
          clearProgress: true,
          progressLabel: 'Stahuji výsledek…',
        ),
      );
      await _runAsync(nodeId, () => _comfyui.followMesh(jobId));
      return;
    }
    // No job id (or a genuinely absent output): regenerate from the source.
    if (node.is3D) {
      final base = _imageById(node.sourceImageId);
      if (base == null) {
        _patch(
          nodeId,
          (n) =>
              n.copyWith(status: GenStatus.error, error: 'Source image gone'),
        );
        return;
      }
      final seed3d = _newSeed();
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.generating,
          clearError: true,
          clearProgress: true,
          clearJobId: true,
        ),
      );
      await _runAsync(
        nodeId,
        () => _comfyui.generateMesh(image: base.bytes, seed: seed3d),
      );
      return;
    }
    // Repose retry: must not fall into the generic child path below, which
    // would re-run it as a chained img2img (auto-depth 0.7, img2imgDenoise).
    if (node.isRepose) {
      if (!state.model.supportsPose) {
        _patch(
          nodeId,
          (n) => n.copyWith(
            status: GenStatus.error,
            error: '„Zachovej pózu“ funguje jen na SDXL modelech — vyber jiný.',
          ),
        );
        return;
      }
      final base = _imageById(node.sourceImageId);
      if (base == null) {
        _patch(
          nodeId,
          (n) =>
              n.copyWith(status: GenStatus.error, error: 'Source image gone'),
        );
        return;
      }
      final parts = splitPromptNegatives(node.prompt);
      final seed = _newSeed();
      final latent = _reposeLatent(base);
      final refreshed = _createNodeWithMeta(
        id: node.id,
        parentId: node.parentId,
        sourceImageId: node.sourceImageId,
        prompt: node.prompt,
        seed: seed,
        isImg2img: false,
        isRepose: true,
        latentSize: latent,
        userNegative: parts.negative,
      ).copyWith(images: node.images);
      _patch(nodeId, (_) => refreshed);
      await _runAsync(
        nodeId,
        () => _comfyui.repose(
          image: base.bytes,
          prompt: applyStyle(parts.positive, node.styleId),
          n: _comfyui.variantCount,
          seed: seed,
          negativePrompt: parts.negative.isEmpty ? null : parts.negative,
          latentSize: latent,
        ),
      );
      return;
    }
    final parts = splitPromptNegatives(node.prompt);
    final seed = _newSeed();
    final refreshed = _createNodeWithMeta(
      id: node.id,
      parentId: node.parentId,
      sourceImageId: node.sourceImageId,
      prompt: node.prompt,
      seed: seed,
      isImg2img: !node.isRoot,
      userNegative: parts.negative,
      maskFileName: node.maskFileName,
      refFileName: node.refFileName,
      refIsFace: node.refIsFace,
    ).copyWith(images: node.images);
    _patch(nodeId, (_) => refreshed);
    if (node.isRoot) {
      await _runAsync(
        nodeId,
        () => _backend.generate(
          // The style follows the *current* selection, like the model and
          // LoRA above — the rebuilt snapshot records what actually ran.
          prompt: applyStyle(parts.positive, state.selectedStyleId),
          n: _backend.variantCount,
          seed: seed,
          negativePrompt: parts.negative.isEmpty ? null : parts.negative,
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
      // Inpaint retry: re-send the persisted mask (and reference, when the
      // round had one); the prompt stays unchained (it describes only the
      // masked region — see [inpaint]).
      Uint8List? mask;
      Uint8List? refImage;
      if (node.maskFileName != null) {
        try {
          mask = await File(
            '${GenImage.baseDir}/${node.maskFileName}',
          ).readAsBytes();
          if (node.refFileName != null) {
            refImage = await File(
              '${GenImage.baseDir}/${node.refFileName}',
            ).readAsBytes();
          }
        } catch (_) {
          _patch(
            nodeId,
            (n) => n.copyWith(status: GenStatus.error, error: 'Maska ztracena'),
          );
          return;
        }
      }
      // Recomposed against the *current* model, consistent with the metadata
      // snapshot rebuild above.
      final chained = mask != null
          ? parts.positive
          : _chainedPrompt(node.parentId, node.prompt);
      await _runAsync(
        nodeId,
        () => _backend.edit(
          image: base.bytes,
          prompt: mask != null
              ? chained
              : applyStyle(chained, state.selectedStyleId),
          n: _backend.variantCount,
          seed: seed,
          negativePrompt: parts.negative.isEmpty ? null : parts.negative,
          mask: mask,
          refImage: refImage,
          refIsFace: node.refIsFace,
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
      // Keep the job id on 3D nodes: the mesh artifacts are durable on the
      // server, so retry can still just download them (see [retry]).
      final n0 = _nodeById(nodeId);
      final keepJobId = (n0?.is3D ?? false) || (n0?.isVideo ?? false);
      _patch(
        nodeId,
        (n) => n.copyWith(
          status: GenStatus.error,
          error: msg,
          clearProgress: true,
          clearJobId: !keepJobId,
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
      } else if (_nodeById(nodeId)?.is3D == true ||
          _nodeById(nodeId)?.isVideo == true) {
        // A mesh/video job is durable server-side and recoverable from its output
        // files at any time — never hard-fail it on a burnt retry budget.
        // Keep the node generating with its jobId; the next app foreground
        // (didChangeAppLifecycleState) re-attaches with a fresh budget.
        _patch(
          nodeId,
          (n) => n.copyWith(progressLabel: 'Obnovím po návratu do aplikace…'),
        );
        unawaited(_save());
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
          case GenRunning(:final step, :final total, :final fraction):
            // Real progress ⇒ the connection is healthy again.
            _interruptRetries = 0;
            final isVideo = _nodeById(nodeId)?.isVideo ?? false;
            _patch(
              nodeId,
              (n) => n.copyWith(
                progress: fraction,
                clearProgress: fraction == null,
                // Video: step = beats finished of total; all in ⇒ the server
                // is stitching + interpolating (ffmpeg + RIFE, ~1–2 min).
                progressLabel: isVideo
                    ? (step < total
                        ? 'Beat ${step + 1}/$total · ~${(total - step) * 2.5} min'
                        : 'Slepuji a vyhlazuji…')
                    : fraction == null
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
          case GenMeshComplete(:final stl, :final glb):
            completedByEvent = true;
            unawaited(() async {
              final dir = await _dirFuture;
              // Node id is already a UUID — reuse it for stable file names.
              final glbName = '$nodeId.glb';
              final stlName = '$nodeId.stl';
              await File('${dir.path}/$glbName').writeAsBytes(glb, flush: true);
              await File('${dir.path}/$stlName').writeAsBytes(stl, flush: true);
              if (!mounted) return;
              _patch(
                nodeId,
                (n) => n.copyWith(
                  status: GenStatus.ready,
                  glbFileName: glbName,
                  stlFileName: stlName,
                  clearError: true,
                  clearProgress: true,
                  clearJobId: true,
                ),
              );
              unawaited(_save());
              finish();
            }());
          case GenVideoComplete(:final mp4):
            completedByEvent = true;
            unawaited(() async {
              final dir = await _dirFuture;
              final name = '$nodeId.mp4';
              await File('${dir.path}/$name').writeAsBytes(mp4, flush: true);
              if (!mounted) return;
              _patch(
                nodeId,
                (n) => n.copyWith(
                  status: GenStatus.ready,
                  videoFileName: name,
                  clearError: true,
                  clearProgress: true,
                  clearJobId: true,
                ),
              );
              unawaited(_save());
              finish();
            }());
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

  GenImage? _imageById(String? id) => state.imageById(id);

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
    _video.dispose();
    _fluxNim.dispose();
    _fluxKontextNim.dispose();
    _finetuneExport.dispose();
    super.dispose();
  }
}
