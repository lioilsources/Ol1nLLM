import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/persona.dart';
import 'package:ol1n_llm/services/chat_backend.dart';
import 'package:ol1n_llm/services/library_chat_service.dart';

/// Právník ⚖️ is the second RAG persona: the same server code and SSE dialect
/// as the library, a different corpus behind a different URL. The app routes
/// on `Persona.backend` alone, so three things must hold for a question to
/// reach the law server rather than the library or vLLM — the registry
/// entry, the service ids, and the routing rule. Each is pinned here.
///
/// The wire format itself is pinned by `law_sse_parse_test.dart` over
/// `test/fixtures/law_stream.sse`, a verbatim capture from the live server.
void main() {
  group('LibraryChatService factories', () {
    test('law() and library() report distinct, stable backend ids', () {
      final law = LibraryChatService.law();
      final library = LibraryChatService.library();
      addTearDown(law.dispose);
      addTearDown(library.dispose);

      expect(law.id, 'law');
      expect(law.id, kChatBackendLaw);
      expect(library.id, 'library');
      expect(library.id, kChatBackendLibrary);
    });

    test('error texts name the service the user actually asked', () {
      final law = LibraryChatService.law();
      final library = LibraryChatService.library();
      addTearDown(law.dispose);
      addTearDown(library.dispose);

      expect(law.label, 'právník');
      expect(law.unit, 'law-chat');
      expect(library.label, 'knihovna');
      expect(library.unit, 'library-chat');
    });

    test('leads() is a third instance with its own id, label and unit', () {
      final leads = LibraryChatService.leads();
      addTearDown(leads.dispose);

      expect(leads.id, 'leads');
      expect(leads.id, kChatBackendLeads);
      expect(leads.label, 'leads');
      expect(leads.unit, 'leadsd');
    });
  });

  group('persona registry', () {
    late Persona pravnik;
    late Persona leads;

    setUpAll(() {
      final raw = File('assets/personas/index.json').readAsStringSync();
      final personas = (jsonDecode(raw) as Map<String, dynamic>)['personas'];
      final all = (personas as List)
          .cast<Map<String, dynamic>>()
          .map(Persona.fromJson)
          .toList();
      pravnik = all.firstWhere((p) => p.id == 'pravnik');
      leads = all.firstWhere((p) => p.id == 'leads');
    });

    test('leads routes to the leads backend and carries no local prompt', () {
      expect(leads.backend, kChatBackendLeads);
      expect(leads.name, 'Leads');
      expect(leads.emoji, '📈');
      expect(leads.file, isNull);
    });

    test('pravnik routes to the law backend', () {
      expect(pravnik.backend, kChatBackendLaw);
      expect(pravnik.name, 'Právník');
    });

    test('pravnik carries no local prompt — the server builds its own', () {
      // persona_service.dart: `file == null` ⇒ no asset is loaded. A stray
      // `file` key would look functional and never be read by the RAG server.
      expect(pravnik.file, isNull);
    });
  });

  group('chatBackendIdFor', () {
    Persona persona({String? backend, String? file}) => Persona(
      id: 'p',
      name: 'p',
      emoji: 'p',
      description: '',
      backend: backend,
      file: file,
    );

    test('law persona → law', () {
      expect(chatBackendIdFor(persona(backend: 'law')), kChatBackendLaw);
    });

    test('leads persona → leads', () {
      expect(chatBackendIdFor(persona(backend: 'leads')), kChatBackendLeads);
    });

    test('library persona → library', () {
      expect(
        chatBackendIdFor(persona(backend: 'library')),
        kChatBackendLibrary,
      );
    });

    test('prompt-file persona and no persona at all → vllm', () {
      expect(
        chatBackendIdFor(persona(file: 'assets/personas/babicka.md')),
        kChatBackendVllm,
      );
      expect(chatBackendIdFor(null), kChatBackendVllm);
    });

    test('an unknown backend id falls back to vllm instead of throwing', () {
      // A registry typo must not make the whole chat unusable.
      expect(chatBackendIdFor(persona(backend: 'lww')), kChatBackendVllm);
    });
  });
}
