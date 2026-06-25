import 'dart:typed_data';

/// Stable ids for the image backends the studio supports.
const kBackendComfyUI = 'comfyui';
const kBackendFluxNim = 'flux_nim';

/// A single progress/result event from any image backend.
///
/// Backends differ wildly in how they report progress (the diffusers service
/// exposes a job model; ComfyUI streams over a websocket), so they're unified
/// behind this small event vocabulary that the Image Studio provider consumes.
sealed class GenEvent {
  const GenEvent();
}

/// The job has been accepted by the server and assigned an id. Emitted once,
/// before any progress, so callers can persist it and resume later (e.g. after
/// an app restart) via [ImageBackend.follow].
class GenSubmitted extends GenEvent {
  final String jobId;
  const GenSubmitted(this.jobId);
}

/// Job is waiting in the server queue. [position] is 0-based (0 = next up).
class GenQueued extends GenEvent {
  final int position;
  const GenQueued(this.position);
}

/// Job is generating. [total] == 0 means progress is indeterminate (the
/// backend can't report per-step granularity right now — e.g. ComfyUI polling
/// fallback), otherwise [step]/[total] is a 0..1 fraction.
class GenRunning extends GenEvent {
  final int step;
  final int total;
  const GenRunning(this.step, this.total);

  double? get fraction => total > 0 ? (step / total).clamp(0.0, 1.0) : null;
}

/// Generation finished; results are being downloaded. [done] of [total].
class GenDownloading extends GenEvent {
  final int done;
  final int total;
  const GenDownloading(this.done, this.total);

  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

/// Terminal success — decoded image bytes (raw PNG), one per variant.
class GenComplete extends GenEvent {
  final List<Uint8List> images;
  const GenComplete(this.images);
}

/// Terminal failure with a human-readable [message].
class GenFailed extends GenEvent {
  final String message;
  const GenFailed(this.message);
}

/// A pluggable image generation/editing backend.
///
/// Implementations turn a prompt (or an image + edit instruction) into a
/// stream of [GenEvent]s ending in exactly one [GenComplete] or [GenFailed].
abstract class ImageBackend {
  String get id;
  String get label;

  Stream<GenEvent> generate({required String prompt, required int n});

  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  });

  /// Re-attach to an already-submitted job (by the [GenSubmitted.jobId] a
  /// previous [generate]/[edit] emitted) and stream it to completion. Used to
  /// resume a job that outlived the app session.
  Stream<GenEvent> follow(String jobId);

  /// Best-effort cancel of the in-flight job (server-side where supported).
  Future<void> interrupt() async {}

  void dispose();
}
