import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';

/// Právník ⚖️ speaks the library's SSE dialect, so `LibraryChatService`
/// parses it unchanged — but the *content* of the frames differs, and that is
/// what the app renders: the source label is the act's full citation
/// (`name_cs`), the position is a paragraph range in the `title` tail instead
/// of `část N/M`, and there is no translation (`excerpt_cs` is null — the
/// corpus is Czech). `test/fixtures/law_stream.sse` is a verbatim capture from
/// `law-chat` on SPARK (2026-09-23, `curl -N` on `/chat/stream`, question
/// „Jaká je výpovědní doba u pracovního poměru?"), like `library_stream.sse`.
void main() {
  late List<String> lines;

  setUpAll(() {
    lines = File('test/fixtures/law_stream.sse').readAsLinesSync();
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
    expect(deltas, 875);
    expect(answer.toString(), contains('výpovědní doba'));
    expect(sessionId, isNotNull);
    expect(model, isNotEmpty);
    expect(sources, hasLength(8));
    expect(lines.any((l) => l.contains('[DONE]')), isFalse);
  });

  test('a law source renders as citation + paragraph without any app change', () {
    final done = lines
        .map(LibraryChatService.parseSseLine)
        .firstWhere((o) => o?['done'] == true)!;
    final sources = LibrarySource.listFrom(done['sources']);
    final first = sources.first;

    // The row label is the act, the subtitle carries the paragraph range that
    // the server put at the end of `title` — the same `(…)` convention the
    // library uses for `část N/M`, so `LibrarySource` needs no new field.
    expect(first.work, '262/2006 Sb.');
    expect(first.nameCs, 'Zákon č. 262/2006 Sb., zákoník práce');
    expect(first.title, '262/2006 Sb. (§ 51 odst. 1–3)');
    expect(first.label, first.nameCs);
    expect(first.subtitle, '§ 51 odst. 1–3 · pracovni_socialni · cs');

    // No translation for a Czech corpus: the excerpt is shown as-is, and the
    // detail sheet must not offer an „originál" section.
    expect(first.excerptCs, isNull);
    expect(first.hasTranslation, isFalse);
    expect(first.readableExcerpt, first.excerpt);
    expect(first.excerpt, startsWith('§ 51'));

    expect(first.distance, isNotNull);
    expect(first.distance, lessThan(1.0));
    // Every hit is a paragraph, never a positional chunk.
    for (final s in sources) {
      expect(s.title, matches(RegExp(r'\((§|čl\.) ')), reason: s.title);
      expect(s.lang, 'cs');
    }
  });
}
