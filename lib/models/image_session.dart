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
    required this.modelId,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<GenNode> nodes;
  final String? currentNodeId;
  final String? selectedLora;

  /// [ImageModelSpec.id] the session was generated with (implies the backend).
  final String modelId;
  final DateTime updatedAt;

  String? get thumbnailFilePath {
    for (final n in nodes) {
      if (n.status == GenStatus.ready && n.images.isNotEmpty) {
        return n.images.first.filePath;
      }
    }
    return null;
  }

  factory ImageSession.create({
    String? id,
    required List<GenNode> nodes,
    String? currentNodeId,
    String? selectedLora,
    required String modelId,
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
      modelId: modelId,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    if (currentNodeId != null) 'currentNodeId': currentNodeId,
    if (selectedLora != null) 'selectedLora': selectedLora,
    'modelId': modelId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ImageSession.fromJson(Map<String, dynamic> json) => ImageSession(
    id: json['id'] as String,
    title: json['title'] as String,
    nodes: (json['nodes'] as List)
        .map((e) => GenNode.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentNodeId: json['currentNodeId'] as String?,
    selectedLora: json['selectedLora'] as String?,
    modelId: json['modelId'] as String? ??
        _legacyModelId(
          json['backendId'] as String?,
          json['workflow'] as String?,
        ),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
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
