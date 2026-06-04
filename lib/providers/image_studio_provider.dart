import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gen_node.dart';
import '../services/comfyui_service.dart';
import '../services/image_backend.dart';

final imageStudioProvider =
    StateNotifierProvider<ImageStudioNotifier, ImageStudioState>(
  (ref) => ImageStudioNotifier(),
);

/// How many candidates each round produces.
const kVariantCount = 4;

class ImageStudioState {
  /// Every round ever produced this session (the refinement tree).
  final List<GenNode> nodes;

  /// Node currently shown in the grid.
  final String? currentNodeId;

  /// Image selected within the current node — the base for the next refine.
  final String? selectedImageId;

  /// Active image backend id (kBackendDiffusers | kBackendComfyUI).
  final String backendId;

  /// LoRAs available on the ComfyUI server (empty when Diffusers is active).
  final List<String> availableLoras;

  /// Currently selected LoRA name, or null for no LoRA.
  final String? selectedLora;

  /// Last error surfaced to the user (for a one-shot snackbar).
  final String? error;

  const ImageStudioState({
    this.nodes = const [],
    this.currentNodeId,
    this.selectedImageId,
    this.backendId = kBackendDiffusers,
    this.availableLoras = const [],
    this.selectedLora,
    this.error,
  });

  GenNode? get current {
    final id = currentNodeId;
    if (id == null) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool get isBusy => current?.status == GenStatus.generating;

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
    String? error,
    bool clearError = false,
  }) =>
      ImageStudioState(
        nodes: nodes ?? this.nodes,
        currentNodeId: currentNodeId ?? this.currentNodeId,
        selectedImageId:
            clearSelected ? null : (selectedImageId ?? this.selectedImageId),
        backendId: backendId ?? this.backendId,
        availableLoras: availableLoras ?? this.availableLoras,
        selectedLora: clearLora ? null : (selectedLora ?? this.selectedLora),
        error: clearError ? null : (error ?? this.error),
      );
}

class ImageStudioNotifier extends StateNotifier<ImageStudioState> {
  ImageStudioNotifier() : super(const ImageStudioState()) {
    // Pre-load LoRAs so they're ready before the user switches to ComfyUI.
    _loadLoras();
  }

  final DiffusersBackend _diffusers = DiffusersBackend();
  final ComfyUIService _comfyui = ComfyUIService();

  StreamSubscription<GenEvent>? _activeSub;
  String? _activeNodeId;
  Completer<void>? _activeCompleter;

  ImageBackend get _backend =>
      state.backendId == kBackendComfyUI ? _comfyui : _diffusers;

  /// The backends the user can switch between, for the UI picker.
  List<ImageBackend> get backends => [_diffusers, _comfyui];

  void selectImage(String imageId) =>
      state = state.copyWith(selectedImageId: imageId);

  void navigateTo(String nodeId) =>
      state = state.copyWith(currentNodeId: nodeId, clearSelected: true);

  void startOver() {
    _activeSub?.cancel();
    _activeSub = null;
    _activeNodeId = null;
    state = ImageStudioState(backendId: state.backendId);
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// Switch image backend (ignored while a job is in flight).
  void setBackend(String backendId) {
    if (state.isBusy || backendId == state.backendId) return;
    state = state.copyWith(backendId: backendId, clearSelected: true);
    if (backendId == kBackendComfyUI) _loadLoras();
  }

  void setLora(String? loraName) {
    _comfyui.setLora(loraName);
    state = state.copyWith(
      selectedLora: loraName,
      clearLora: loraName == null,
    );
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
      () => _backend.generate(prompt: text, n: kVariantCount),
    );
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
        image: base64Decode(base.b64),
        prompt: text,
        n: kVariantCount,
      ),
    );
  }

  /// Re-run a failed (or finished) node with its original prompt.
  Future<void> retry(String nodeId) async {
    final node = _nodeById(nodeId);
    if (node == null || node.status == GenStatus.generating) return;
    _patch(
      nodeId,
      (n) => n.copyWith(status: GenStatus.generating, clearError: true, clearProgress: true),
    );
    if (node.isRoot) {
      await _runAsync(
        nodeId,
        () => _backend.generate(prompt: node.prompt, n: kVariantCount),
      );
    } else {
      final base = _imageById(node.sourceImageId);
      if (base == null) {
        _patch(nodeId,
            (n) => n.copyWith(status: GenStatus.error, error: 'Source image gone'));
        return;
      }
      await _runAsync(
        nodeId,
        () => _backend.edit(
          image: base64Decode(base.b64),
          prompt: node.prompt,
          n: kVariantCount,
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
  Future<void> _runAsync(
    String nodeId,
    Stream<GenEvent> Function() run,
  ) async {
    await _activeSub?.cancel();
    _activeNodeId = nodeId;
    final completer = Completer<void>();
    _activeCompleter = completer;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    void fail(String msg) {
      _patch(
        nodeId,
        (n) => n.copyWith(
            status: GenStatus.error, error: msg, clearProgress: true),
      );
      state = state.copyWith(error: msg);
    }

    _activeSub = run().listen(
      (event) {
        switch (event) {
          case GenQueued(:final position):
            _patch(
              nodeId,
              (n) => n.copyWith(
                clearProgress: true,
                progressLabel:
                    position > 0 ? 'Ve frontě: $position' : 'Ve frontě…',
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
            final genImages = [
              for (final bytes in images) GenImage.fromB64(base64Encode(bytes)),
            ];
            _patch(
              nodeId,
              (n) => n.copyWith(
                status: GenStatus.ready,
                images: genImages,
                clearError: true,
                clearProgress: true,
              ),
            );
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
        finish();
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
    _activeSub?.cancel();
    _diffusers.dispose();
    _comfyui.dispose();
    super.dispose();
  }
}
