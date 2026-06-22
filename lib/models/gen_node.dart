import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Lifecycle of a single generation round.
enum GenStatus { generating, ready, error }

/// One produced image (base64 PNG) with a stable local id used for selection.
class GenImage {
  final String id;
  final String b64;
  Uint8List? _bytes;

  GenImage({required this.id, required this.b64});

  /// Decoded PNG bytes, decoded lazily once and cached. Reusing the same
  /// [Uint8List] instance across rebuilds lets `Image.memory` recognise the
  /// image as unchanged, so it isn't re-decoded (which caused tiles and tree
  /// thumbnails to flicker on every progress tick / selection).
  Uint8List get bytes => _bytes ??= base64Decode(b64);

  factory GenImage.fromB64(String b64) => GenImage(id: _uuid.v4(), b64: b64);

  Map<String, dynamic> toJson() => {'id': id, 'b64': b64};

  factory GenImage.fromJson(Map<String, dynamic> json) =>
      GenImage(id: json['id'] as String, b64: json['b64'] as String);
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

  Map<String, dynamic> toJson() => {
    'id': id,
    if (parentId != null) 'parentId': parentId,
    if (sourceImageId != null) 'sourceImageId': sourceImageId,
    'prompt': prompt,
    'status': status.name,
    'images': images.map((i) => i.toJson()).toList(),
    if (error != null) 'error': error,
  };

  factory GenNode.fromJson(Map<String, dynamic> json) {
    var status = GenStatus.values.byName(json['status'] as String);
    // A generating node can't be resumed after serialization — mark as error
    if (status == GenStatus.generating) status = GenStatus.error;
    return GenNode(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      sourceImageId: json['sourceImageId'] as String?,
      prompt: json['prompt'] as String,
      status: status,
      images: (json['images'] as List)
          .map((e) => GenImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: status == GenStatus.error
          ? (json['error'] as String? ?? 'Generování přerušeno')
          : null,
    );
  }

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
