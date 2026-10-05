import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';
import 'package:ol1n_llm/widgets/source_list.dart';

/// `url` on a source is a link to the original document. Only LeadsRAG sends
/// it (the contract in Registr smluv); Knihovník and Právník do not, and
/// answers stored in Hive before the field existed must still load.
List<LibrarySource> _sourcesOf(String fixture) {
  final done = File(fixture)
      .readAsLinesSync()
      .map(LibraryChatService.parseSseLine)
      .firstWhere((o) => o?['done'] == true)!;
  return LibrarySource.listFrom(done['sources']);
}

void main() {
  group('url from the wire', () {
    test('leads sources link to the contract in Registr smluv', () {
      final sources = _sourcesOf('test/fixtures/leads_stream.sse');
      expect(sources, isNotEmpty);
      for (final s in sources) {
        expect(s.url, startsWith('https://smlouvy.gov.cz/smlouva/'));
        expect(s.openableUrl, isNotNull);
        expect(s.openableUrl!.host, 'smlouvy.gov.cz');
      }
    });

    for (final fixture in [
      'test/fixtures/library_stream.sse',
      'test/fixtures/law_stream.sse',
    ]) {
      test('$fixture sources carry no url', () {
        final sources = _sourcesOf(fixture);
        expect(sources, isNotEmpty);
        for (final s in sources) {
          expect(s.url, isNull);
          expect(s.openableUrl, isNull);
        }
      });
    }
  });

  group('Hive round-trip', () {
    test('url survives toJson → fromJson', () {
      const src = LibrarySource(
        work: '12345678',
        excerpt: 'Dodávka tabletů',
        url: 'https://smlouvy.gov.cz/smlouva/39107334',
      );
      final json = jsonDecode(jsonEncode(src.toJson()));
      final back = LibrarySource.fromJson(json as Map<String, dynamic>);
      expect(back.url, src.url);
      expect(back.toJson(), src.toJson());
    });

    test('no url → no key, and old stored JSON still loads', () {
      const src = LibrarySource(work: 'zhuangzi', excerpt: 'Tao');
      expect(src.toJson().containsKey('url'), isFalse);

      // Shape of an answer stored before `url` existed.
      final old = LibrarySource.listFrom(
        jsonDecode(
          '[{"work":"zhuangzi","title":"zhuangzi (část 1/2)",'
          '"distance":0.2,"excerpt":"Tao"}]',
        ),
      );
      expect(old, hasLength(1));
      expect(old.single.url, isNull);
      expect(old.single.toJson(), {
        'work': 'zhuangzi',
        'title': 'zhuangzi (část 1/2)',
        'distance': 0.2,
        'excerpt': 'Tao',
      });
    });

    test('blank url is treated as missing', () {
      final s = LibrarySource.fromJson({'work': 'w', 'url': '  '});
      expect(s.url, isNull);
    });
  });

  group('openableUrl', () {
    LibrarySource withUrl(String url) =>
        LibrarySource(work: 'w', excerpt: '', url: url);

    test('accepts http and https', () {
      expect(
        withUrl('https://smlouvy.gov.cz/smlouva/1').openableUrl,
        isNotNull,
      );
      expect(withUrl('HTTP://example.org/x').openableUrl, isNotNull);
    });

    test('rejects other schemes and garbage', () {
      for (final u in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://x#Intent;end',
        'tel:123',
        'smlouvy.gov.cz/smlouva/1',
        'https://',
        'http://[',
      ]) {
        expect(withUrl(u).openableUrl, isNull, reason: u);
      }
    });
  });

  group('source sheet', () {
    Future<void> openSheet(WidgetTester tester, LibrarySource source) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SourceList(sources: [source])),
        ),
      );
      await tester.tap(find.textContaining('Zdroje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(source.label).first);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the original link when the source has a url', (
      tester,
    ) async {
      await openSheet(
        tester,
        const LibrarySource(
          work: '12345678',
          nameCs: 'Základní škola',
          excerpt: 'Dodávka tabletů',
          url: 'https://smlouvy.gov.cz/smlouva/39107334',
        ),
      );
      expect(find.byType(OriginalLink), findsOneWidget);
      expect(find.text('Otevřít originál'), findsOneWidget);
      expect(find.text('smlouvy.gov.cz'), findsOneWidget);
    });

    testWidgets('no link without a url', (tester) async {
      await openSheet(
        tester,
        const LibrarySource(work: 'zhuangzi', excerpt: 'Tao'),
      );
      expect(find.text('Tao'), findsOneWidget);
      expect(find.byType(OriginalLink), findsNothing);
      expect(find.text('Otevřít originál'), findsNothing);
    });

    testWidgets('no link for a non-http url', (tester) async {
      await openSheet(
        tester,
        const LibrarySource(
          work: 'w',
          excerpt: 'x',
          url: 'javascript:alert(1)',
        ),
      );
      expect(find.byType(OriginalLink), findsNothing);
    });
  });
}
