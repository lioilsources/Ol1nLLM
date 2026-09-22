import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Where the files of the *current* launch live (cast images, finished
/// videos). Persisted paths are relative for the same reason as
/// `GenImage.baseDir`: the iOS container prefix changes on reinstall/restore.
class StoryFiles {
  static late String baseDir;
  static String path(String fileName) => '$baseDir/$fileName';
}

// ── Catalog (server, display only) ──────────────────────────────────────────

/// One character slot of a story. The server draws keyframes from the image
/// the user gives for [role]; [hasDefault] means it has its own picture for
/// the role (made with `story.py sheet/cast`), so sending one is optional.
class StoryRole {
  final String role;
  final String name;
  final String nameEn;

  /// English prompt description — what the server paints if the image is
  /// ambiguous. Shown only as a fallback for [look].
  final String desc;

  /// Czech description of the look, for the user choosing an image.
  final String look;
  final bool hero;
  final bool hasDefault;

  const StoryRole({
    required this.role,
    required this.name,
    required this.nameEn,
    required this.desc,
    required this.look,
    required this.hero,
    required this.hasDefault,
  });

  factory StoryRole.fromJson(Map<String, dynamic> j) => StoryRole(
    role: j['role'] as String,
    name: j['name'] as String? ?? j['role'] as String,
    nameEn: j['name_en'] as String? ?? '',
    desc: j['desc'] as String? ?? '',
    look: j['look'] as String? ?? '',
    hero: j['hero'] as bool? ?? false,
    hasDefault: j['default'] as bool? ?? false,
  );

  String get lookOrDesc => look.isNotEmpty ? look : desc;
}

/// One shot of the screenplay as the catalog describes it.
class StoryShotInfo {
  final String id;
  final List<String> chars;
  final String action;
  final String narration;
  final String narrationEn;

  /// Dance skeleton id (the shot moves along a Mixamo dance), or null.
  final String? control;

  /// Camera move (zoom_in, pan_left…), or null for a static camera.
  final String? camera;
  final int beats;

  const StoryShotInfo({
    required this.id,
    required this.chars,
    required this.action,
    required this.narration,
    required this.narrationEn,
    this.control,
    this.camera,
    this.beats = 1,
  });

  factory StoryShotInfo.fromJson(Map<String, dynamic> j) => StoryShotInfo(
    id: j['id'] as String,
    chars: [for (final c in (j['chars'] as List?) ?? const []) '$c'],
    action: j['action'] as String? ?? '',
    narration: j['narration'] as String? ?? '',
    narrationEn: j['narration_en'] as String? ?? '',
    control: j['control'] as String?,
    camera: j['camera'] as String?,
    beats: (j['beats'] as num?)?.toInt() ?? 1,
  );

  String narrationFor(String lang) =>
      lang == 'en' && narrationEn.isNotEmpty ? narrationEn : narration;
}

/// A story from the server catalog (`video-stack/stories/*.json`). Prompts
/// and screenplays are tuned on the server without an app release — the same
/// idea as the „Rozhýbat" scenes.
class StoryInfo {
  final String id;
  final String title;
  final String titleEn;
  final String desc;
  final String descEn;
  final String setting;
  final int shots;
  final int beats;
  final double seconds;

  /// Server's GPU-time estimate (keyframes + animation + sound), queue not
  /// included.
  final int minutesEst;
  final int minutesEstHd;
  final List<String> languages;
  final List<StoryRole> characters;
  final List<StoryShotInfo> script;

  const StoryInfo({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.desc,
    required this.descEn,
    required this.setting,
    required this.shots,
    required this.beats,
    required this.seconds,
    required this.minutesEst,
    required this.minutesEstHd,
    required this.languages,
    required this.characters,
    required this.script,
  });

  factory StoryInfo.fromJson(Map<String, dynamic> j) => StoryInfo(
    id: j['id'] as String,
    title: j['title'] as String? ?? j['id'] as String,
    titleEn: j['title_en'] as String? ?? '',
    desc: j['desc'] as String? ?? '',
    descEn: j['desc_en'] as String? ?? '',
    setting: j['setting'] as String? ?? '',
    shots: (j['shots'] as num?)?.toInt() ?? 0,
    beats: (j['beats'] as num?)?.toInt() ?? 0,
    seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
    minutesEst: (j['minutes_est'] as num?)?.toInt() ?? 0,
    minutesEstHd:
        (j['minutes_est_hd'] as num?)?.toInt() ??
        (j['minutes_est'] as num?)?.toInt() ??
        0,
    languages: [
      for (final l in (j['languages'] as List?) ?? const ['cs']) '$l',
    ],
    characters: [
      for (final c in (j['characters'] as List?) ?? const [])
        StoryRole.fromJson(c as Map<String, dynamic>),
    ],
    script: [
      for (final s in (j['script'] as List?) ?? const [])
        StoryShotInfo.fromJson(s as Map<String, dynamic>),
    ],
  );

  StoryRole? role(String role) {
    for (final c in characters) {
      if (c.role == role) return c;
    }
    return null;
  }
}

// ── Server job ──────────────────────────────────────────────────────────────

/// `GET /v1/video/jobs/<id>` for a story job.
class StoryJobView {
  final String id;

  /// queued | running | review | done | error
  final String status;

  /// keyframes (up to review) | redo (repainting chosen shots) | all
  final String? stage;

  /// Server phase: keyframes, review, compile, render, assemble, rife, voice,
  /// music, mix.
  final String? phase;
  final int keyframe;
  final int keyframes;
  final int beat;
  final int beats;
  final String? error;

  /// Index in the server queue, 0 = next.
  final int? position;

  const StoryJobView({
    required this.id,
    required this.status,
    this.stage,
    this.phase,
    this.keyframe = 0,
    this.keyframes = 0,
    this.beat = 0,
    this.beats = 0,
    this.error,
    this.position,
  });

  factory StoryJobView.fromJson(Map<String, dynamic> j) => StoryJobView(
    id: j['id'] as String,
    status: j['status'] as String? ?? 'error',
    stage: j['stage'] as String?,
    phase: j['phase'] as String?,
    keyframe: (j['keyframe'] as num?)?.toInt() ?? 0,
    keyframes: (j['keyframes'] as num?)?.toInt() ?? 0,
    beat: (j['beat'] as num?)?.toInt() ?? 0,
    beats: (j['beats'] as num?)?.toInt() ?? 0,
    error: j['error'] as String?,
    position: (j['position'] as num?)?.toInt(),
  );
}

/// One keyframe waiting for review (`GET …/keyframes`).
class StoryKeyframe {
  final String id;
  final List<String> chars;

  /// English description the keyframe was painted from — the text the user
  /// edits to repaint a shot differently.
  final String keyframe;
  final String action;
  final String narration;
  final String narrationEn;
  final String? control;
  final String? camera;
  final bool ready;

  const StoryKeyframe({
    required this.id,
    required this.chars,
    required this.keyframe,
    required this.action,
    required this.narration,
    required this.narrationEn,
    required this.ready,
    this.control,
    this.camera,
  });

  factory StoryKeyframe.fromJson(Map<String, dynamic> j) => StoryKeyframe(
    id: j['id'] as String,
    chars: [for (final c in (j['chars'] as List?) ?? const []) '$c'],
    keyframe: j['keyframe'] as String? ?? '',
    action: j['action'] as String? ?? '',
    narration: j['narration'] as String? ?? '',
    narrationEn: j['narration_en'] as String? ?? '',
    control: j['control'] as String?,
    camera: j['camera'] as String?,
    ready: j['ready'] as bool? ?? false,
  );

  String narrationFor(String lang) =>
      lang == 'en' && narrationEn.isNotEmpty ? narrationEn : narration;
}

// ── Local project ───────────────────────────────────────────────────────────

enum StoryStatus { submitting, queued, running, review, done, failed }

/// Who plays a role: a picked image copied into the studio's storage, or the
/// server's own picture for the role ([fileName] null).
class StoryCast {
  final String name;
  final String? fileName;

  const StoryCast({required this.name, this.fileName});

  bool get usesDefault => fileName == null;
  String? get path => fileName == null ? null : StoryFiles.path(fileName!);

  factory StoryCast.fromJson(Map<String, dynamic> j) =>
      StoryCast(name: j['name'] as String? ?? '', fileName: j['file'] as String?);

  Map<String, dynamic> toJson() => {'name': name, 'file': fileName};
}

/// One story render: one server job from cast to finished video.
class StoryProject {
  final String id;
  final String storyId;
  final String title;
  final String lang;
  final bool review;
  final bool hd;
  final int seed;

  /// role → who plays it, in the story's order (hero first).
  final Map<String, StoryCast> cast;

  /// Server job id; kept for the whole life of the project (review and
  /// variant downloads need it after the render too).
  final String? jobId;
  final StoryStatus status;
  final String? stage;
  final String? phase;
  final int keyframe;
  final int keyframes;
  final int beat;
  final int beats;
  final int? position;

  /// Bumped on every repaint so keyframe images are fetched anew.
  final int keyframesVersion;
  final int minutesEst;
  final double seconds;

  /// The finished video (with narration and music), relative.
  final String? videoFile;

  /// Downloaded on demand: `sub` (burned-in subtitles), `16x9`.
  final Map<String, String> variantFiles;
  final String? error;

  /// The job failed on the server — „Zkusit znovu" starts a new one. Otherwise
  /// (network, download) it re-attaches to the existing job.
  final bool serverFailed;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StoryProject({
    required this.id,
    required this.storyId,
    required this.title,
    required this.lang,
    required this.review,
    required this.hd,
    required this.seed,
    required this.cast,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.jobId,
    this.stage,
    this.phase,
    this.keyframe = 0,
    this.keyframes = 0,
    this.beat = 0,
    this.beats = 0,
    this.position,
    this.keyframesVersion = 0,
    this.minutesEst = 0,
    this.seconds = 0,
    this.videoFile,
    this.variantFiles = const {},
    this.error,
    this.serverFailed = false,
  });

  factory StoryProject.create({
    required StoryInfo story,
    required Map<String, StoryCast> cast,
    required String lang,
    required bool review,
    required bool hd,
    required int seed,
  }) {
    final now = DateTime.now();
    return StoryProject(
      id: _uuid.v4(),
      storyId: story.id,
      title: story.title,
      lang: lang,
      review: review,
      hd: hd,
      seed: seed,
      cast: cast,
      status: StoryStatus.submitting,
      keyframes: story.shots,
      beats: story.beats,
      minutesEst: hd ? story.minutesEstHd : story.minutesEst,
      seconds: story.seconds,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get inFlight =>
      status == StoryStatus.submitting ||
      status == StoryStatus.queued ||
      status == StoryStatus.running;

  String? get videoPath => videoFile == null ? null : StoryFiles.path(videoFile!);

  StoryProject copyWith({
    String? jobId,
    StoryStatus? status,
    String? stage,
    String? phase,
    bool clearPhase = false,
    int? keyframe,
    int? keyframes,
    int? beat,
    int? beats,
    int? position,
    bool clearPosition = false,
    int? keyframesVersion,
    int? minutesEst,
    double? seconds,
    String? videoFile,
    Map<String, String>? variantFiles,
    String? error,
    bool clearError = false,
    bool? serverFailed,
    bool touch = true,
  }) => StoryProject(
    id: id,
    storyId: storyId,
    title: title,
    lang: lang,
    review: review,
    hd: hd,
    seed: seed,
    cast: cast,
    jobId: jobId ?? this.jobId,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    phase: clearPhase ? null : (phase ?? this.phase),
    keyframe: keyframe ?? this.keyframe,
    keyframes: keyframes ?? this.keyframes,
    beat: beat ?? this.beat,
    beats: beats ?? this.beats,
    position: clearPosition ? null : (position ?? this.position),
    keyframesVersion: keyframesVersion ?? this.keyframesVersion,
    minutesEst: minutesEst ?? this.minutesEst,
    seconds: seconds ?? this.seconds,
    videoFile: videoFile ?? this.videoFile,
    variantFiles: variantFiles ?? this.variantFiles,
    error: clearError ? null : (error ?? this.error),
    serverFailed: serverFailed ?? this.serverFailed,
    createdAt: createdAt,
    updatedAt: touch ? DateTime.now() : updatedAt,
  );

  factory StoryProject.fromJson(Map<String, dynamic> j) => StoryProject(
    id: j['id'] as String,
    storyId: j['storyId'] as String,
    title: j['title'] as String? ?? j['storyId'] as String,
    lang: j['lang'] as String? ?? 'cs',
    review: j['review'] as bool? ?? false,
    hd: j['hd'] as bool? ?? false,
    seed: (j['seed'] as num?)?.toInt() ?? 0,
    cast: {
      for (final e in ((j['cast'] as Map?) ?? const {}).entries)
        '${e.key}': StoryCast.fromJson(e.value as Map<String, dynamic>),
    },
    jobId: j['jobId'] as String?,
    status: StoryStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => StoryStatus.failed,
    ),
    stage: j['stage'] as String?,
    phase: j['phase'] as String?,
    keyframe: (j['keyframe'] as num?)?.toInt() ?? 0,
    keyframes: (j['keyframes'] as num?)?.toInt() ?? 0,
    beat: (j['beat'] as num?)?.toInt() ?? 0,
    beats: (j['beats'] as num?)?.toInt() ?? 0,
    keyframesVersion: (j['keyframesVersion'] as num?)?.toInt() ?? 0,
    minutesEst: (j['minutesEst'] as num?)?.toInt() ?? 0,
    seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
    videoFile: j['videoFile'] as String?,
    variantFiles: {
      for (final e in ((j['variantFiles'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
    error: j['error'] as String?,
    serverFailed: j['serverFailed'] as bool? ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'storyId': storyId,
    'title': title,
    'lang': lang,
    'review': review,
    'hd': hd,
    'seed': seed,
    'cast': {for (final e in cast.entries) e.key: e.value.toJson()},
    'jobId': jobId,
    'status': status.name,
    'stage': stage,
    'phase': phase,
    'keyframe': keyframe,
    'keyframes': keyframes,
    'beat': beat,
    'beats': beats,
    'keyframesVersion': keyframesVersion,
    'minutesEst': minutesEst,
    'seconds': seconds,
    'videoFile': videoFile,
    'variantFiles': variantFiles,
    'error': error,
    'serverFailed': serverFailed,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

// ── Display helpers ─────────────────────────────────────────────────────────

/// What the server is doing right now, in words.
String storyProgressLabel(StoryProject p) {
  if (p.status == StoryStatus.submitting) return 'Odesílám postavy…';
  if (p.status == StoryStatus.queued) {
    final pos = p.position;
    return pos != null && pos > 0 ? 'Ve frontě (${pos + 1}.)' : 'Čeká na GPU…';
  }
  final redo = p.stage == 'redo';
  return switch (p.phase) {
    'keyframes' || null when redo =>
      'Překresluji záběry ${p.keyframe}/${p.keyframes}',
    'keyframes' => 'Kreslím záběry ${p.keyframe}/${p.keyframes}',
    'review' => 'Dokončuji záběry…',
    'compile' => 'Připravuji animaci…',
    'render' =>
      p.beat > 0 ? 'Animuji ${p.beat}/${p.beats}' : 'Animuji první záběr…',
    'assemble' => 'Stříhám záběry dohromady…',
    'rife' => 'Vyhlazuji pohyb…',
    'voice' => 'Namlouvám vypravěče…',
    'music' => 'Skládám hudbu…',
    'mix' => 'Míchám zvuk a titulky…',
    _ => 'Startuji…',
  };
}

/// Rough share of the whole job that is done, for the progress bar; null
/// while waiting (indeterminate bar). Animation dominates the GPU time, so it
/// gets most of the bar.
double? storyProgressFraction(StoryProject p) {
  if (p.status != StoryStatus.running) return null;
  double part(int done, int total) =>
      total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
  if (p.stage == 'keyframes' || p.stage == 'redo') {
    return part(p.keyframe, p.keyframes);
  }
  return switch (p.phase) {
    'keyframes' => 0.1 * part(p.keyframe, p.keyframes),
    'review' || 'compile' => 0.1,
    'render' => 0.1 + 0.75 * part(p.beat, p.beats),
    'assemble' => 0.86,
    'rife' => 0.88,
    'voice' => 0.92,
    'music' => 0.95,
    'mix' => 0.98,
    _ => null,
  };
}

const kStoryLanguages = {'cs': 'Česky', 'en': 'English'};

/// Dance skeleton id → what the user sees.
String danceLabel(String control) => switch (control) {
  'chicken_dance' => 'kuřecí tanec',
  'macarena' => 'makarena',
  'samba' => 'samba',
  'salsa' => 'salsa',
  'rumba' => 'rumba',
  'robot' => 'robot',
  'moonwalk' => 'moonwalk',
  'maraschino_step' => 'taneční kroky',
  'snake_hip_hop' => 'hip hop',
  _ => control.replaceAll('_', ' '),
};

String cameraLabel(String camera) => switch (camera) {
  'zoom_in' => 'přiblížení',
  'zoom_out' => 'oddálení',
  'pan_left' => 'švenk doleva',
  'pan_right' => 'švenk doprava',
  'pan_up' => 'švenk nahoru',
  'pan_down' => 'švenk dolů',
  _ => camera.replaceAll('_', ' '),
};

String formatStorySeconds(double s) {
  final total = s.round();
  return total < 60
      ? '$total s'
      : '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')} min';
}
