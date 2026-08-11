import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Lifecycle of a single generation round.
enum GenStatus { generating, ready, error }

/// One produced image stored as a PNG file on disk.
///
/// Keeping full PNG bytes inside the Hive session box caused OOM when reading
/// back large multi-session blobs. The box now stores only the file name.
///
/// We store the *relative* file name, not an absolute path: on iOS the app's
/// data-container prefix (`…/Containers/Data/Application/<UUID>/…`) changes on
/// every reinstall and on device restore/migration, so persisting an absolute
/// path would make the whole history point at a dead container after the next
/// launch. The absolute path is rebuilt at runtime against [baseDir].
class GenImage {
  /// Absolute path of the `image_studio` directory for the *current* launch.
  /// Set once at startup from getApplicationSupportDirectory() before any
  /// loaded image is rendered (see ImageStudioNotifier._init).
  static late String baseDir;

  final String id;

  /// Relative file name, e.g. `<uuid>.png`.
  final String fileName;
  Uint8List? _bytes;

  GenImage({required this.id, required this.fileName});

  /// Absolute path to the PNG for the current launch.
  String get filePath => '$baseDir/$fileName';

  /// PNG bytes, read from [filePath] and cached for the lifetime of this
  /// instance so repeated accesses (e.g. Gal save) skip the disk read.
  Uint8List get bytes => _bytes ??= File(filePath).readAsBytesSync();

  /// Write [bytes] to [dir] as `<uuid>.png` and return a [GenImage] pointing
  /// to the new file. The bytes are cached so the first [bytes] call is free.
  static Future<GenImage> save(Uint8List bytes, Directory dir) async {
    final id = _uuid.v4();
    final fileName = '$id.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return GenImage(id: id, fileName: fileName).._bytes = bytes;
  }

  Map<String, dynamic> toJson() => {'id': id, 'fileName': fileName};

  factory GenImage.fromJson(Map<String, dynamic> json) {
    // Backward compat: legacy boxes stored an absolute 'filePath'. Derive the
    // relative name from its basename so old sessions self-heal on the same
    // install (where the files still exist).
    final fileName = (json['fileName'] as String?) ??
        (json['filePath'] as String).split('/').last;
    return GenImage(id: json['id'] as String, fileName: fileName);
  }
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

  /// Relative file name of the inpaint mask PNG (same directory scheme as
  /// [GenImage.fileName]; white = repainted area). Non-null marks this node
  /// as an inpaint round: retry re-sends the mask and prompt chaining is
  /// skipped. Nullable — nodes written before this existed stay valid.
  final String? maskFileName;

  /// Relative file name of the inpaint reference PNG (IPAdapter appearance
  /// donor), or null for text-only inpaint. Only set when [maskFileName] is.
  final String? refFileName;

  // ── Generation metadata (nullable — nodes written before this existed
  //    stay valid; NIM models leave preset-derived fields null because their
  //    values are service constants recoverable from [modelId]) ──
  /// [ImageModelSpec.id] this node was actually generated with. Session-level
  /// modelId only reflects the *latest* choice, so it's snapshotted here.
  final String? modelId;
  final String? loraName;
  final String? poseId;

  /// Base RNG seed passed to the backend. ComfyUI batches share one seed
  /// (variants differ by batch index); NIM sends seed+i for request i.
  final int? seed;
  final String? negativePrompt;

  /// Score-tag/style prefix prepended to [prompt] at generation time.
  /// Effective positive prompt = '$positivePrefix, $prompt'.
  final String? positivePrefix;
  final int? width;
  final int? height;
  final int? steps;
  final double? cfg;
  final double? denoise;
  final String? samplerName;
  final String? scheduler;
  final DateTime? createdAt;

  /// 'upload' for user-photo roots (never training outputs), null/'generated'
  /// for model outputs. Only persisted when 'upload'.
  final String? origin;

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
    this.maskFileName,
    this.refFileName,
    this.modelId,
    this.loraName,
    this.poseId,
    this.seed,
    this.negativePrompt,
    this.positivePrefix,
    this.width,
    this.height,
    this.steps,
    this.cfg,
    this.denoise,
    this.samplerName,
    this.scheduler,
    this.createdAt,
    this.origin,
  });

  bool get isRoot => parentId == null;

  factory GenNode.create({
    String? id,
    String? parentId,
    String? sourceImageId,
    required String prompt,
    String? maskFileName,
    String? refFileName,
    String? modelId,
    String? loraName,
    String? poseId,
    int? seed,
    String? negativePrompt,
    String? positivePrefix,
    int? width,
    int? height,
    int? steps,
    double? cfg,
    double? denoise,
    String? samplerName,
    String? scheduler,
    String? origin,
  }) => GenNode(
    id: id ?? _uuid.v4(),
    parentId: parentId,
    sourceImageId: sourceImageId,
    prompt: prompt,
    status: GenStatus.generating,
    maskFileName: maskFileName,
    refFileName: refFileName,
    modelId: modelId,
    loraName: loraName,
    poseId: poseId,
    seed: seed,
    negativePrompt: negativePrompt,
    positivePrefix: positivePrefix,
    width: width,
    height: height,
    steps: steps,
    cfg: cfg,
    denoise: denoise,
    samplerName: samplerName,
    scheduler: scheduler,
    createdAt: DateTime.now(),
    origin: origin,
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
    if (maskFileName != null) 'maskFileName': maskFileName,
    if (refFileName != null) 'refFileName': refFileName,
    if (modelId != null) 'modelId': modelId,
    if (loraName != null) 'loraName': loraName,
    if (poseId != null) 'poseId': poseId,
    if (seed != null) 'seed': seed,
    if (negativePrompt != null) 'negativePrompt': negativePrompt,
    if (positivePrefix != null) 'positivePrefix': positivePrefix,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (steps != null) 'steps': steps,
    if (cfg != null) 'cfg': cfg,
    if (denoise != null) 'denoise': denoise,
    if (samplerName != null) 'samplerName': samplerName,
    if (scheduler != null) 'scheduler': scheduler,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (origin == 'upload') 'origin': origin,
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
      maskFileName: json['maskFileName'] as String?,
      refFileName: json['refFileName'] as String?,
      modelId: json['modelId'] as String?,
      loraName: json['loraName'] as String?,
      poseId: json['poseId'] as String?,
      seed: json['seed'] as int?,
      negativePrompt: json['negativePrompt'] as String?,
      positivePrefix: json['positivePrefix'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      steps: json['steps'] as int?,
      cfg: (json['cfg'] as num?)?.toDouble(),
      denoise: (json['denoise'] as num?)?.toDouble(),
      samplerName: json['samplerName'] as String?,
      scheduler: json['scheduler'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
      origin: json['origin'] as String?,
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
    maskFileName: maskFileName,
    refFileName: refFileName,
    modelId: modelId,
    loraName: loraName,
    poseId: poseId,
    seed: seed,
    negativePrompt: negativePrompt,
    positivePrefix: positivePrefix,
    width: width,
    height: height,
    steps: steps,
    cfg: cfg,
    denoise: denoise,
    samplerName: samplerName,
    scheduler: scheduler,
    createdAt: createdAt,
    origin: origin,
  );
}
