/// One server-defined animation preset for the „Rozhýbat" round.
///
/// The catalog lives on the video server (`video-stack/scenes/*.json`) so
/// prompts can be tuned without an app release — mirrors how LoRAs and
/// checkpoints are fetched rather than hard-coded. Only [id] is persisted on
/// the node; label/desc are display-only.
class VideoScene {
  final String id;
  final String label;
  final String desc;

  /// Number of 5 s segments (beats) the scene renders.
  final int beats;

  /// Clip length in seconds.
  final double seconds;

  /// Server's GPU-time estimate in minutes (queue not included).
  final int minutesEst;

  /// Whether the clip comes back with a generated soundtrack. Older servers
  /// omit the field, so the default is silent — the behaviour until now.
  final bool audio;

  const VideoScene({
    required this.id,
    required this.label,
    required this.desc,
    required this.beats,
    required this.seconds,
    required this.minutesEst,
    this.audio = false,
  });

  factory VideoScene.fromJson(Map<String, dynamic> json) => VideoScene(
        id: json['id'] as String,
        label: json['label'] as String,
        desc: json['desc'] as String? ?? '',
        beats: json['beats'] as int,
        seconds: (json['seconds'] as num).toDouble(),
        minutesEst: json['minutes_est'] as int,
        audio: json['audio'] as bool? ?? false,
      );
}

/// What the video server allows for „Rozhýbat promptem" — animating the image
/// with the user's own motion description instead of a scene. Absent on
/// servers that predate it (the option then stays hidden).
class VideoCustomSpec {
  /// Longest clip in 5 s segments.
  final int maxBeats;
  final int maxPrompt;
  final double secondsPerBeat;
  final int minutesPerBeat;

  const VideoCustomSpec({
    this.maxBeats = 3,
    this.maxPrompt = 500,
    this.secondsPerBeat = 5,
    this.minutesPerBeat = 3,
  });

  factory VideoCustomSpec.fromJson(Map<String, dynamic> json) =>
      VideoCustomSpec(
        maxBeats: (json['max_beats'] as num?)?.toInt() ?? 1,
        maxPrompt: (json['max_prompt'] as num?)?.toInt() ?? 500,
        secondsPerBeat: (json['seconds_per_beat'] as num?)?.toDouble() ?? 5,
        minutesPerBeat: (json['minutes_per_beat'] as num?)?.toInt() ?? 3,
      );
}

/// `GET /v1/video/scenes`: the presets and, on newer servers, the custom
/// prompt limits.
class VideoCatalog {
  final List<VideoScene> scenes;
  final VideoCustomSpec? custom;

  const VideoCatalog({required this.scenes, this.custom});
}
