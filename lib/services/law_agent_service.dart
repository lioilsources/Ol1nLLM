import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/agent_step.dart';
import '../models/message.dart';
import 'chat_backend.dart';
import 'http_error.dart';

/// Právník's contract agent — `POST /agent/chat` on the same `law-chat`
/// server as [LibraryChatService.law] (WorldLibraryProject `rag/server.py`,
/// SPARK :8098, `https://pravnik.ol1n.com`). The model behind it is the
/// LiteLLM alias `pravnik-agent` (Gemma on demand, otherwise qwen36), which
/// runs **19:00–01:00 only**; outside that window the server answers 503 with
/// a sentence meant for the user, shown verbatim.
///
/// Unlike the RAG stream this is **one JSON object per step**: the agent runs
/// a tool-calling loop on the server (pick a template, ask, save answers,
/// render) for 5–60 s and returns structured data — question cards, intake
/// progress, the finished document. Nothing would be gained by streaming
/// tokens of a reply that is two sentences and a card. The step is emitted as
/// one [ChatDelta] (the agent's text) plus a [ChatDone] carrying
/// [ChatDone.agentStep].
///
/// Conversation history lives on the server in RAM per `session_id`, like the
/// RAG chat, and `POST /reset` drops it. The same id keys the drafted
/// document in Postgres (`lawyer_sessions`, 30-day retention), so answers
/// survive a server restart even though the chat memory does not.
///
/// Wire format (verified against qwen36 on SPARK, 2026-10-05 — see
/// `test/fixtures/law_agent_*.json`):
///
/// ```
/// → {"message": "...", "session_id": "...", "mode": "draft",
///    "odpovedi": [{"id": "najemne", "otazka": "...", "hodnota": "16 500"}]}
/// ← {"odpoved": "...", "session_id": "...", "otazky": [...], "dokument": null,
///    "checklist": [], "upozorneni": [], "stav": {...},
///    "ulozene_odpovedi": {"ulozeno": [...], "odmitnuto": [...]}, ...}
/// ```
class LawAgentService extends ChatBackend {
  /// Same host as the law RAG chat; the agent is a set of endpoints on it.
  static const _baseUrl = String.fromEnvironment(
    'LAW_CHAT_URL',
    defaultValue: 'https://pravnik.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  /// A whole agent step, not an idle gap: up to 8 tool calls, each a model
  /// round trip. Measured 3–20 s with qwen36; Gemma (~7 tok/s) is far slower,
  /// so leave room. LiteLLM gives up on a single call after 900 s anyway.
  static const _stepTimeout = Duration(minutes: 6);

  static const label = 'právník';
  static const unit = 'law-chat';

  final http.Client _client;

  LawAgentService({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get id => kChatBackendLawAgent;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_cfId.isNotEmpty && _cfSecret.isNotEmpty) ...{
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    },
  };

  /// Request body for the last user turn. Answers from a question card ride
  /// on the message ([Message.agentAnswers]); the server saves them into the
  /// intake itself, so the model cannot forget to.
  @visibleForTesting
  static Map<String, dynamic> requestBody(
    Message last, {
    String? remoteSessionId,
  }) => {
    'message': last.content.trim(),
    'session_id': ?remoteSessionId,
    // This persona exists to draft documents; skip the server's router call.
    'mode': 'draft',
    if (last.agentAnswers.isNotEmpty)
      'odpovedi': last.agentAnswers.map((a) => a.toJson()).toList(),
  };

  /// Text shown in the bubble. The model sometimes returns only a tool call
  /// result (cards, a document) with no prose; the bubble must not be empty.
  @visibleForTesting
  static String replyText(Map<String, dynamic> json, AgentStep step) {
    final text = (json['odpoved'] as String?)?.trim() ?? '';
    if (text.isNotEmpty) return text;
    if (step.hasDocument) return 'Dokument je hotový.';
    if (step.questions.isNotEmpty) return 'Doplň prosím:';
    return '…';
  }

  /// The user-facing message for a non-200 answer. 503 is the expected
  /// "model is not running" state and its `detail` is already a sentence for
  /// the user (server: `agent/klient.py`, `hlaska_modelu`), so it is shown
  /// as is — no layer prefix, no systemctl hint.
  @visibleForTesting
  static String errorText(
    int statusCode,
    String body,
    Map<String, String> headers,
  ) {
    if (statusCode == 503) {
      try {
        final detail = (jsonDecode(body) as Map)['detail'];
        if (detail is String && detail.isNotEmpty) return '[$label] $detail';
      } catch (_) {}
    }
    final err = HttpLayerError.parse(
      statusCode: statusCode,
      body: body,
      headers: headers,
      step: 'krok agenta',
      service: label,
    );
    final hint = const {502, 503, 504}.contains(statusCode)
        ? ' — $label neběží (na SPARKu: systemctl --user status $unit)'
        : statusCode == 501
        ? ' — na serveru chybí agent (law-chat bez --cite-registry nebo PG)'
        : '';
    return '$err$hint';
  }

  @override
  Stream<ChatEvent> chat(
    List<Message> thread, {
    String? systemPrompt,
    String? remoteSessionId,
  }) async* {
    if (thread.isEmpty || thread.last.content.trim().isEmpty) {
      throw Exception('[$label] prázdná zpráva');
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/agent/chat'),
            headers: _headers,
            body: jsonEncode(
              requestBody(thread.last, remoteSessionId: remoteSessionId),
            ),
          )
          .timeout(_stepTimeout);
    } catch (e) {
      throw Exception(
        HttpLayerError.fromException(
          e,
          'krok agenta',
          label,
          timeout: _stepTimeout,
        ).toString(),
      );
    }

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw Exception(errorText(response.statusCode, body, response.headers));
    }

    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw Exception('[$label] server vrátil nečitelnou odpověď');
    }
    final step = AgentStep.fromJson(json);
    yield ChatDelta(replyText(json, step));
    yield ChatDone(
      null,
      remoteSessionId: json['session_id'] as String?,
      model: json['model'] as String?,
      agentStep: step,
    );
  }

  /// Drops the agent's chat memory for [remoteSessionId]. The drafted
  /// document stays in Postgres until its retention runs out.
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
