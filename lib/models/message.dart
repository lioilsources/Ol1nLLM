enum MessageRole { user, assistant }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  /// Base64-encoded images attached to this message — either an input image
  /// (user, for edit/OCR) or a generated result (assistant). Empty for plain
  /// chat messages.
  final List<String> images;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.images = const [],
  });

  Message copyWith({String? content, List<String>? images}) => Message(
        id: id,
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
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        if (images.isNotEmpty) 'images': images,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: MessageRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        images: (json['images'] as List?)?.cast<String>() ?? const [],
      );
}
