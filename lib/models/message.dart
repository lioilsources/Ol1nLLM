enum MessageRole { user, assistant }

class Message {
  final String id;

  /// Id of the previous message on this branch (null for the conversation
  /// root). Lets a conversation form a tree instead of a flat list: sending
  /// from an older message creates a sibling branch.
  final String? parentId;

  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final List<String> images; // base64-encoded PNG/JPEG

  const Message({
    required this.id,
    this.parentId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.images = const [],
  });

  Message copyWith({String? content, List<String>? images, String? parentId}) =>
      Message(
        id: id,
        parentId: parentId ?? this.parentId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        images: images ?? this.images,
      );

  Map<String, dynamic> toOllamaJson() => {
    'role': role.name,
    'content': content,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    if (parentId != null) 'parentId': parentId,
    'role': role.name,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (images.isNotEmpty) 'images': images,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    parentId: json['parentId'] as String?,
    role: MessageRole.values.byName(json['role'] as String),
    content: json['content'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    images: (json['images'] as List?)?.cast<String>() ?? [],
  );
}
