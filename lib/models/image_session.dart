import 'package:uuid/uuid.dart';
import 'gen_node.dart';
import '../services/comfyui_service.dart' show ComfyWorkflow;
import '../services/image_backend.dart' show kBackendComfyUI;

const _uuid = Uuid();

class ImageSession {
  const ImageSession({
    required this.id,
    required this.title,
    required this.nodes,
    this.currentNodeId,
    this.selectedLora,
    required this.workflow,
    required this.updatedAt,
    this.backendId = kBackendComfyUI,
  });

  final String id;
  final String title;
  final List<GenNode> nodes;
  final String? currentNodeId;
  final String? selectedLora;
  final ComfyWorkflow workflow;
  final DateTime updatedAt;
  final String backendId;

  String? get thumbnailB64 {
    for (final n in nodes) {
      if (n.status == GenStatus.ready && n.images.isNotEmpty) {
        return n.images.first.b64;
      }
    }
    return null;
  }

  factory ImageSession.create({
    String? id,
    required List<GenNode> nodes,
    String? currentNodeId,
    String? selectedLora,
    required ComfyWorkflow workflow,
    String backendId = kBackendComfyUI,
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
      workflow: workflow,
      updatedAt: DateTime.now(),
      backendId: backendId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    if (currentNodeId != null) 'currentNodeId': currentNodeId,
    if (selectedLora != null) 'selectedLora': selectedLora,
    'workflow': workflow.name,
    'updatedAt': updatedAt.toIso8601String(),
    'backendId': backendId,
  };

  factory ImageSession.fromJson(Map<String, dynamic> json) => ImageSession(
    id: json['id'] as String,
    title: json['title'] as String,
    nodes: (json['nodes'] as List)
        .map((e) => GenNode.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentNodeId: json['currentNodeId'] as String?,
    selectedLora: json['selectedLora'] as String?,
    workflow: ComfyWorkflow.values.byName(json['workflow'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    backendId: json['backendId'] as String? ?? kBackendComfyUI,
  );
}
