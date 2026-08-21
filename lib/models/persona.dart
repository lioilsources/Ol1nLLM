class Persona {
  final String id;
  final String name;
  final String emoji;
  final String description;

  /// Asset path of the system prompt. Null for personas whose backend builds
  /// its own prompt server-side (the library chatbot) — a placeholder .md
  /// there would look functional and never be read.
  final String? file;

  /// Which chat backend answers under this persona. Null = the default vLLM
  /// chat; `kChatBackendLibrary` routes to the RAG library server.
  final String? backend;

  const Persona({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    this.file,
    this.backend,
  });

  factory Persona.fromJson(Map<String, dynamic> json) => Persona(
    id: json['id'] as String,
    name: json['name'] as String,
    emoji: json['emoji'] as String,
    description: json['description'] as String,
    file: json['file'] as String?,
    backend: json['backend'] as String?,
  );
}
