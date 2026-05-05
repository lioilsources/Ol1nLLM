class Persona {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String file;

  const Persona({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.file,
  });

  factory Persona.fromJson(Map<String, dynamic> json) => Persona(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        description: json['description'] as String,
        file: json['file'] as String,
      );
}
