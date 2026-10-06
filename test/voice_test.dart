import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/core/constants/theme.dart';
import 'package:ol1n_llm/models/persona.dart';
import 'package:ol1n_llm/models/voice.dart';
import 'package:ol1n_llm/providers/voice_studio_provider.dart';
import 'package:ol1n_llm/screens/voice_studio_screen.dart';
import 'package:ol1n_llm/services/persona_service.dart';
import 'package:ol1n_llm/services/voice_service.dart';

/// FastAPI's JSON: UTF-8 bytes, no charset in the content type.
http.Response _fastapi(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// `GET /v1/audio/voices` as SPARK returned it on 2026-10-06 (62 rows).
List<Voice> _catalogue() =>
    Voice.fromRows(jsonDecode(_fixture('audio_voices.json')) as List);

/// The audio service as the app sees it; records what the app sent.
class _FakeAudioServer {
  final requests = <http.BaseRequest>[];
  final bodies = <Map<String, dynamic>>[];
  http.Response? ttsRefusal;
  final audio = utf8.encode('ID3-not-really-mp3');

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    if (path == '/v1/audio/voices' && r.method == 'GET') {
      return _fastapi(_fixture('audio_voices.json'));
    }
    if (path == '/v1/audio/voices' && r.method == 'POST') {
      return _fastapi(_fixture('audio_voice_stored.json'), 201);
    }
    if (path == '/v1/audio/voices/smoke-ref') {
      return _fastapi(_fixture('audio_voice_stored.json'));
    }
    if (path == '/v1/audio/tts') {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return ttsRefusal ??
          _fastapi({
            'job_id': 'j1',
            'status': 'queued',
            'queue_position': 1,
          }, 202);
    }
    if (path == '/v1/audio/jobs/j1') {
      // The finished Kasandra job from SPARK, pointed at our fake output.
      final job =
          jsonDecode(_fixture('audio_tts_job.json')) as Map<String, dynamic>;
      final output = (job['outputs'] as List).first as Map<String, dynamic>;
      output['url'] = '/v1/audio/jobs/j1/outputs/00.mp3';
      output['bytes'] = audio.length;
      return _fastapi(job);
    }
    if (path == '/v1/audio/jobs/j1/outputs/00.mp3') {
      return http.Response.bytes(audio, 200);
    }
    return _fastapi({'detail': 'Not Found'}, 404);
  }
}

void main() {
  group('catalogue', () {
    test('a clone listed once per cloning model is one voice', () {
      final voices = _catalogue();
      final clones = voices.where((v) => v.isCustom).toList();
      expect(clones, hasLength(1));
      final clone = clones.single;
      expect(clone.id, 'custom:smoke-ref');
      expect(clone.storedId, 'smoke-ref');
      expect(clone.models.map((m) => m.model), [
        'xtts-v2',
        'chatterbox-multilingual',
        'chatterbox-cs',
      ]);
      // Czech cloning exists only on the two models without a clean licence.
      expect(clone.modelsFor('cs').map((m) => m.model), [
        'xtts-v2',
        'chatterbox-cs',
      ]);
      expect(clone.modelsFor('cs').every((m) => !m.commercial), isTrue);
    });

    test('the default voice is in the catalogue and speaks Czech', () {
      final kasandra = _catalogue().firstWhere((v) => v.id == kDefaultVoiceId);
      expect(kasandra.speaks('cs'), isTrue);
      expect(kasandra.label, 'Kasandra (medium)');
      expect(kasandra.genderLabel, 'ženský');
      expect(kasandra.models.single.licenseLabel, 'CC-BY-4.0 · uvést autora');
    });

    test('preset names are tidied, licences worded', () {
      final voices = _catalogue();
      expect(
        voices.firstWhere((v) => v.id == 'kokoro:af_heart').label,
        'Heart',
      );
      final jirka = voices.firstWhere(
        (v) => v.id == 'piper:cs_CZ-jirka-medium',
      );
      expect(jirka.models.single.licenseLabel, 'licence neověřená');
    });

    test('speech language follows what the voice can speak', () {
      final voices = _catalogue();
      Voice byId(String id) => voices.firstWhere((v) => v.id == id);
      expect(speechLanguage(byId(kDefaultVoiceId)), 'cs');
      expect(speechLanguage(byId('custom:smoke-ref')), 'cs');
      expect(speechLanguage(byId('kokoro:af_heart')), 'en');
      // Catalogue not loaded: assume the persona's language.
      expect(speechLanguage(null), 'cs');
    });
  });

  group('voiceIdFor', () {
    test('folds diacritics and punctuation into a server id', () {
      expect(voiceIdFor('Děda Vráťa'), 'deda-vrata');
      expect(voiceIdFor('  Smug_Cat!! '), 'smug_cat');
      expect(voiceIdFor('🙂'), isNull);
      expect(voiceIdFor('a'), isNull);
    });

    test('result always passes the server pattern', () {
      final pattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,47}$');
      for (final name in ['Žluťoučký kůň', '__x__y', 'A' * 80, '-- 12 --']) {
        expect(pattern.hasMatch(voiceIdFor(name)!), isTrue, reason: name);
      }
    });
  });

  group('speakableText', () {
    test('drops markdown, code, links and table rules', () {
      const md = '''
## Nadpis

Tohle je **tučně** a [odkaz](https://example.com/x), viz https://ol1n.com/a.

- první bod
- druhý bod

```dart
print('nečíst');
```

| Dílo | Autor |
|---|---|
| Ilias | Homér |
''';
      final s = speakableText(md);
      expect(s, isNot(contains('#')));
      expect(s, isNot(contains('*')));
      expect(s, isNot(contains('http')));
      expect(s, isNot(contains('nečíst')));
      expect(s, isNot(contains('|')));
      expect(s, isNot(contains('---')));
      expect(s, contains('Nadpis.'));
      expect(s, contains('Tohle je tučně a odkaz'));
      expect(s, contains('první bod. druhý bod.'));
      expect(s, contains('Ilias, Homér'));
    });

    test('caps at the server limit on a sentence end', () {
      final long = List.filled(400, 'Tohle je jedna věta.').join(' ');
      final s = speakableText(long);
      expect(s.length, lessThanOrEqualTo(kMaxSpeechChars));
      expect(s.endsWith('věta.'), isTrue);
    });

    test('nothing but syntax is nothing to read', () {
      expect(speakableText('```\ncode\n```'), isEmpty);
    });
  });

  group('VoiceService', () {
    test('speak: submit, poll, download', () async {
      final server = _FakeAudioServer();
      final service = VoiceService(
        client: MockClient(server.handle),
        pollInterval: Duration.zero,
      );
      final bytes = await service.speak(
        speechRequest(text: 'Ahoj.', voiceId: kDefaultVoiceId, language: 'cs'),
      );
      expect(bytes, server.audio);
      expect(server.bodies.single, {
        'text': 'Ahoj.',
        'language': 'cs',
        'voice': kDefaultVoiceId,
        'commercial_only': false,
        'format': 'mp3',
      });
    });

    test('a refused request shows the server\'s own words', () async {
      // Body as SPARK returned it for a Czech clone with commercial_only.
      final server = _FakeAudioServer()
        ..ttsRefusal = _fastapi({
          'detail':
              "pro jazyk 'cs' (klonovaný hlas) není komerčně použitelný TTS "
              'model (kandidáti: chatterbox-cs, xtts-v2). Na pokusy pošli '
              'commercial_only=false.',
        }, 403);
      final service = VoiceService(client: MockClient(server.handle));
      await expectLater(
        service.speak({'text': 'Ahoj.'}),
        throwsA(
          isA<VoiceServiceException>().having(
            (e) => e.message,
            'message',
            allOf(startsWith('HTTP 403: pro jazyk'), contains('klonovaný')),
          ),
        ),
      );
    });

    test('engine down (503) is a sentence, not a status code', () async {
      final server = _FakeAudioServer()
        ..ttsRefusal = _fastapi({'detail': 'Hlas teď neběží.'}, 503);
      final service = VoiceService(client: MockClient(server.handle));
      await expectLater(
        service.speak({'text': 'Ahoj.'}),
        throwsA(
          isA<VoiceServiceException>().having(
            (e) => e.message,
            'message',
            'Hlas teď neběží.',
          ),
        ),
      );
    });
  });

  group('VoiceStudioNotifier', () {
    late Directory dir;
    late _FakeAudioServer server;
    late VoiceStudioNotifier notifier;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('voice_test');
      server = _FakeAudioServer();
      notifier = VoiceStudioNotifier.preloaded(
        const VoiceStudioState(),
        service: VoiceService(
          client: MockClient(server.handle),
          pollInterval: Duration.zero,
        ),
        dir: dir,
      );
    });

    tearDown(() {
      notifier.dispose();
      dir.deleteSync(recursive: true);
    });

    test('loadVoices names clones from their stored details', () async {
      await notifier.loadVoices();
      expect(notifier.state.customVoices, hasLength(1));
      expect(notifier.state.stored['smoke-ref']!.rights, 'own');
      expect(notifier.state.voiceLabel('custom:smoke-ref'), 'smoke-ref');
      expect(notifier.state.voiceLabel(kDefaultVoiceId), 'Kasandra (medium)');
    });

    test('the same sentence in the same voice is synthesised once', () async {
      final first = await notifier.speak('**Ahoj.**', kDefaultVoiceId);
      final second = await notifier.speak('Ahoj.', kDefaultVoiceId);
      expect(second, first);
      expect(File(first).readAsBytesSync(), server.audio);
      expect(server.count('POST', '/v1/audio/tts'), 1);
      // Markdown never reaches the engine.
      expect(server.bodies.single['text'], 'Ahoj.');
    });

    test('an English preset reads in English, a clone in Czech', () async {
      await notifier.speak('Ahoj.', 'kokoro:af_heart');
      await notifier.speak('Ahoj.', 'custom:smoke-ref');
      expect(server.bodies.map((b) => b['language']), ['en', 'cs']);
      // One catalogue fetch serves both.
      expect(server.count('GET', '/v1/audio/voices'), 1);
    });

    test('an answer with nothing to read is refused before the network', () {
      expect(
        notifier.speak('```\nx\n```', kDefaultVoiceId),
        throwsA(isA<VoiceServiceException>()),
      );
      expect(server.requests, isEmpty);
    });

    test('a failed synthesis leaves no file to mistake for audio', () async {
      server.ttsRefusal = _fastapi({'detail': 'Hlas teď neběží.'}, 503);
      await expectLater(
        notifier.speak('Ahoj.', kDefaultVoiceId),
        throwsA(isA<VoiceServiceException>()),
      );
      expect(dir.listSync(), isEmpty);
      server.ttsRefusal = null;
      expect(
        File(await notifier.speak('Ahoj.', kDefaultVoiceId)).existsSync(),
        isTrue,
      );
    });

    test('createVoice uploads under an id derived from the name', () async {
      final sample = File('${dir.path}/in.m4a')..writeAsBytesSync([1, 2, 3]);
      final id = await notifier.createVoice(
        samplePath: sample.path,
        fileName: 'in.m4a',
        name: 'Děda Vráťa',
        language: 'cs',
        rights: 'own',
        source: 'já, říjen 2026',
      );
      expect(id, 'custom:deda-vrata');
      final upload =
          server.requests.firstWhere((r) => r.method == 'POST') as http.Request;
      final body = latin1.decode(upload.bodyBytes);
      expect(body, contains('name="voice_id"'));
      expect(body, contains('deda-vrata'));
      expect(body, contains('name="rights"'));
      expect(notifier.state.uploading, isFalse);
    });

    test('deleting a voice returns its personas to the default', () async {
      await notifier.loadVoices();
      await notifier.setPersonaVoice('babicka', 'custom:smoke-ref');
      await notifier.setPersonaVoice('dedecek', 'piper:cs_CZ-jirka-medium');
      expect(notifier.state.voiceIdForPersona('babicka'), 'custom:smoke-ref');
      await notifier.deleteVoice(notifier.state.voice('custom:smoke-ref')!);
      expect(notifier.state.voiceIdForPersona('babicka'), kDefaultVoiceId);
      expect(
        notifier.state.voiceIdForPersona('dedecek'),
        'piper:cs_CZ-jirka-medium',
      );
      expect(notifier.state.customVoices, isEmpty);
      expect(server.count('DELETE', '/v1/audio/voices/smoke-ref'), 1);
    });
  });

  testWidgets('screen at iPhone 12 mini width: clones, personas, presets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('voice_screen');
    addTearDown(() => dir.deleteSync(recursive: true));
    final stored = StoredVoice.fromJson(
      jsonDecode(_fixture('audio_voice_stored.json')) as Map<String, dynamic>,
    );
    final notifier = VoiceStudioNotifier.preloaded(
      VoiceStudioState(
        voices: _catalogue(),
        stored: {stored.voiceId: stored},
        personaVoices: const {'babicka': 'custom:smoke-ref'},
      ),
      // The screen refreshes on open; a dead server must leave what it has.
      service: VoiceService(
        client: MockClient((_) async => http.Response('', 500)),
      ),
      dir: dir,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceStudioProvider.overrideWith((_) => notifier),
          personaListProvider.overrideWith(
            (_) async => const [
              Persona(
                id: 'babicka',
                name: 'Babička',
                emoji: '👵',
                description: '',
              ),
              Persona(
                id: 'dedecek',
                name: 'Dědeček',
                emoji: '👴',
                description: '',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const VoiceStudioScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The clone, with its length, declared rights and Czech licences.
    expect(
      find.textContaining('4 s · je to můj hlas · česky: xtts-v2'),
      findsOneWidget,
    );
    // Babička speaks with the clone, Dědeček with the default.
    expect(find.text('smoke-ref'), findsNWidgets(2));
    final list = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Jirka (medium)'),
      200,
      scrollable: list,
    );
    expect(find.text('HOTOVÉ HLASY'), findsOneWidget);
    expect(find.text('Kasandra (medium)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
