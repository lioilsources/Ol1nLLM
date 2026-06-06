import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Lifecycle of a single generation round.
enum GenStatus { generating, ready, error }

/// One produced image (base64 PNG) with a stable local id used for selection.
class GenImage {
  final String id;
  final String b64;

  const GenImage({required this.id, required this.b64});

  factory GenImage.fromB64(String b64) => GenImage(id: _uuid.v4(), b64: b64);
}

/// One round in the refinement tree.
///
/// A root node ([parentId] == null) is a FLUX text→image generation. A child
/// node is a Qwen-Image-Edit of [sourceImageId] (an image in the parent),
/// using [prompt] as the edit instruction. Each node holds up to four
/// candidate images.
class GenNode {
  final String id;
  final String? parentId;

  /// Id of the image in the parent node chosen as the edit base (null = root).
  final String? sourceImageId;

  /// text→image prompt for a root, or the edit instruction for a child.
  final String prompt;

  final GenStatus status;
  final List<GenImage> images;
  final String? error;

  /// Live generation progress in 0..1 while [status] == generating, or null
  /// when the backend can't report a fraction yet (indeterminate).
  final double? progress;

  /// Short human-readable progress label (queue position, step, download…).
  final String? progressLabel;

  const GenNode({
    required this.id,
    required this.parentId,
    required this.sourceImageId,
    required this.prompt,
    required this.status,
    this.images = const [],
    this.error,
    this.progress,
    this.progressLabel,
  });

  bool get isRoot => parentId == null;

  factory GenNode.create({
    String? parentId,
    String? sourceImageId,
    required String prompt,
  }) => GenNode(
    id: _uuid.v4(),
    parentId: parentId,
    sourceImageId: sourceImageId,
    prompt: prompt,
    status: GenStatus.generating,
  );

  GenNode copyWith({
    GenStatus? status,
    List<GenImage>? images,
    String? error,
    bool clearError = false,
    double? progress,
    String? progressLabel,
    bool clearProgress = false,
  }) => GenNode(
    id: id,
    parentId: parentId,
    sourceImageId: sourceImageId,
    prompt: prompt,
    status: status ?? this.status,
    images: images ?? this.images,
    error: clearError ? null : (error ?? this.error),
    // clearProgress only resets the numeric fraction (→ indeterminate);
    // the label follows its own argument so a queued/indeterminate state
    // can still carry text like "Ve frontě…".
    progress: clearProgress ? null : (progress ?? this.progress),
    progressLabel: progressLabel ?? this.progressLabel,
  );
}
