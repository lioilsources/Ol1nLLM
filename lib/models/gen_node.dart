import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Lifecycle of a single generation round.
enum GenStatus { generating, ready, error }

/// One produced image stored as a PNG file on disk.
///
/// Keeping full PNG bytes inside the Hive session box caused OOM when reading
/// back large multi-session blobs. The box now stores only the file path.
class GenImage {
  final String id;
  final String filePath;
  Uint8List? _bytes;

  GenImage({required this.id, required this.filePath});

  /// PNG bytes, read from [filePath] and cached for the lifetime of this
  /// instance so repeated accesses (e.g. Gal save) skip the disk read.
  Uint8List get bytes => _bytes ??= File(filePath).readAsBytesSync();

  /// Write [bytes] to [dir] as `<uuid>.png` and return a [GenImage] pointing
  /// to the new file. The bytes are cached so the first [bytes] call is free.
  static Future<GenImage> save(Uint8List bytes, Directory dir) async {
    final id = _uuid.v4();
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(bytes, flush: true);
    return GenImage(id: id, filePath: file.path).._bytes = bytes;
  }

  Map<String, dynamic> toJson() => {'id': id, 'filePath': filePath};

  factory GenImage.fromJson(Map<String, dynamic> json) =>
      GenImage(id: json['id'] as String, filePath: json['filePath'] as String);
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

  /// Server-assigned job id emitted by [GenSubmitted]. Persisted so the
  /// provider can call [ImageBackend.follow] after an app suspension/restart.
  final String? jobId;

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
    this.jobId,
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
    if (jobId != null) 'jobId': jobId,
  };

  factory GenNode.fromJson(Map<String, dynamic> json) {
    var status = GenStatus.values.byName(json['status'] as String);
    final jobId = json['jobId'] as String?;
    // Keep generating status only when a jobId is present — the provider
    // will call follow() to re-attach. Without jobId there's no way to resume.
    if (status == GenStatus.generating && jobId == null) {
      status = GenStatus.error;
    }
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
      jobId: jobId,
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
    String? jobId,
    bool clearJobId = false,
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
    jobId: clearJobId ? null : (jobId ?? this.jobId),
  );
}
