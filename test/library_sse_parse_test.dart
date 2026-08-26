import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';

/// The library RAG server speaks its own SSE dialect (`rag/server.py:
/// chat_stream`), not the OpenAI one VllmService parses:
///
///   data: {"delta": "..."}                             per token
///   data: {"done": true, sources, session_id, model}   terminator
///
/// No `[DONE]` sentinel, no `choices[]`, no `finish_reason`, no heartbeats.
/// `test/fixtures/library_stream.sse` holds frames captured verbatim from the
/// live server through the Cloudflare tunnel, so this pins the real wire
/// format rather than an assumption about it.
void main() {
  group('parseSseLine', () {
    test('decodes a delta frame', () {
      final obj = LibraryChatService.parseSseLine('data: {"delta": "Tao"}');
      expect(obj, isNotNull);
      expect(obj!['delta'], 'Tao');
    });

    test('tolerates a missing space after data:', () {
      expect(
        LibraryChatService.parseSseLine('data:{"delta":"x"}')?['delta'],
        'x',
      );
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
      expect(LibraryChatService.parseSseLine('data: [1,2]'), isNull);
    });

    test('surfaces an error frame as a decodable map', () {
      expect(
        LibraryChatService.parseSseLine('data: {"error": "boom"}')?['error'],
        'boom',
      );
    });

    test('does not treat [DONE] as a terminator — the server sends none', () {
      // If the server ever grew an OpenAI-style sentinel it would be ignored
      // rather than silently ending the stream early.
      expect(LibraryChatService.parseSseLine('data: [DONE]'), isNull);
    });
  });

  group('captured live stream', () {
    late List<String> lines;

    setUpAll(() {
      lines = File('test/fixtures/library_stream.sse').readAsLinesSync();
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
      expect(deltas, 40);
      expect(answer.toString(), startsWith('Tao'));
      expect(sessionId, isNotNull);
      expect(model, 'translate');
      expect(sources, isNotEmpty);
    });

    test('the captured stream carries no [DONE] sentinel', () {
      expect(lines.any((l) => l.contains('[DONE]')), isFalse);
    });

    test('parses real source metadata, including chunked titles', () {
      final done = lines
          .map(LibraryChatService.parseSseLine)
          .firstWhere((o) => o?['done'] == true)!;
      final sources = LibrarySource.listFrom(done['sources']);

      expect(sources, isNotEmpty);
      final first = sources.first;
      expect(first.work, 'zhuangzi');
      expect(first.group, 'chinese');
      // Real titles carry the chunk position, so label must prefer them.
      expect(first.title, contains('část'));
      expect(first.label, first.title);
      expect(first.subtitle, 'chinese · zh');
      // Distances observed on live answers sit well under 1 — and lower is a
      // closer match, so this must never be rendered as a percentage.
      expect(first.distance, isNotNull);
      expect(first.distance, lessThan(1.0));
      expect(first.excerpt, isNotEmpty);
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

    test('listFrom ignores junk rather than making a chat unloadable', () {
      expect(LibrarySource.listFrom(null), isEmpty);
      expect(LibrarySource.listFrom('nope'), isEmpty);
      expect(LibrarySource.listFrom([1, 'x']), isEmpty);
    });

    test('round-trips through JSON', () {
      const s = LibrarySource(
        work: 'zhuangzi',
        title: 'zhuangzi (část 233/488)',
        group: 'chinese',
        lang: 'zh',
        path: 'downloads/zhuangzi.txt',
        distance: 0.17247349,
        excerpt: 'úryvek',
      );
      final back = LibrarySource.fromJson(s.toJson());
      expect(back.work, s.work);
      expect(back.title, s.title);
      expect(back.path, s.path);
      expect(back.distance, s.distance);
      expect(back.excerpt, s.excerpt);
    });
  });
}
