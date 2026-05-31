import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gen_node.dart';
import '../services/media_service.dart';

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

  /// Last error surfaced to the user (for a one-shot snackbar).
  final String? error;

  const ImageStudioState({
    this.nodes = const [],
    this.currentNodeId,
    this.selectedImageId,
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
    String? error,
    bool clearError = false,
  }) =>
      ImageStudioState(
        nodes: nodes ?? this.nodes,
        currentNodeId: currentNodeId ?? this.currentNodeId,
        selectedImageId:
            clearSelected ? null : (selectedImageId ?? this.selectedImageId),
        error: clearError ? null : (error ?? this.error),
      );
}

class ImageStudioNotifier extends StateNotifier<ImageStudioState> {
  ImageStudioNotifier() : super(const ImageStudioState());

  final MediaService _media = MediaService();

  void selectImage(String imageId) =>
      state = state.copyWith(selectedImageId: imageId);

  void navigateTo(String nodeId) =>
      state = state.copyWith(currentNodeId: nodeId, clearSelected: true);

  void startOver() => state = const ImageStudioState();

  void clearError() => state = state.copyWith(clearError: true);

  /// Round 1: four FLUX text→image candidates from [prompt].
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
      () => _media.submitGeneration(prompt: text, n: kVariantCount),
    );
  }

  /// Round 2+: four Qwen-Image-Edit variants of the selected image.
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
      () => _media.submitEdit(
        imageBase64: base.b64,
        prompt: text,
        n: kVariantCount,
      ),
    );
  }

  /// Re-run a failed (or finished) node with its original prompt.
  Future<void> retry(String nodeId) async {
    final node = _nodeById(nodeId);
    if (node == null || node.status == GenStatus.generating) return;
    _patch(nodeId,
        (n) => n.copyWith(status: GenStatus.generating, clearError: true));
    if (node.isRoot) {
      await _runAsync(
        nodeId,
        () => _media.submitGeneration(prompt: node.prompt, n: kVariantCount),
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
        () => _media.submitEdit(
          imageBase64: base.b64,
          prompt: node.prompt,
          n: kVariantCount,
        ),
      );
    }
  }

  /// Submit a job then poll until terminal state, updating [nodeId] in place.
  Future<void> _runAsync(
    String nodeId,
    Future<String> Function() submitJob,
  ) async {
    String jobId;
    try {
      jobId = await submitJob();
    } catch (e) {
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      _patch(nodeId, (n) => n.copyWith(status: GenStatus.error, error: msg));
      state = state.copyWith(error: msg);
      return;
    }

    await for (final status in _media.pollJob(jobId)) {
      switch (status) {
        case JobQueued() || JobRunning():
          break; // node stays generating, _PlaceholderTile spinner stays visible
        case JobDone(:final resultUrl, :final count):
          final genImages = <GenImage>[];
          for (var i = 0; i < count; i++) {
            final bytes = await _media.downloadResult(resultUrl, index: i);
            genImages.add(GenImage.fromB64(base64Encode(bytes)));
          }
          _patch(
            nodeId,
            (n) => n.copyWith(
              status: GenStatus.ready,
              images: genImages,
              clearError: true,
            ),
          );
          return;
        case JobFailed(:final message):
          _patch(nodeId,
              (n) => n.copyWith(status: GenStatus.error, error: message));
          state = state.copyWith(error: message);
          return;
        case JobExpired():
          const msg = 'Výsledek vypršel – zkus znovu';
          _patch(nodeId,
              (n) => n.copyWith(status: GenStatus.error, error: msg));
          state = state.copyWith(error: msg);
          return;
      }
    }
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
    _media.dispose();
    super.dispose();
  }
}
