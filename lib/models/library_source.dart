/// One retrieved chunk backing a library (RAG) answer.
///
/// Field names mirror the server 1:1 (`rag/server.py: _sources`) so a payload
/// dump and this class read the same. Everything except [work] and [excerpt]
/// is optional because the server builds these from `meta.get(...)` and older
/// ingests do not carry every key.
class LibrarySource {
  /// Work the chunk comes from, e.g. `zhuangzi`.
  final String work;

  /// Human title from ingest metadata. In practice it carries the chunk
  /// position too — `"zhuangzi (část 233/488)"` — which is worth showing.
  final String? title;

  /// Tradition the work belongs to, e.g. `chinese`, `buddhist`.
  final String? group;

  final String? lang;

  /// Corpus-relative path of the source file.
  final String? path;

  /// Vector **distance**, not a similarity — lower means a closer match
  /// (observed range on real answers: ~0.15–0.25). Never render this as a
  /// percentage without inverting it first.
  final double? distance;

  /// First 200 characters of the chunk (the server truncates, not us).
  final String excerpt;

  const LibrarySource({
    required this.work,
    this.title,
    this.group,
    this.lang,
    this.path,
    this.distance,
    required this.excerpt,
  });

  /// Label for the sources list: the title when it adds something, else work.
  String get label {
    final t = title?.trim();
    if (t == null || t.isEmpty || t == work) return work;
    return t;
  }

  /// `group · lang`, skipping whichever half is missing.
  String get subtitle =>
      [group, lang].where((s) => s != null && s.isNotEmpty).join(' · ');

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory LibrarySource.fromJson(Map<String, dynamic> json) => LibrarySource(
    work: _str(json['work']) ?? 'neznámý zdroj',
    title: _str(json['title']),
    group: _str(json['group']),
    lang: _str(json['lang']),
    path: _str(json['path']),
    distance: (json['distance'] as num?)?.toDouble(),
    excerpt: _str(json['excerpt']) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'work': work,
    if (title != null) 'title': title,
    if (group != null) 'group': group,
    if (lang != null) 'lang': lang,
    if (path != null) 'path': path,
    if (distance != null) 'distance': distance,
    if (excerpt.isNotEmpty) 'excerpt': excerpt,
  };

  /// Tolerant list parser — used for both the wire payload and Hive JSON.
  /// Anything that is not a list of maps yields an empty list rather than
  /// throwing, so one malformed answer cannot make a conversation unloadable.
  static List<LibrarySource> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <LibrarySource>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          out.add(LibrarySource.fromJson(e.cast<String, dynamic>()));
        } catch (_) {
          // skip unreadable entry
        }
      }
    }
    return out;
  }
}
