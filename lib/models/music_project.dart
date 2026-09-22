import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// How a new track relates to the sample (AiStack `services/audio`, vibe):
/// [vibe] composes a new piece with the sample's sound and mood (text2music
/// with the sample as reference audio — the melody is not copied), [groove]
/// keeps the sample's rhythm and form and only changes its coat (cover).
enum MusicMode { vibe, groove }

/// Cover strength the server defaults to. Measured on SPARK: below 0.5 the
/// cover holds the sample's rhythm only sometimes (onset correlation
/// 0.05–0.51), from 0.5 reliably (0.28–0.69), and above it nothing improves.
const kDefaultCoverStrength = 0.5;
const kMinTrackSeconds = 10.0;
const kMaxTrackSeconds = 180.0;

/// Where the files of the *current* launch live. Persisted paths are relative
/// for the same reason as `GenImage.baseDir`: the iOS container prefix changes
/// on reinstall/restore.
class MusicFiles {
  static late String baseDir;
  static String path(String fileName) => '$baseDir/$fileName';
}

/// What the server heard in the sample: LM listening (ACE-Step) with tempo
/// double-checked by librosa. [source] says where each value came from
/// ("lm" / "librosa" / "default" / "none"), [warnings] why a value was
/// overruled — both are shown so the user knows which chip to distrust.
class SampleAnalysis {
  final String caption;
  final String genre;
  final int? bpm;
  final String keyscale;
  final String timesignature;
  final bool instrumental;
  final double durationS;
  final Map<String, String> source;
  final List<String> warnings;

  const SampleAnalysis({
    required this.caption,
    required this.genre,
    required this.bpm,
    required this.keyscale,
    required this.timesignature,
    required this.instrumental,
    required this.durationS,
    this.source = const {},
    this.warnings = const [],
  });

  factory SampleAnalysis.fromJson(Map<String, dynamic> j) => SampleAnalysis(
    caption: j['caption'] as String? ?? '',
    genre: j['genre'] as String? ?? '',
    bpm: (j['bpm'] as num?)?.round(),
    keyscale: j['keyscale'] as String? ?? '',
    timesignature: '${j['timesignature'] ?? ''}',
    instrumental: j['instrumental'] as bool? ?? true,
    durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
    source: {
      for (final e in ((j['source'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
    warnings: [for (final w in (j['warnings'] as List?) ?? const []) '$w'],
  );

  Map<String, dynamic> toJson() => {
    'caption': caption,
    'genre': genre,
    'bpm': bpm,
    'keyscale': keyscale,
    'timesignature': timesignature,
    'instrumental': instrumental,
    'duration_s': durationS,
    'source': source,
    'warnings': warnings,
  };
}

/// The settings the user is about to send. Seeded from the analysis, then
/// edited; each take keeps its own snapshot so „použít znovu" is exact.
class MusicDraft {
  final MusicMode mode;
  final String caption;
  final String hint;
  final int? bpm;
  final String keyscale;
  final String timesignature;

  /// Vibe only; null = the sample's length.
  final double? durationS;

  /// Groove only.
  final double coverStrength;

  /// Vibe only: let the 5 Hz LM lay out the structure first. Slower
  /// (~20 s instead of ~5 s per variant) and the same seed then gives a
  /// different piece every time — off by default.
  final bool lmPlan;
  final int variations;

  const MusicDraft({
    this.mode = MusicMode.vibe,
    this.caption = '',
    this.hint = '',
    this.bpm,
    this.keyscale = '',
    this.timesignature = '4',
    this.durationS,
    this.coverStrength = kDefaultCoverStrength,
    this.lmPlan = false,
    this.variations = 2,
  });

  factory MusicDraft.fromAnalysis(SampleAnalysis a) => MusicDraft(
    caption: a.caption,
    bpm: a.bpm,
    keyscale: a.keyscale,
    timesignature: a.timesignature.isEmpty ? '4' : a.timesignature,
  );

  MusicDraft copyWith({
    MusicMode? mode,
    String? caption,
    String? hint,
    int? bpm,
    String? keyscale,
    String? timesignature,
    double? durationS,
    bool clearDuration = false,
    double? coverStrength,
    bool? lmPlan,
    int? variations,
  }) => MusicDraft(
    mode: mode ?? this.mode,
    caption: caption ?? this.caption,
    hint: hint ?? this.hint,
    bpm: bpm ?? this.bpm,
    keyscale: keyscale ?? this.keyscale,
    timesignature: timesignature ?? this.timesignature,
    durationS: clearDuration ? null : (durationS ?? this.durationS),
    coverStrength: coverStrength ?? this.coverStrength,
    lmPlan: lmPlan ?? this.lmPlan,
    variations: variations ?? this.variations,
  );

  /// Body of `POST /v1/audio/vibe/generate`. Always instrumental: the server
  /// would otherwise sing the lyrics the LM transcribed from the sample, i.e.
  /// copy the original song's words.
  Map<String, dynamic> toRequest(String sampleId, {int? seed}) => {
    'sample_id': sampleId,
    'mode': mode.name,
    'caption': caption.trim(),
    'user_hint': hint.trim(),
    'bpm': ?bpm,
    if (keyscale.isNotEmpty) 'keyscale': keyscale,
    if (timesignature.isNotEmpty) 'timesignature': timesignature,
    if (mode == MusicMode.vibe && durationS != null) 'duration_s': durationS,
    if (mode == MusicMode.groove) 'cover_strength': coverStrength,
    if (mode == MusicMode.vibe) 'lm_plan': lmPlan,
    'variations': variations,
    'instrumental': true,
    'format': 'mp3',
    'seed': ?seed,
  };

  factory MusicDraft.fromJson(Map<String, dynamic> j) => MusicDraft(
    mode: j['mode'] == 'groove' ? MusicMode.groove : MusicMode.vibe,
    caption: j['caption'] as String? ?? '',
    hint: j['hint'] as String? ?? '',
    bpm: (j['bpm'] as num?)?.round(),
    keyscale: j['keyscale'] as String? ?? '',
    timesignature: j['timesignature'] as String? ?? '4',
    durationS: (j['durationS'] as num?)?.toDouble(),
    coverStrength:
        (j['coverStrength'] as num?)?.toDouble() ?? kDefaultCoverStrength,
    lmPlan: j['lmPlan'] as bool? ?? false,
    variations: (j['variations'] as num?)?.toInt() ?? 2,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'caption': caption,
    'hint': hint,
    'bpm': bpm,
    'keyscale': keyscale,
    'timesignature': timesignature,
    'durationS': durationS,
    'coverStrength': coverStrength,
    'lmPlan': lmPlan,
    'variations': variations,
  };
}

enum TakeStatus { queued, running, done, failed }

/// One finished variant, stored as a local mp3.
class MusicOutput {
  final String fileName;
  final int? seed;
  final double durationS;
  final double? lufs;

  const MusicOutput({
    required this.fileName,
    required this.seed,
    required this.durationS,
    this.lufs,
  });

  String get path => MusicFiles.path(fileName);

  factory MusicOutput.fromJson(Map<String, dynamic> j) => MusicOutput(
    fileName: j['fileName'] as String,
    seed: (j['seed'] as num?)?.toInt(),
    durationS: (j['durationS'] as num?)?.toDouble() ?? 0,
    lufs: (j['lufs'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'seed': seed,
    'durationS': durationS,
    'lufs': lufs,
  };
}

/// One generate round (one server job, 1–4 variants).
class MusicTake {
  final String id;

  /// Server job id; kept while running so a suspended app can re-attach.
  final String? jobId;
  final TakeStatus status;
  final MusicDraft draft;

  /// The caption the server actually used (draft + hint, cleaned).
  final String? finalCaption;
  final List<MusicOutput> outputs;
  final String? error;
  final DateTime createdAt;

  /// Transient progress, not persisted.
  final int? queuePosition;

  const MusicTake({
    required this.id,
    required this.status,
    required this.draft,
    required this.createdAt,
    this.jobId,
    this.finalCaption,
    this.outputs = const [],
    this.error,
    this.queuePosition,
  });

  factory MusicTake.start(MusicDraft draft) => MusicTake(
    id: _uuid.v4(),
    status: TakeStatus.queued,
    draft: draft,
    createdAt: DateTime.now(),
  );

  bool get inFlight =>
      status == TakeStatus.queued || status == TakeStatus.running;

  MusicTake copyWith({
    String? jobId,
    bool clearJobId = false,
    TakeStatus? status,
    String? finalCaption,
    List<MusicOutput>? outputs,
    String? error,
    bool clearError = false,
    int? queuePosition,
    bool clearQueuePosition = false,
  }) => MusicTake(
    id: id,
    jobId: clearJobId ? null : (jobId ?? this.jobId),
    status: status ?? this.status,
    draft: draft,
    finalCaption: finalCaption ?? this.finalCaption,
    outputs: outputs ?? this.outputs,
    error: clearError ? null : (error ?? this.error),
    createdAt: createdAt,
    queuePosition: clearQueuePosition
        ? null
        : (queuePosition ?? this.queuePosition),
  );

  factory MusicTake.fromJson(Map<String, dynamic> j) => MusicTake(
    id: j['id'] as String,
    jobId: j['jobId'] as String?,
    status: TakeStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => TakeStatus.failed,
    ),
    draft: MusicDraft.fromJson(j['draft'] as Map<String, dynamic>),
    finalCaption: j['finalCaption'] as String?,
    outputs: [
      for (final o in (j['outputs'] as List?) ?? const [])
        MusicOutput.fromJson(o as Map<String, dynamic>),
    ],
    error: j['error'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'status': status.name,
    'draft': draft.toJson(),
    'finalCaption': finalCaption,
    'outputs': [for (final o in outputs) o.toJson()],
    'error': error,
    'createdAt': createdAt.toIso8601String(),
  };
}

enum SampleStatus { uploading, analyzing, ready, failed }

/// One sample and everything composed from it.
class MusicProject {
  final String id;

  /// Original file name, for display.
  final String name;

  /// Local copy of the sample (relative, see [MusicFiles]) — playback, and
  /// re-upload when the server no longer has it.
  final String sampleFile;

  /// Server id (hash of the upload); null until uploaded.
  final String? sampleId;

  /// Length of the part the server uses (≤ 60 s) and of the whole file.
  final double? sampleDurationS;
  final double? sourceDurationS;
  final double? windowStartS;

  final SampleStatus status;
  final String? analyzeJobId;
  final SampleAnalysis? analysis;
  final String? error;
  final MusicDraft draft;

  /// Newest first.
  final List<MusicTake> takes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MusicProject({
    required this.id,
    required this.name,
    required this.sampleFile,
    required this.status,
    required this.draft,
    required this.createdAt,
    required this.updatedAt,
    this.sampleId,
    this.sampleDurationS,
    this.sourceDurationS,
    this.windowStartS,
    this.analyzeJobId,
    this.analysis,
    this.error,
    this.takes = const [],
  });

  factory MusicProject.create({
    required String name,
    required String sampleFile,
  }) {
    final now = DateTime.now();
    return MusicProject(
      id: _uuid.v4(),
      name: name,
      sampleFile: sampleFile,
      status: SampleStatus.uploading,
      draft: const MusicDraft(),
      createdAt: now,
      updatedAt: now,
    );
  }

  String get samplePath => MusicFiles.path(sampleFile);

  /// The track length a vibe round gets when the user leaves it alone.
  double get defaultDurationS => (sampleDurationS ?? analysis?.durationS ?? 30)
      .clamp(kMinTrackSeconds, kMaxTrackSeconds);

  MusicProject copyWith({
    String? sampleId,
    double? sampleDurationS,
    double? sourceDurationS,
    double? windowStartS,
    SampleStatus? status,
    String? analyzeJobId,
    bool clearAnalyzeJobId = false,
    SampleAnalysis? analysis,
    String? error,
    bool clearError = false,
    MusicDraft? draft,
    List<MusicTake>? takes,
    bool touch = true,
  }) => MusicProject(
    id: id,
    name: name,
    sampleFile: sampleFile,
    sampleId: sampleId ?? this.sampleId,
    sampleDurationS: sampleDurationS ?? this.sampleDurationS,
    sourceDurationS: sourceDurationS ?? this.sourceDurationS,
    windowStartS: windowStartS ?? this.windowStartS,
    status: status ?? this.status,
    analyzeJobId: clearAnalyzeJobId
        ? null
        : (analyzeJobId ?? this.analyzeJobId),
    analysis: analysis ?? this.analysis,
    error: clearError ? null : (error ?? this.error),
    draft: draft ?? this.draft,
    takes: takes ?? this.takes,
    createdAt: createdAt,
    updatedAt: touch ? DateTime.now() : updatedAt,
  );

  factory MusicProject.fromJson(Map<String, dynamic> j) => MusicProject(
    id: j['id'] as String,
    name: j['name'] as String,
    sampleFile: j['sampleFile'] as String,
    sampleId: j['sampleId'] as String?,
    sampleDurationS: (j['sampleDurationS'] as num?)?.toDouble(),
    sourceDurationS: (j['sourceDurationS'] as num?)?.toDouble(),
    windowStartS: (j['windowStartS'] as num?)?.toDouble(),
    status: SampleStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => SampleStatus.failed,
    ),
    analyzeJobId: j['analyzeJobId'] as String?,
    analysis: j['analysis'] == null
        ? null
        : SampleAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
    error: j['error'] as String?,
    draft: MusicDraft.fromJson(
      (j['draft'] as Map<String, dynamic>?) ?? const {},
    ),
    takes: [
      for (final t in (j['takes'] as List?) ?? const [])
        MusicTake.fromJson(t as Map<String, dynamic>),
    ],
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sampleFile': sampleFile,
    'sampleId': sampleId,
    'sampleDurationS': sampleDurationS,
    'sourceDurationS': sourceDurationS,
    'windowStartS': windowStartS,
    'status': status.name,
    'analyzeJobId': analyzeJobId,
    'analysis': analysis?.toJson(),
    'error': error,
    'draft': draft.toJson(),
    'takes': [for (final t in takes) t.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

// ── Display helpers ─────────────────────────────────────────────────────────

const kKeyNotes = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
];

/// Server time signatures are the beat count ("4"); 6 means 6/8.
const kTimeSignatures = ['2', '3', '4', '6'];

String timeSignatureLabel(String ts) => switch (ts) {
  '2' => '2/4',
  '3' => '3/4',
  '6' => '6/8',
  '' => '—',
  _ => '4/4',
};

/// „E major" → „E dur", „F# minor" → „F# moll" (the server's format stays in
/// the draft; this is only the chip label).
String keyLabel(String keyscale) {
  final parts = keyscale.trim().split(RegExp(r'\s+'));
  if (parts.length != 2) return keyscale.isEmpty ? '—' : keyscale;
  final mode = parts[1].toLowerCase() == 'minor' ? 'moll' : 'dur';
  return '${parts[0]} $mode';
}

String formatSeconds(double s) {
  final total = s.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
