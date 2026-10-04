import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';

/// Leads 📈 is served by different server code (LeadsRAG, `leadsd`) that
/// speaks the library's SSE dialect, so `LibraryChatService` parses it
/// unchanged. Two differences matter: the server sends `: planning` and
/// `: keepalive` comment lines while it works, and the sources describe firms
/// from Registr smluv — `work` is the IČO, `name_cs` the firm, `title`
/// `IČO … · segment`, `path` the contract id; the extra `url` and `channels`
/// keys are ignored by `LibrarySource`. `test/fixtures/leads_stream.sse` is a
/// verbatim capture from `leadsd` (`curl -N` on `/chat/stream`, question
/// „Které školy kupují tablety pro výuku?").
void main() {
  late List<String> lines;

  setUpAll(() {
    lines = File('test/fixtures/leads_stream.sse').readAsLinesSync();
  });

  test('keep-alive comments are ignored, not decoded', () {
    final comments = lines.where((l) => l.startsWith(':')).toList();
    expect(comments, contains(': planning'));
    expect(comments, contains(': keepalive'));
    for (final c in comments) {
      expect(LibraryChatService.parseSseLine(c), isNull, reason: c);
    }
  });

  test('replays end-to-end into deltas plus one terminal frame', () {
    var deltas = 0, done = 0;
    final answer = StringBuffer();
    var sources = <LibrarySource>[];
    String? sessionId, model;

    for (final line in lines) {
      final obj = LibraryChatService.parseSseLine(line);
      if (obj == null) continue;
      expect(obj['error'] ?? obj['detail'], isNull);

      final delta = obj['delta'];
      if (delta is String && delta.isNotEmpty) {
        deltas++;
        answer.write(delta);
        continue;
      }
      if (obj['done'] == true) {
        done++;
        sources = LibrarySource.listFrom(obj['sources']);
        sessionId = obj['session_id'] as String?;
        model = obj['model'] as String?;
      }
    }

    expect(done, 1, reason: 'exactly one terminal frame');
    expect(deltas, greaterThanOrEqualTo(1));
    expect(answer.toString(), contains('IČO'));
    expect(sessionId, isNotNull);
    expect(model, isNotEmpty);
    expect(sources, isNotEmpty);
    expect(lines.any((l) => l.contains('[DONE]')), isFalse);
  });

  test('a leads source maps firm, IČO and contract onto LibrarySource', () {
    final done = lines
        .map(LibraryChatService.parseSseLine)
        .firstWhere((o) => o?['done'] == true)!;
    final sources = LibrarySource.listFrom(done['sources']);

    expect(sources.first.nameCs, contains('škola'));
    for (final s in sources) {
      expect(s.work, matches(RegExp(r'^\d{8}$')), reason: 'IČO: ${s.work}');
      expect(s.title, startsWith('IČO '));
      expect(s.path, matches(RegExp(r'^\d+$')), reason: 'contract id');
      expect(s.lang, 'cs');
      expect(s.label, s.nameCs);
      expect(s.excerpt, isNotEmpty);
    }
  });
}
