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

  const VideoScene({
    required this.id,
    required this.label,
    required this.desc,
    required this.beats,
    required this.seconds,
    required this.minutesEst,
  });

  factory VideoScene.fromJson(Map<String, dynamic> json) => VideoScene(
        id: json['id'] as String,
        label: json['label'] as String,
        desc: json['desc'] as String? ?? '',
        beats: json['beats'] as int,
        seconds: (json['seconds'] as num).toDouble(),
        minutesEst: json['minutes_est'] as int,
      );
}
