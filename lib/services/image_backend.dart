import 'dart:convert';
import 'dart:typed_data';

import 'media_service.dart';

/// Stable ids for the two image backends the studio can target.
const kBackendDiffusers = 'diffusers';
const kBackendComfyUI = 'comfyui';

/// A single progress/result event from any image backend.
///
/// Backends differ wildly in how they report progress (the diffusers service
/// exposes a job model; ComfyUI streams over a websocket), so they're unified
/// behind this small event vocabulary that the Image Studio provider consumes.
sealed class GenEvent {
  const GenEvent();
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

  /// Best-effort cancel of the in-flight job (server-side where supported).
  Future<void> interrupt() async {}

  void dispose();
}

/// The existing diffusers/FLUX + Qwen-Image-Edit service behind llm.ol1n.com,
/// adapted to the unified [GenEvent] stream. Wraps [MediaService]'s
/// submit → poll → download job model.
class DiffusersBackend implements ImageBackend {
  DiffusersBackend([MediaService? media]) : _media = media ?? MediaService();

  final MediaService _media;

  @override
  String get id => kBackendDiffusers;

  @override
  String get label => 'Diffusers (FLUX)';

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    final jobId = await _media.submitGeneration(prompt: prompt, n: n);
    yield* _follow(jobId);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    final jobId = await _media.submitEdit(
      imageBase64: base64Encode(image),
      prompt: prompt,
      n: n,
    );
    yield* _follow(jobId);
  }

  Stream<GenEvent> _follow(String jobId) async* {
    await for (final s in _media.pollJob(jobId)) {
      switch (s) {
        case JobQueued(:final position):
          yield GenQueued(position);
        case JobRunning(:final step, :final total):
          yield GenRunning(step, total);
        case JobDone(:final resultUrl, :final count):
          final images = <Uint8List>[];
          for (var i = 0; i < count; i++) {
            yield GenDownloading(i, count);
            images.add(await _media.downloadResult(resultUrl, index: i));
          }
          yield GenComplete(images);
          return;
        case JobFailed(:final message):
          yield GenFailed(message);
          return;
        case JobExpired():
          yield const GenFailed('Výsledek vypršel – zkus znovu');
          return;
      }
    }
  }

  /// The diffusers job model has no server-side cancel; stopping consumption
  /// of the poll stream (done by the provider) is the best we can do.
  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _media.dispose();
}
