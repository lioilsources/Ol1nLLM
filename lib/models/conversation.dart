import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'message.dart';

const _uuid = Uuid();

class Conversation {
  final String id;
  final String title;

  /// Pool of every message across all branches (not necessarily a single
  /// chain). The visible/active conversation is [thread] — the path from the
  /// root down to [activeLeafId].
  final List<Message> messages;
  final DateTime updatedAt;
  final String? personaId;

  /// Id of the message at the tip of the currently active branch. Sending a
  /// new message appends a child of this leaf; selecting an older node moves
  /// the leaf there, so the next send branches.
  final String? activeLeafId;

  const Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.personaId,
    this.activeLeafId,
  });

  factory Conversation.create({String? personaId}) => Conversation(
    id: _uuid.v4(),
    title: 'New conversation',
    messages: const [],
    updatedAt: DateTime.now(),
    personaId: personaId,
  );

  Conversation copyWith({
    String? title,
    List<Message>? messages,
    DateTime? updatedAt,
    String? personaId,
    bool clearPersona = false,
    String? activeLeafId,
  }) => Conversation(
    id: id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    updatedAt: updatedAt ?? this.updatedAt,
    personaId: clearPersona ? null : (personaId ?? this.personaId),
    activeLeafId: activeLeafId ?? this.activeLeafId,
  );

  Message? get _byIdLeaf =>
      messages.where((m) => m.id == activeLeafId).firstOrNull;

  /// Messages on the active branch, root→leaf. Falls back to the whole list
  /// when no parent links exist yet (legacy / freshly migrated chains).
  List<Message> get thread {
    if (messages.isEmpty) return const [];
    final byId = {for (final m in messages) m.id: m};
    var leaf = _byIdLeaf;
    // No explicit leaf → use the most recent message as the tip.
    leaf ??= messages.last;
    final out = <Message>[];
    Message? node = leaf;
    final seen = <String>{};
    while (node != null && seen.add(node.id)) {
      out.insert(0, node);
      final pid = node.parentId;
      node = pid == null ? null : byId[pid];
    }
    return out;
  }

  /// The assistant reply that directly follows [userMessageId] on its branch
  /// (the second half of a turn), or null if none yet.
  Message? replyOf(String userMessageId) => messages
      .where((m) => m.parentId == userMessageId && m.role == MessageRole.assistant)
      .firstOrNull;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    if (personaId != null) 'personaId': personaId,
    if (activeLeafId != null) 'activeLeafId': activeLeafId,
  };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
    var activeLeafId = json['activeLeafId'] as String?;

    // Migrate legacy flat conversations: if no message carries a parentId,
    // link them into a single chain so they form a (degenerate) tree.
    final hasLinks = messages.any((m) => m.parentId != null);
    if (!hasLinks && messages.isNotEmpty) {
      for (var i = 0; i < messages.length; i++) {
        messages[i] = messages[i].copyWith(
          parentId: i == 0 ? null : messages[i - 1].id,
        );
      }
      activeLeafId ??= messages.last.id;
    }

    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: messages,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      personaId: json['personaId'] as String?,
      activeLeafId: activeLeafId,
    );
  }
}
