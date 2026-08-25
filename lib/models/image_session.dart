import 'package:uuid/uuid.dart';
import 'gen_node.dart';
import 'image_model.dart';

const _uuid = Uuid();

class ImageSession {
  const ImageSession({
    required this.id,
    required this.title,
    required this.nodes,
    this.currentNodeId,
    this.selectedLora,
    this.loraStrength,
    this.selectedPoseId,
    this.selectedStyleId,
    this.editDenoise,
    required this.modelId,
    required this.updatedAt,
    this.exportedAt,
    this.exportedImageCount,
  });

  final String id;
  final String title;
  final List<GenNode> nodes;
  final String? currentNodeId;
  final String? selectedLora;

  /// LoRA strength used in this session (null = app default).
  final double? loraStrength;
  final String? selectedPoseId;

  /// Art-style preset id appended to prompts in this session (see
  /// [kStylePresets]); null = no style.
  final String? selectedStyleId;

  /// img2img denoise chosen by the user; null = the model preset's value.
  final double? editDenoise;

  /// [ImageModelSpec.id] the session was generated with (implies the backend).
  final String modelId;
  final DateTime updatedAt;

  /// When this session was last exported to the FINETUNE gallery, and how many
  /// ready images the export covered. Staleness is judged against the image
  /// count, not [updatedAt] — that bumps on mere navigation too.
  final DateTime? exportedAt;
  final int? exportedImageCount;

  String? get thumbnailFilePath {
    for (final n in nodes) {
      if (n.status == GenStatus.ready && n.images.isNotEmpty) {
        return n.images.first.filePath;
      }
    }
    return null;
  }

  /// Images an export would cover (ready nodes only).
  int get readyImageCount {
    var count = 0;
    for (final n in nodes) {
      if (n.status == GenStatus.ready) count += n.images.length;
    }
    return count;
  }

  /// True when there is something new to export.
  bool get isExportStale =>
      exportedAt == null || exportedImageCount != readyImageCount;

  ImageSession copyWithExport({
    required DateTime exportedAt,
    required int exportedImageCount,
  }) => ImageSession(
    id: id,
    title: title,
    nodes: nodes,
    currentNodeId: currentNodeId,
    selectedLora: selectedLora,
    loraStrength: loraStrength,
    selectedPoseId: selectedPoseId,
    modelId: modelId,
    updatedAt: updatedAt,
    exportedAt: exportedAt,
    exportedImageCount: exportedImageCount,
  );

  factory ImageSession.create({
    String? id,
    required List<GenNode> nodes,
    String? currentNodeId,
    String? selectedLora,
    double? loraStrength,
    String? selectedPoseId,
    String? selectedStyleId,
    double? editDenoise,
    required String modelId,
    DateTime? exportedAt,
    int? exportedImageCount,
  }) {
    GenNode? root;
    for (final n in nodes) {
      if (n.parentId == null) {
        root = n;
        break;
      }
    }
    final prompt = root?.prompt ?? '';
    final title = prompt.isEmpty
        ? 'Image session'
        : prompt.length > 40
            ? '${prompt.substring(0, 40)}…'
            : prompt;

    return ImageSession(
      id: id ?? _uuid.v4(),
      title: title,
      nodes: List.unmodifiable(nodes),
      currentNodeId: currentNodeId,
      selectedLora: selectedLora,
      loraStrength: loraStrength,
      selectedPoseId: selectedPoseId,
      selectedStyleId: selectedStyleId,
      editDenoise: editDenoise,
      modelId: modelId,
      updatedAt: DateTime.now(),
      exportedAt: exportedAt,
      exportedImageCount: exportedImageCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    if (currentNodeId != null) 'currentNodeId': currentNodeId,
    if (selectedLora != null) 'selectedLora': selectedLora,
    if (loraStrength != null) 'loraStrength': loraStrength,
    if (selectedPoseId != null) 'selectedPoseId': selectedPoseId,
    if (selectedStyleId != null) 'selectedStyleId': selectedStyleId,
    if (editDenoise != null) 'editDenoise': editDenoise,
    'modelId': modelId,
    'updatedAt': updatedAt.toIso8601String(),
    if (exportedAt != null) 'exportedAt': exportedAt!.toIso8601String(),
    if (exportedImageCount != null) 'exportedImageCount': exportedImageCount,
  };

  factory ImageSession.fromJson(Map<String, dynamic> json) => ImageSession(
    id: json['id'] as String,
    title: json['title'] as String,
    nodes: (json['nodes'] as List)
        .map((e) => GenNode.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentNodeId: json['currentNodeId'] as String?,
    selectedLora: json['selectedLora'] as String?,
    loraStrength: (json['loraStrength'] as num?)?.toDouble(),
    selectedPoseId: json['selectedPoseId'] as String?,
    selectedStyleId: json['selectedStyleId'] as String?,
    editDenoise: (json['editDenoise'] as num?)?.toDouble(),
    modelId: json['modelId'] as String? ??
        _legacyModelId(
          json['backendId'] as String?,
          json['workflow'] as String?,
        ),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    exportedAt: json['exportedAt'] == null
        ? null
        : DateTime.tryParse(json['exportedAt'] as String),
    exportedImageCount: json['exportedImageCount'] as int?,
  );

  /// Sessions written before the unified model picker stored a backendId +
  /// ComfyWorkflow name pair; map them onto the equivalent model id so old
  /// history (including in-flight jobs awaiting follow()) keeps working.
  static String _legacyModelId(String? backendId, String? workflow) =>
      switch (backendId) {
        'flux_nim' => 'flux-schnell',
        'flux_kontext_nim' => 'flux-kontext',
        _ => workflow == 'pony' ? 'pony' : kDefaultImageModelId,
      };
}
