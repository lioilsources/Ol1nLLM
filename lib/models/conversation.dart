import 'package:uuid/uuid.dart';
import 'message.dart';

const _uuid = Uuid();

class Conversation {
  final String id;
  final String title;
  final List<Message> messages;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  factory Conversation.create() => Conversation(
        id: _uuid.v4(),
        title: 'New conversation',
        messages: const [],
        updatedAt: DateTime.now(),
      );

  Conversation copyWith({
    String? title,
    List<Message>? messages,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
