import 'agent_step.dart';
import 'library_source.dart';

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

  /// Persona (role) this turn was sent under. Set on the user message so a
  /// branch can switch roles independently; node visuals use its emoji and the
  /// active branch inherits the nearest message that carries one.
  final String? personaId;

  /// Chunks a library (RAG) answer was built from. Empty for every other
  /// backend. Snapshotted on the assistant message when the stream finishes,
  /// so the citations survive a restart with the answer they belong to.
  final List<LibrarySource> sources;

  /// Structured result of a Právník contract-agent step (questions, intake
  /// progress, finished document). Only on assistant messages of the
  /// `law-agent` backend; snapshotted like [sources].
  final AgentStep? agentStep;

  /// Answers from an agent question card. Only on the user message that
  /// submitted them; [content] holds the same answers as readable text.
  final List<AgentAnswer> agentAnswers;

  const Message({
    required this.id,
    this.parentId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.images = const [],
    this.personaId,
    this.sources = const [],
    this.agentStep,
    this.agentAnswers = const [],
  });

  Message copyWith({
    String? content,
    List<String>? images,
    String? parentId,
    String? personaId,
    List<LibrarySource>? sources,
    AgentStep? agentStep,
  }) => Message(
    id: id,
    parentId: parentId ?? this.parentId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    images: images ?? this.images,
    personaId: personaId ?? this.personaId,
    sources: sources ?? this.sources,
    agentStep: agentStep ?? this.agentStep,
    agentAnswers: agentAnswers,
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
    if (personaId != null) 'personaId': personaId,
    if (sources.isNotEmpty) 'sources': sources.map((s) => s.toJson()).toList(),
    if (agentStep != null) 'agentStep': agentStep!.toJson(),
    if (agentAnswers.isNotEmpty)
      'agentAnswers': agentAnswers.map((a) => a.toJson()).toList(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    parentId: json['parentId'] as String?,
    role: MessageRole.values.byName(json['role'] as String),
    content: json['content'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    images: (json['images'] as List?)?.cast<String>() ?? [],
    personaId: json['personaId'] as String?,
    sources: LibrarySource.listFrom(json['sources']),
    agentStep: json['agentStep'] is Map
        ? AgentStep.fromJson((json['agentStep'] as Map).cast())
        : null,
    agentAnswers:
        (json['agentAnswers'] as List?)
            ?.whereType<Map>()
            .map((m) => AgentAnswer.fromJson(m.cast()))
            .toList() ??
        const [],
  );
}
