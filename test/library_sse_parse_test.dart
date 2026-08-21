import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';

/// The library RAG server speaks its own SSE dialect (`rag/server.py:
/// chat_stream`), not the OpenAI one VllmService parses:
///
///   data: {"delta": "..."}                      ← per token
///   data: {"done": true, sources, session_id, model}   ← terminator
///
/// No `[DONE]` sentinel, no `choices[]`, no `finish_reason`. These tests pin
/// that shape plus the noise a real stream carries.
void main() {
  group('parseSseLine', () {
    test('decodes a delta frame', () {
      final obj = LibraryChatService.parseSseLine('data: {"delta": "Tao"}');
      expect(obj, isNotNull);
      expect(obj!['delta'], 'Tao');
    });

    test('decodes the terminal done frame with sources', () {
      const line =
          'data: {"done": true, "session_id": "abc-123", "model": "translate", '
          '"sources": [{"work": "Tao te ťing", "group": "chinese", '
          '"lang": "zh", "distance": 0.34, "excerpt": "úryvek"}]}';
      final obj = LibraryChatService.parseSseLine(line);
      expect(obj, isNotNull);
      expect(obj!['done'], isTrue);
      expect(obj['session_id'], 'abc-123');
      expect(obj['model'], 'translate');

      final sources = LibrarySource.listFrom(obj['sources']);
      expect(sources, hasLength(1));
      expect(sources.first.work, 'Tao te ťing');
      expect(sources.first.group, 'chinese');
      expect(sources.first.distance, closeTo(0.34, 1e-9));
      expect(sources.first.excerpt, 'úryvek');
    });

    test('tolerates a missing space after data:', () {
      final obj = LibraryChatService.parseSseLine('data:{"delta":"x"}');
      expect(obj?['delta'], 'x');
    });

    test('skips blank frame separators', () {
      expect(LibraryChatService.parseSseLine(''), isNull);
      expect(LibraryChatService.parseSseLine('   '), isNull);
    });

    test('skips SSE comments (heartbeat pings)', () {
      expect(LibraryChatService.parseSseLine(': ping'), isNull);
      expect(LibraryChatService.parseSseLine(':'), isNull);
    });

    test('skips non-data fields', () {
      expect(LibraryChatService.parseSseLine('event: message'), isNull);
      expect(LibraryChatService.parseSseLine('id: 7'), isNull);
    });

    test('returns null on malformed JSON instead of throwing', () {
      expect(LibraryChatService.parseSseLine('data: {oops'), isNull);
      expect(LibraryChatService.parseSseLine('data: [1,2]'), isNull); // not a map
    });

    test('surfaces an error frame as a decodable map', () {
      final obj = LibraryChatService.parseSseLine('data: {"error": "boom"}');
      expect(obj?['error'], 'boom');
    });

    test('does not mistake [DONE] for a terminator — the server sends none', () {
      // If the server ever grew an OpenAI-style sentinel, this line would be
      // ignored rather than silently ending the stream.
      expect(LibraryChatService.parseSseLine('data: [DONE]'), isNull);
    });
  });

  group('LibrarySource', () {
    test('survives sparse metadata from older ingests', () {
      final sources = LibrarySource.listFrom([
        {'work': 'Mahábhárata', 'excerpt': 'text'},
      ]);
      expect(sources, hasLength(1));
      expect(sources.first.title, isNull);
      expect(sources.first.distance, isNull);
      expect(sources.first.subtitle, '');
      expect(sources.first.label, 'Mahábhárata'); // falls back to work
    });

    test('label prefers a title that adds information', () {
      const s = LibrarySource(work: 'tao', title: 'Tao te ťing', excerpt: '');
      expect(s.label, 'Tao te ťing');
    });

    test('listFrom ignores junk rather than making a chat unloadable', () {
      expect(LibrarySource.listFrom(null), isEmpty);
      expect(LibrarySource.listFrom('nope'), isEmpty);
      expect(LibrarySource.listFrom([1, 'x']), isEmpty);
    });

    test('round-trips through JSON', () {
      const s = LibrarySource(
        work: 'Zhuangzi',
        group: 'chinese',
        lang: 'zh',
        path: 'downloads/zhuangzi.txt',
        distance: 0.41,
        excerpt: 'úryvek',
      );
      final back = LibrarySource.fromJson(s.toJson());
      expect(back.work, s.work);
      expect(back.group, s.group);
      expect(back.path, s.path);
      expect(back.distance, s.distance);
      expect(back.excerpt, s.excerpt);
    });
  });
}
