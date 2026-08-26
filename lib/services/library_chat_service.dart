import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/library_source.dart';
import '../models/message.dart';
import 'chat_backend.dart';
import 'http_error.dart';

/// Library RAG chatbot (`WorldLibraryProject/rag/server.py`, SPARK :8090,
/// exposed as chat.ol1n.com behind CF Access). Retrieves from a ChromaDB
/// corpus of ~93 works and answers with citations.
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
  static const _baseUrl = String.fromEnvironment(
    'LIBRARY_CHAT_URL',
    defaultValue: 'https://chat.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  /// How many chunks the server puts into the prompt. Sent explicitly rather
  /// than relying on the server default, so a server-side change cannot
  /// silently alter what the app asks for. Raising it overflows the model's
  /// context — 5 chunks already build a 9–12k token prompt.
  static const _topK = 5;

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

  @override
  String get id => 'library';

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
      throw Exception('[knihovna] prázdný dotaz');
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
          'dotaz na knihovnu',
          'knihovna',
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
        step: 'dotaz na knihovnu',
        service: 'knihovna',
      );
      // A bare "502 bad gateway" is accurate but not actionable — the tunnel
      // stays up while the RAG server itself is down.
      final hint = const {502, 503, 504}.contains(response.statusCode)
          ? ' — knihovna neběží (na SPARKu: systemctl status library-chat)'
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
        debugPrint('[knihovna] SSE error event: $msg');
        throw Exception('[knihovna] $msg');
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
          '[knihovna] stream skončil bez odpovědi — model pravděpodobně '
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
      debugPrint('[knihovna] reset session failed (ignored): $e');
    }
  }

  @override
  void dispose() => _client.close();
}
