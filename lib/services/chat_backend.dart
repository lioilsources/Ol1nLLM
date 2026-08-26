import '../models/library_source.dart';
import '../models/message.dart';

/// Backend id carried by a persona (`Persona.backend`). `null` means the
/// default vLLM chat; ids here must stay stable, they are matched against
/// `assets/personas/index.json`.
const kChatBackendLibrary = 'library';

sealed class ChatEvent {
  const ChatEvent();
}

class ChatDelta extends ChatEvent {
  final String content;
  const ChatDelta(this.content);
}

class ChatDone extends ChatEvent {
  /// e.g. 'stop', 'length', 'content_filter', or null if server didn't send one.
  ///
  /// The library backend never sends one — its SSE stream carries no
  /// `finish_reason` (verified against the live server) — so an answer clipped
  /// at the server's `max_tokens` is indistinguishable from a complete one and
  /// [truncatedByLength] stays false. A server-side gap, not something the
  /// client can infer.
  final String? finishReason;

  /// Chunks the RAG answer was built from. Empty for stateless backends.
  final List<LibrarySource> sources;

  /// Server-side conversation id to echo back on the next turn. Only the
  /// library backend keeps history server-side; null elsewhere.
  final String? remoteSessionId;

  /// Model that actually answered, as reported by the server.
  final String? model;

  const ChatDone(
    this.finishReason, {
    this.sources = const [],
    this.remoteSessionId,
    this.model,
  });

  bool get truncatedByLength => finishReason == 'length';
}

/// A chat transport. Implementations differ in what they can actually use of
/// the arguments below — the doc on [chat] spells that out rather than
/// pretending the two backends are interchangeable.
abstract class ChatBackend {
  /// Stable id, used in debug output only.
  String get id;

  /// Streams the assistant's reply to the last message on [thread].
  ///
  /// [thread] is the active branch root→leaf, including the new user turn.
  ///
  /// `VllmService` sends the **whole thread** plus [systemPrompt] (the
  /// endpoint is stateless) and ignores [remoteSessionId].
  ///
  /// `LibraryChatService` sends **only `thread.last.content`** plus
  /// [remoteSessionId]. The RAG server keeps its own per-session history and
  /// builds its own system prompt from `prompts/librarian_cs.md` + the work
  /// catalog, so [systemPrompt] and every earlier message are **dropped, not
  /// merged**. Passing a persona prompt there has no effect.
  Stream<ChatEvent> chat(
    List<Message> thread, {
    String? systemPrompt,
    String? remoteSessionId,
  });

  /// Best-effort drop of server-side history for [remoteSessionId].
  /// No-op for stateless backends. Never throws — callers fire and forget.
  Future<void> resetSession(String remoteSessionId) async {}

  void dispose();
}
