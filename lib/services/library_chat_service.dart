import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/library_source.dart';
import '../models/message.dart';
import 'chat_backend.dart';
import 'http_error.dart';

/// RAG chatbot over a text corpus (`WorldLibraryProject/rag/server.py` on
/// SPARK, behind CF Access). Retrieves from a ChromaDB collection and answers
/// with citations. One class, two instances — the server code and wire
/// format are identical, only corpus, URL and prompt differ:
///
///  * [LibraryChatService.library] — chat.ol1n.com (:8090), ~93 works of
///    world philosophy and scripture.
///  * [LibraryChatService.law] — pravnik.ol1n.com (:8091), Czech statutes
///    from e-Sbírka; see `docs/plan-pravnik.md`.
///
/// Two things make it unlike [VllmService]:
///
///  * **Conversation memory lives on the server**, in RAM, keyed by
///    `session_id` (10 turns). The server ignores any history we send — it
///    reads only the `message` field — so we post the last user turn and echo
///    the session id back.
///  * **The SSE stream is not OpenAI-shaped.** Verified against the live
///    server:
///
///    ```
///    data: {"delta": "T"}
///    data: {"done": true, "sources": [...], "session_id": "...", "model": "translate"}
///    ```
///
///    No `[DONE]` sentinel, no `choices[]`, no `finish_reason`, and no
///    heartbeat comments.
class LibraryChatService extends ChatBackend {
  /// Host only — no trailing slash, no `/v1`. Point it at the SPARK LAN
  /// address (`http://192.168.88.66:8090`) to develop without the tunnel.
  static const _libraryUrl = String.fromEnvironment(
    'LIBRARY_CHAT_URL',
    defaultValue: 'https://chat.ol1n.com',
  );

  /// Law instance of the same server (`law-chat`; LAN
  /// `http://192.168.88.66:8091`).
  static const _lawUrl = String.fromEnvironment(
    'LAW_CHAT_URL',
    defaultValue: 'https://pravnik.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _connectTimeout = Duration(seconds: 30);

  /// Idle timeout *between* stream events. The largest real gap is between
  /// the response headers and the first token: embedding + Chroma lookup plus
  /// prefill of a 9–12k token prompt. A measured `top_k=2` question took 28 s
  /// end to end; `top_k=5` against the big model runs into minutes. Once
  /// decoding starts deltas arrive every few hundred ms, so five minutes of
  /// silence genuinely means dead — while vLLM's 120 s would abort healthy
  /// queries.
  static const _streamIdleTimeout = Duration(minutes: 5);

  final http.Client _client = http.Client();

  final String _baseUrl;
  final String _id;

  /// Czech name of the service as users see it in error messages
  /// (`[knihovna] …`, „knihovna neběží").
  final String label;

  /// systemd user unit on SPARK, named in the 502/503/504 hint.
  final String unit;

  /// How many chunks the server puts into the prompt. Sent explicitly rather
  /// than relying on the server default, so a server-side change cannot
  /// silently alter what the app asks for. Raising it overflows the model's
  /// context — 5 library chunks already build a 9–12k token prompt; statute
  /// paragraphs are shorter, so the law instance asks for 8.
  final int _topK;

  LibraryChatService._({
    required String baseUrl,
    required String id,
    required this.label,
    required this.unit,
    int topK = 5,
  }) : _baseUrl = baseUrl,
       _id = id,
       _topK = topK;

  /// World-library corpus at `LIBRARY_CHAT_URL`.
  factory LibraryChatService.library() => LibraryChatService._(
    baseUrl: _libraryUrl,
    id: kChatBackendLibrary,
    label: 'knihovna',
    unit: 'library-chat',
  );

  /// Czech statutes at `LAW_CHAT_URL`.
  factory LibraryChatService.law() => LibraryChatService._(
    baseUrl: _lawUrl,
    id: kChatBackendLaw,
    label: 'právník',
    unit: 'law-chat',
    topK: 8,
  );

  @override
  String get id => _id;

  /// What the request is, for `HttpLayerError` steps („timeout při …").
  /// Accusative, so it cannot be derived from [label].
  String get _step => switch (_id) {
    kChatBackendLaw => 'dotaz na právníka',
    _ => 'dotaz na knihovnu',
  };

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    // Unlike VllmService this must not hard-fail when the tokens are absent:
    // LAN development bypasses Cloudflare entirely.
    if (_cfId.isNotEmpty && _cfSecret.isNotEmpty) ...{
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    },
  };

  /// Decodes one SSE line into its JSON payload, or null for lines that carry
  /// none: blank frame separators, `:` heartbeat comments, non-`data:` fields
  /// and malformed JSON.
  @visibleForTesting
  static Map<String, dynamic>? parseSseLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return null;
    if (line.startsWith(':')) return null; // SSE comment / keep-alive ping
    if (!line.startsWith('data:')) return null;
    final payload = line.substring(5).trimLeft(); // tolerate a missing space
    if (payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Posts `thread.last` to `/chat/stream`.
  ///
  /// [systemPrompt] and every message before the last are **dropped** — the
  /// server builds its own prompt and keeps its own history. See
  /// [ChatBackend.chat].
  @override
  Stream<ChatEvent> chat(
    List<Message> thread, {
    String? systemPrompt,
    String? remoteSessionId,
  }) async* {
    final message = thread.isEmpty ? '' : thread.last.content.trim();
    if (message.isEmpty) {
      throw Exception('[$label] prázdný dotaz');
    }

    final request = http.Request('POST', Uri.parse('$_baseUrl/chat/stream'));
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'message': message,
      if (remoteSessionId != null) 'session_id': remoteSessionId,
      'top_k': _topK,
    });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_connectTimeout);
    } catch (e) {
      throw Exception(
        HttpLayerError.fromException(
          e,
          _step,
          label,
          timeout: _connectTimeout,
        ).toString(),
      );
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      final err = HttpLayerError.parse(
        statusCode: response.statusCode,
        body: body,
        headers: response.headers,
        step: _step,
        service: label,
      );
      // A bare "502 bad gateway" is accurate but not actionable — the tunnel
      // stays up while the RAG server itself is down.
      final hint = const {502, 503, 504}.contains(response.statusCode)
          ? ' — $label neběží (na SPARKu: systemctl status $unit)'
          : '';
      throw Exception('$err$hint');
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_streamIdleTimeout);

    var sawDone = false;
    var deltas = 0;

    await for (final line in lineStream) {
      final obj = parseSseLine(line);
      if (obj == null) continue;

      final error = obj['error'] ?? obj['detail'];
      if (error != null) {
        final msg = error is Map ? '${error['message'] ?? error}' : '$error';
        debugPrint('[$label] SSE error event: $msg');
        throw Exception('[$label] $msg');
      }

      final delta = obj['delta'];
      if (delta is String && delta.isNotEmpty) {
        deltas++;
        yield ChatDelta(delta);
        continue;
      }

      if (obj['done'] == true) {
        sawDone = true;
        yield ChatDone(
          null, // the server sends no finish_reason
          sources: LibrarySource.listFrom(obj['sources']),
          remoteSessionId: obj['session_id'] as String?,
          model: obj['model'] as String?,
        );
        return;
      }
    }

    if (!sawDone) {
      // The server raises inside its generator, *after* FastAPI has already
      // flushed 200 OK — so a failed LLM call has no HTTP status to parse.
      // An empty stream that just closes is the only signature it leaves.
      if (deltas == 0) {
        throw Exception(
          '[$label] stream skončil bez odpovědi — model pravděpodobně '
          'selhal. Ověř, že role „translate" na SPARKu běží.',
        );
      }
      // Partial answer: keep what arrived rather than throwing it away.
      yield const ChatDone(null);
    }
  }

  /// Drops the server-side history for [remoteSessionId]. Fire-and-forget:
  /// a failure here only leaves an orphaned deque that dies with the server.
  @override
  Future<void> resetSession(String remoteSessionId) async {
    try {
      await _client
          .post(
            Uri.parse('$_baseUrl/reset'),
            headers: _headers,
            body: jsonEncode({'session_id': remoteSessionId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[$label] reset session failed (ignored): $e');
    }
  }

  @override
  void dispose() => _client.close();
}
