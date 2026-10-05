/// One retrieved chunk backing a library (RAG) answer.
///
/// Field names mirror the server 1:1 (`rag/server.py: _sources`) so a payload
/// dump and this class read the same. Everything except [work] and [excerpt]
/// is optional because the server builds these from `meta.get(...)` and older
/// ingests do not carry every key.
class LibrarySource {
  /// Work the chunk comes from, e.g. `zhuangzi`.
  final String work;

  /// Curated Czech name of the work (`summaries.json: name_cs`), e.g.
  /// `Khuddaka-nikája — Otázky krále Milindy`. Null for works that have none
  /// (the Mahábhárata parvy are already Czech) and for older answers stored
  /// before the server started sending it.
  final String? nameCs;

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

  /// Czech translation of [excerpt], made by the server while the answer was
  /// still streaming. Null when translation is off, failed, or the answer
  /// predates it — the original then stands alone.
  final String? excerptCs;

  /// Link to the original document the chunk was cut from. Sent only by
  /// LeadsRAG (`leadsd`, persona Leads 📈), where it points at the contract
  /// in Registr smluv (`https://smlouvy.gov.cz/smlouva/<id>`); the library
  /// and law servers have no public original, so for them — and for answers
  /// stored in Hive before the field existed — it stays null. Server data,
  /// not trusted: the UI opens it only when [openableUrl] says so.
  final String? url;

  const LibrarySource({
    required this.work,
    this.nameCs,
    this.title,
    this.group,
    this.lang,
    this.path,
    this.distance,
    required this.excerpt,
    this.excerptCs,
    this.url,
  });

  /// Label for the sources list: the Czech name when the catalog has one,
  /// else the title when it adds something, else the raw work name.
  String get label {
    final cs = nameCs?.trim();
    if (cs != null && cs.isNotEmpty) return cs;
    final t = title?.trim();
    if (t == null || t.isEmpty || t == work) return work;
    return t;
  }

  /// Chunk position out of the ingest title — `"zhuangzi (část 233/488)"`
  /// → `"část 233/488"`. Surfaced in [subtitle] only when [label] shows the
  /// Czech name instead of the title, so the position is never lost.
  String? get _chunkPart {
    final t = title?.trim();
    if (t == null) return null;
    final m = RegExp(r'\(([^)]+)\)$').firstMatch(t);
    return m?.group(1);
  }

  /// `část N/M · group · lang`, skipping whatever is missing.
  String get subtitle => [
    if (nameCs != null && nameCs!.trim().isNotEmpty) _chunkPart,
    group,
    lang,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');

  /// What to show as the citation body: the translation when there is one.
  String get readableExcerpt {
    final cs = excerptCs?.trim();
    return (cs != null && cs.isNotEmpty) ? cs : excerpt;
  }

  /// True when [readableExcerpt] is a translation, so the UI can also offer
  /// the original — the untranslated text is the actual evidence.
  bool get hasTranslation {
    final cs = excerptCs?.trim();
    return cs != null && cs.isNotEmpty && cs != excerpt;
  }

  /// [url] parsed, but only for `http`/`https` with a host — anything else
  /// (`javascript:`, `file:`, `intent:`, garbage) yields null so the UI never
  /// hands an arbitrary scheme to the OS.
  Uri? get openableUrl {
    final raw = url;
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') ? uri : null;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory LibrarySource.fromJson(Map<String, dynamic> json) => LibrarySource(
    work: _str(json['work']) ?? 'neznámý zdroj',
    nameCs: _str(json['name_cs']),
    title: _str(json['title']),
    group: _str(json['group']),
    lang: _str(json['lang']),
    path: _str(json['path']),
    distance: (json['distance'] as num?)?.toDouble(),
    excerpt: _str(json['excerpt']) ?? '',
    excerptCs: _str(json['excerpt_cs']),
    url: _str(json['url']),
  );

  Map<String, dynamic> toJson() => {
    'work': work,
    if (nameCs != null) 'name_cs': nameCs,
    if (title != null) 'title': title,
    if (group != null) 'group': group,
    if (lang != null) 'lang': lang,
    if (path != null) 'path': path,
    if (distance != null) 'distance': distance,
    if (excerpt.isNotEmpty) 'excerpt': excerpt,
    if (excerptCs != null) 'excerpt_cs': excerptCs,
    if (url != null) 'url': url,
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
