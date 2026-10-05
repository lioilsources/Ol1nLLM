/// One step of the Právník contract agent (`POST /agent/chat` on `law-chat`,
/// WorldLibraryProject `rag/agent/klient.py`). The server answers with a
/// single JSON object per step — no stream — carrying structured data the
/// app renders as cards: questions to fill in, the intake progress and, at
/// the end, the finished document with its checklist and warnings.
///
/// Field names mirror the server (Czech), so a capture from the live server
/// (`test/fixtures/law_agent_*.json`) parses without a mapping layer.
library;

/// A question the agent wants answered (`ask_user`, or the next missing
/// variable from the template). [id] is the template variable the answer is
/// saved under; the server only accepts ids the template knows.
class AgentQuestion {
  final String id;
  final String question;

  /// `string | text | money | date | int | enum | bool` — picks the input.
  final String type;

  /// Allowed values for `enum`.
  final List<String> options;
  final String? hint;

  /// Current value when the server asks to *correct* an answer that breaks
  /// a statutory limit (e.g. deposit over 3× rent); null for a new question.
  final String? current;

  const AgentQuestion({
    required this.id,
    required this.question,
    this.type = 'string',
    this.options = const [],
    this.hint,
    this.current,
  });

  factory AgentQuestion.fromJson(Map<String, dynamic> j) => AgentQuestion(
    id: (j['id'] ?? '') as String,
    question: (j['otazka'] ?? '') as String,
    type: (j['typ'] as String?) ?? 'string',
    options: (j['hodnoty'] as List?)?.map((e) => '$e').toList() ?? const [],
    hint: _nonEmpty(j['napoveda']),
    current: j['hodnota'] == null ? null : '${j['hodnota']}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'otazka': question,
    'typ': type,
    if (options.isNotEmpty) 'hodnoty': options,
    if (hint != null) 'napoveda': hint,
    if (current != null) 'hodnota': current,
  };
}

/// The user's answer to one [AgentQuestion]. Sent as `odpovedi[]`; the
/// server converts the value by the variable's type ("16 500 Kč" → 16500,
/// "1. 10. 2026" → 2026-10-01) and saves it into the intake itself.
class AgentAnswer {
  final String id;
  final String question;
  final String value;

  const AgentAnswer({
    required this.id,
    required this.question,
    required this.value,
  });

  factory AgentAnswer.fromJson(Map<String, dynamic> j) => AgentAnswer(
    id: j['id'] as String,
    question: (j['otazka'] ?? '') as String,
    value: '${j['hodnota'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'otazka': question,
    'hodnota': value,
  };
}

/// A statutory limit the current answers break (`porusene_limity`).
class AgentLimit {
  final String message;
  final String? basis;

  const AgentLimit(this.message, [this.basis]);

  factory AgentLimit.fromJson(Map<String, dynamic> j) =>
      AgentLimit((j['zprava'] ?? '') as String, _nonEmpty(j['zaklad']));

  Map<String, dynamic> toJson() => {
    'zprava': message,
    if (basis != null) 'zaklad': basis,
  };
}

/// Where the document being drafted stands (`stav`). Null on a step before
/// the agent has picked a template.
class AgentIntake {
  final String template;
  final String title;

  /// `intake` while answers are collected, `hotovo` once rendered.
  final String status;
  final int required;
  final int requiredFilled;
  final bool readyToRender;
  final List<AgentLimit> limits;

  const AgentIntake({
    required this.template,
    required this.title,
    this.status = 'intake',
    this.required = 0,
    this.requiredFilled = 0,
    this.readyToRender = false,
    this.limits = const [],
  });

  double get progress => required == 0 ? 0 : requiredFilled / required;

  factory AgentIntake.fromJson(Map<String, dynamic> j) => AgentIntake(
    template: (j['typ'] ?? '') as String,
    title: (j['nazev'] ?? j['typ'] ?? '') as String,
    status: (j['stav'] as String?) ?? 'intake',
    required: (j['povinnych'] as num?)?.toInt() ?? 0,
    requiredFilled: (j['povinnych_vyplneno'] as num?)?.toInt() ?? 0,
    readyToRender: j['pripraveno_k_renderu'] == true,
    limits: _list(j['porusene_limity'], AgentLimit.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'typ': template,
    'nazev': title,
    'stav': status,
    'povinnych': required,
    'povinnych_vyplneno': requiredFilled,
    'pripraveno_k_renderu': readyToRender,
    if (limits.isNotEmpty)
      'porusene_limity': limits.map((l) => l.toJson()).toList(),
  };
}

/// Everything structured one agent step returned, snapshotted on the
/// assistant message (Hive) so the cards and the document survive a restart.
class AgentStep {
  final String mode;
  final List<AgentQuestion> questions;

  /// Finished document (markdown); null until `render_document` succeeded.
  final String? document;
  final List<String> checklist;
  final List<String> warnings;
  final AgentIntake? intake;

  /// Answers from the previous card the server refused, with the reason
  /// („„hodně“ není číslo"). Shown so the user knows why a question repeats.
  final List<({String id, String reason})> rejected;

  const AgentStep({
    this.mode = 'draft',
    this.questions = const [],
    this.document,
    this.checklist = const [],
    this.warnings = const [],
    this.intake,
    this.rejected = const [],
  });

  bool get hasDocument => document != null && document!.trim().isNotEmpty;

  /// Server response of `POST /agent/chat` (or the Hive snapshot below).
  factory AgentStep.fromJson(Map<String, dynamic> j) {
    final saved = j['ulozene_odpovedi'];
    final rejected = <({String id, String reason})>[];
    if (saved is Map && saved['odmitnuto'] is List) {
      for (final r in (saved['odmitnuto'] as List).whereType<Map>()) {
        rejected.add((id: '${r['id']}', reason: '${r['duvod'] ?? ''}'));
      }
    }
    final stav = j['stav'];
    return AgentStep(
      mode: (j['mode'] as String?) ?? 'draft',
      questions: _list(j['otazky'], AgentQuestion.fromJson),
      document: _nonEmpty(j['dokument']),
      checklist: (j['checklist'] as List?)?.map((e) => '$e').toList() ?? [],
      warnings: (j['upozorneni'] as List?)?.map((e) => '$e').toList() ?? [],
      intake: stav is Map ? AgentIntake.fromJson(stav.cast()) : null,
      rejected: rejected,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode,
    if (questions.isNotEmpty)
      'otazky': questions.map((q) => q.toJson()).toList(),
    if (document != null) 'dokument': document,
    if (checklist.isNotEmpty) 'checklist': checklist,
    if (warnings.isNotEmpty) 'upozorneni': warnings,
    if (intake != null) 'stav': intake!.toJson(),
    if (rejected.isNotEmpty)
      'ulozene_odpovedi': {
        'odmitnuto': [
          for (final r in rejected) {'id': r.id, 'duvod': r.reason},
        ],
      },
  };

  /// Markdown the user copies or shares: the document, then the checklist
  /// and the warnings — the latter are part of the deliverable, a draft
  /// without them reads as finished legal advice.
  String get shareText {
    final b = StringBuffer(document ?? '');
    if (checklist.isNotEmpty) {
      b.write('\n\n## Kontrolní seznam\n\n');
      for (final c in checklist) {
        b.writeln('- [ ] $c');
      }
    }
    if (warnings.isNotEmpty) {
      b.write('\n## Upozornění\n\n');
      for (final w in warnings) {
        b.writeln('- $w');
      }
    }
    return b.toString().trimRight();
  }
}

String? _nonEmpty(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) => raw is List
    ? raw.whereType<Map>().map((m) => f(m.cast<String, dynamic>())).toList()
    : <T>[];
