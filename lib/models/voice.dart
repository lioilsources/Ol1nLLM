import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'style_preset.dart' show foldDiacritics;

/// Voice an unassigned persona speaks with: the one Czech voice that runs on
/// CPU (so it is up whenever the audio service is) with a clean licence.
const kDefaultVoiceId = 'piper:cs_CZ-kasandra-medium';

/// Personas answer in Czech.
const kSpeechLanguage = 'cs';

/// Server limit on `text` (`TtsRequest.text`, AiStack `schemas.py`).
const kMaxSpeechChars = 5000;

/// Reference sample bounds for a cloned voice. The server needs 3 s of speech
/// *after* trimming silence and keeps at most 30 s (`voicestore.py`); 5 s
/// leaves room for the pause before the speaker starts.
const kMinVoiceSampleSeconds = 5;
const kMaxVoiceSampleSeconds = 30;

/// `rights` values the server accepts, with what the user is declaring.
const kVoiceRights = {
  'own': 'Je to můj hlas',
  'consented': 'Mluvčí s klonováním souhlasil',
  'licensed': 'Mám na nahrávku licenci',
  'synthetic': 'Syntetický hlas (ne skutečný člověk)',
};

/// How a model may be used, as the server's catalogue states it.
class VoiceModel {
  final String engine;
  final String model;
  final String license;

  /// `ok` | `attribution` | `noncommercial` | `unclear`.
  final String licenseStatus;
  final bool commercial;
  final String attribution;
  final bool watermark;
  final List<String> languages;

  const VoiceModel({
    required this.engine,
    required this.model,
    required this.license,
    required this.licenseStatus,
    required this.commercial,
    required this.attribution,
    required this.watermark,
    required this.languages,
  });

  String get licenseLabel => switch (licenseStatus) {
    'ok' => license,
    'attribution' => '$license · uvést autora',
    'noncommercial' => 'jen nekomerčně',
    _ => 'licence neověřená',
  };
}

/// One voice of `GET /v1/audio/voices`. The server lists a stored (cloned)
/// voice once per model that can clone it — same id, different engine — so
/// rows are merged by id and the models kept side by side.
class Voice {
  /// With the engine prefix, as `/v1/audio/tts` takes it: `piper:cs_CZ-…`,
  /// `kokoro:af_heart`, `custom:smug-cat`.
  final String id;

  /// `preset` (Kokoro, Piper) | `builtin` (GPU engine's own) | `custom`.
  final String type;
  final String language;
  final String gender;
  final String grade;
  final List<VoiceModel> models;

  const Voice({
    required this.id,
    required this.type,
    required this.language,
    required this.gender,
    required this.grade,
    required this.models,
  });

  bool get isCustom => type == 'custom';

  /// Id of the stored voice on the server (`/v1/audio/voices/{storedId}`).
  String get storedId => id.substring(id.indexOf(':') + 1);

  bool speaks(String language) =>
      models.any((m) => m.languages.contains(language));

  /// Models that can speak [language] with this voice. A clone has several
  /// and the server picks among them per request, so none is "the" licence.
  List<VoiceModel> modelsFor(String language) => [
    for (final m in models)
      if (m.languages.contains(language)) m,
  ];

  /// `af_heart` → Heart, `cs_CZ-kasandra-medium` → Kasandra (medium).
  String get label {
    final raw = storedId;
    if (type != 'preset') return raw;
    final piper = RegExp(
      r'^[a-z]{2}_[A-Z]{2}-(.+?)(?:-(\w+))?$',
    ).firstMatch(raw);
    if (piper != null) {
      final quality = piper.group(2);
      final name = _capitalize(piper.group(1)!);
      return quality == null ? name : '$name ($quality)';
    }
    final kokoro = RegExp(r'^[a-z]{2}_(.+)$').firstMatch(raw);
    return _capitalize(kokoro?.group(1) ?? raw);
  }

  String get genderLabel => switch (gender) {
    'f' => 'ženský',
    'm' => 'mužský',
    _ => '',
  };

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Merge the server's rows by id, keeping first-seen order.
  static List<Voice> fromRows(List<dynamic> rows) {
    final byId = <String, Voice>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      final model = VoiceModel(
        engine: row['engine'] as String,
        model: row['model'] as String,
        license: row['license'] as String,
        licenseStatus: row['license_status'] as String? ?? 'ok',
        commercial: row['commercial'] as bool? ?? false,
        attribution: row['attribution'] as String? ?? '',
        watermark: row['watermark'] as bool? ?? false,
        languages: (row['languages'] as List? ?? const []).cast<String>(),
      );
      final seen = byId[id];
      byId[id] = Voice(
        id: id,
        type: seen?.type ?? row['type'] as String,
        language: seen?.language ?? row['language'] as String? ?? '',
        gender: seen?.gender ?? row['gender'] as String? ?? '',
        grade: seen?.grade ?? row['grade'] as String? ?? '',
        models: [...?seen?.models, model],
      );
    }
    return byId.values.toList();
  }
}

/// A cloned voice's reference as the server stores it.
class StoredVoice {
  final String voiceId;
  final String name;
  final String language;
  final String rights;
  final String source;
  final double durationS;

  const StoredVoice({
    required this.voiceId,
    required this.name,
    required this.language,
    required this.rights,
    required this.source,
    required this.durationS,
  });

  factory StoredVoice.fromJson(Map<String, dynamic> j) => StoredVoice(
    voiceId: j['voice_id'] as String,
    name: j['name'] as String? ?? j['voice_id'] as String,
    language: j['language'] as String? ?? '',
    rights: j['rights'] as String? ?? '',
    source: j['source'] as String? ?? '',
    durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
  );
}

/// Server-side id for a voice called [name]: the server takes lower-case
/// ASCII, digits, `-` and `_`, 2–48 characters, starting with a letter or
/// digit. Null when nothing usable is left (a name of emoji only).
String? voiceIdFor(String name) {
  var id = foldDiacritics(name.trim())
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '-')
      .replaceAll(RegExp(r'^[-_]+|-+$'), '');
  if (id.length > 48) id = id.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  return id.length < 2 ? null : id;
}

/// Language to synthesise in: [preferred] when the voice speaks it, otherwise
/// the voice's own — an English Kokoro voice reading Czech text in English
/// phonemes is still better than a refused request.
String speechLanguage(Voice? voice, {String preferred = kSpeechLanguage}) {
  if (voice == null || voice.speaks(preferred)) return preferred;
  if (voice.language.isNotEmpty) return voice.language;
  return voice.models.firstOrNull?.languages.firstOrNull ?? preferred;
}

/// What a chat answer sounds like read aloud: markdown syntax, code, URLs and
/// table rules carry no speech, and a TTS engine would spell them out.
String speakableText(String markdown) {
  var s = markdown
      .replaceAll(RegExp(r'```.*?```', dotAll: true), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'https?://\S*[^\s.,;:!?)]'), ' ')
      // Tables: the rule row goes, outer borders go, inner ones are pauses.
      .replaceAll(RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*$', multiLine: true), ' ')
      .replaceAll(RegExp(r'^\s*\||\|\s*$', multiLine: true), '')
      .replaceAll(RegExp(r'\s*\|\s*'), ', ')
      // Headings, quotes and list bullets at line start.
      .replaceAll(RegExp(r'^\s*(#{1,6}|>|[-*+]|\d+\.)\s+', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`~#☐⚠️]'), '')
      // A line break ends a thought even without punctuation.
      .replaceAllMapped(
        RegExp(r'([^\s.!?:;,])[^\S\n]*\n+'),
        (m) => '${m.group(1)}. ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      // Punctuation left hanging where a link or symbol was removed.
      .replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m.group(1)!)
      .trim();
  if (s.length <= kMaxSpeechChars) return s;
  // Cut at the last sentence end that fits rather than mid-word.
  s = s.substring(0, kMaxSpeechChars);
  final end = s.lastIndexOf(RegExp(r'[.!?…]\s'));
  return end > kMaxSpeechChars ~/ 2 ? s.substring(0, end + 1) : s;
}

/// First piece of a spoken answer: short, so sound starts within seconds.
const kFirstSpeechChunkChars = 120;

/// Later pieces: long enough that the gaps between them are rare, short
/// enough that one lost request costs little.
const kSpeechChunkChars = 400;

/// [spoken] (already through [speakableText]) cut into pieces that are
/// synthesised one after another while the earlier ones play. A cloning
/// engine generates slightly slower than real time — a three-minute answer
/// takes over three minutes — so waiting for the whole file is not an option.
/// Cuts fall on sentence ends; a sentence longer than a piece is cut at a
/// comma or a space.
List<String> speechChunks(String spoken) {
  final chunks = <String>[];
  var current = '';
  int limit() => chunks.isEmpty ? kFirstSpeechChunkChars : kSpeechChunkChars;
  void flush() {
    if (current.isNotEmpty) chunks.add(current);
    current = '';
  }

  for (var sentence in spoken.trim().split(RegExp(r'(?<=[.!?…])\s+'))) {
    if (sentence.isEmpty) continue;
    if (current.isNotEmpty && current.length + 1 + sentence.length > limit()) {
      flush();
    }
    // A sentence that does not fit even alone.
    while (sentence.length > limit()) {
      final head = sentence.substring(0, limit());
      var cut = head.lastIndexOf(RegExp(r'[,;:]\s'));
      if (cut < limit() ~/ 2) cut = head.lastIndexOf(' ');
      if (cut <= 0) cut = limit() - 1;
      chunks.add(sentence.substring(0, cut + 1).trim());
      sentence = sentence.substring(cut + 1).trim();
    }
    if (sentence.isEmpty) continue;
    current = current.isEmpty ? sentence : '$current $sentence';
  }
  flush();
  return chunks;
}

const kMinBpm = 40;
const kMaxBpm = 220;
const kDefaultBpm = 90;

/// How the text is laid on the beat — the server's phrasing presets
/// (AiStack `app/tts/rhythm.py`, `STYLES`). The value's name is the id it
/// takes.
enum PhrasingStyle {
  spoken('Čtení', 'Klidné čtení s krátkou pauzou po každé frázi.'),
  news('Zprávy', 'Rovně a hustě, skoro bez pauz.'),
  slam('Slam', 'Pomalu, s dlouhým tichem po každé frázi.'),
  rap('Rap', 'Hustý text, krátké fráze, důrazný projev.'),
  preacher('Kazatel', 'Pomalu a přehnaně, s dlouhými pauzami.');

  const PhrasingStyle(this.label, this.description);

  final String label;
  final String description;
}

/// Speech on a grid: the server cuts the text into phrases and fits each to
/// its beats, so the reading keeps a tempo and a click or a beat can go under
/// it. It aligns where a phrase starts and how long it takes, not syllables —
/// this is rhythmic reading, not flow.
class SpeechRhythm {
  final int bpm;
  final PhrasingStyle style;

  /// Click under the voice, accented on the first beat of the bar.
  final bool beat;

  const SpeechRhythm({
    this.bpm = kDefaultBpm,
    this.style = PhrasingStyle.spoken,
    this.beat = false,
  });

  SpeechRhythm copyWith({int? bpm, PhrasingStyle? style, bool? beat}) =>
      SpeechRhythm(
        bpm: (bpm ?? this.bpm).clamp(kMinBpm, kMaxBpm),
        style: style ?? this.style,
        beat: beat ?? this.beat,
      );

  /// As `rhythm` of `POST /v1/audio/tts`, and as stored in Hive.
  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'style': style.name,
    'beat': beat,
  };

  factory SpeechRhythm.fromJson(Map<String, dynamic> j) => SpeechRhythm(
    bpm: ((j['bpm'] as num?)?.round() ?? kDefaultBpm).clamp(kMinBpm, kMaxBpm),
    // A style this build does not know (a newer server's) reads as plain.
    style: PhrasingStyle.values.asNameMap()[j['style']] ?? PhrasingStyle.spoken,
    beat: j['beat'] as bool? ?? false,
  );

  /// Distinguishes this rhythm from any other — in cache file names and in
  /// what counts as "the same reading".
  String get tag => '$bpm-${style.name}-${beat ? 'beat' : 'voice'}';

  String get label => '$bpm BPM · ${style.label}';
}

/// BPM from the moments a finger tapped: the mean interval of the last taps.
/// Null until there are two, and a pause over 2.5 s starts a new count —
/// that is someone coming back to the button, not a 24 BPM song.
int? tapTempo(List<DateTime> taps) {
  final run = <DateTime>[];
  for (final t in taps) {
    if (run.isNotEmpty &&
        t.difference(run.last) > const Duration(milliseconds: 2500)) {
      run.clear();
    }
    run.add(t);
  }
  if (run.length < 2) return null;
  final recent = run.length > 6 ? run.sublist(run.length - 6) : run;
  final ms =
      recent.last.difference(recent.first).inMilliseconds / (recent.length - 1);
  if (ms <= 0) return null;
  return (60000 / ms).round().clamp(kMinBpm, kMaxBpm);
}

/// Body of `POST /v1/audio/tts`.
///
/// `commercial_only` is false on purpose: the app is a private tool and the
/// only engines that clone a voice *in Czech* are XTTS-v2 (non-commercial)
/// and the community chatterbox-cs (licence unverified) — with the server's
/// default every cloned voice would answer 403 in the language the personas
/// speak. The voice list shows each model's licence instead.
Map<String, dynamic> speechRequest({
  required String text,
  required String voiceId,
  required String language,
  SpeechRhythm? rhythm,
}) => {
  'text': text,
  'language': language,
  'voice': voiceId,
  'commercial_only': false,
  'format': 'mp3',
  'rhythm': ?rhythm?.toJson(),
};

/// File name of the synthesised audio — the same text in the same voice is
/// synthesised once and replayed from disk.
///
/// The rhythm is part of the name: the same sentence at 90 BPM is another
/// recording, and without it the cache would answer with the plain one.
String speechFileName(
  String voiceId,
  String language,
  String text, [
  SpeechRhythm? rhythm,
]) {
  final key = [voiceId, language, ?rhythm?.tag, text].join('\n');
  return '${sha1.convert(utf8.encode(key))}.mp3';
}
