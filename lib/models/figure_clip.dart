/// A dance of the figure library served by UGCFactory
/// (`GET /v1/fc/animations?category=dance`). [id] is also the name of the
/// animation inside the downloaded GLB — the server names every glTF
/// animation after its clip id, so the viewer plays a dance by that id.
class FigureClip {
  final String id;

  /// Human label from the library (Czech, curated on the server).
  final String name;

  const FigureClip({required this.id, required this.name});

  factory FigureClip.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = (json['name'] as String?)?.trim();
    return FigureClip(id: id, name: name == null || name.isEmpty ? id : name);
  }
}

/// Label for [clipId]: the catalog name when the catalog knows it, else the id
/// made readable. A figure made with an older catalog must still show its
/// dances after the server renamed or dropped one.
String figureClipLabel(String clipId, List<FigureClip> catalog) {
  for (final c in catalog) {
    if (c.id == clipId) return c.name;
  }
  final words = clipId.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return clipId;
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}
