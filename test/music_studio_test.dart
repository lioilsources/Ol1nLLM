import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/models/music_project.dart';
import 'package:ol1n_llm/services/music_service.dart';

/// FastAPI's JSON: UTF-8 bytes, no charset in the content type.
http.Response _fastapi(Object body, int status) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

/// Analysis exactly as the audio service returned it for the lo-fi sample on
/// SPARK (`POST /v1/audio/vibe/analyze` → job `result`).
const _lofiAnalysis = {
  'caption':
      'A chill, instrumental lo-fi hip-hop track built on a steady, relaxed '
      'drum machine groove and a smooth, melodic bassline.',
  'genre': 'Lo-fi hip hop',
  'bpm': 81,
  'keyscale': 'E major',
  'timesignature': '4',
  'vocal_language': 'unknown',
  'instrumental': true,
  'lyrics': '',
  'duration_s': 28.554,
  'source': {
    'caption': 'lm',
    'bpm': 'lm',
    'keyscale': 'lm',
    'timesignature': 'lm',
    'instrumental': 'lm',
  },
  'measured': {'lm_bpm': 81, 'librosa_bpm': 161.5},
  'warnings': ['librosa 161.5 je oktávová záměna'],
  'sample_id': '216ffb0ea82377a2d41843ca',
  'elapsed_s': 11.2,
};

void main() {
  group('SampleAnalysis / MusicDraft', () {
    test('parses the server analysis and seeds the draft from it', () {
      final a = SampleAnalysis.fromJson(_lofiAnalysis);
      expect(a.bpm, 81);
      expect(a.keyscale, 'E major');
      expect(a.source['bpm'], 'lm');
      expect(a.warnings.single, contains('oktávová'));

      final d = MusicDraft.fromAnalysis(a);
      expect(d.caption, startsWith('A chill'));
      expect(d.bpm, 81);
      expect(d.timesignature, '4');
      expect(d.mode, MusicMode.vibe);
      expect(d.coverStrength, kDefaultCoverStrength);
    });

    test('vibe request carries length and LM plan, never cover strength', () {
      const d = MusicDraft(
        caption: ' warm lo-fi ',
        hint: 'more strings',
        bpm: 81,
        keyscale: 'E major',
        durationS: 45,
        lmPlan: true,
        variations: 3,
      );
      final body = d.toRequest('abc123abc123');
      expect(body['sample_id'], 'abc123abc123');
      expect(body['mode'], 'vibe');
      expect(body['caption'], 'warm lo-fi');
      expect(body['user_hint'], 'more strings');
      expect(body['duration_s'], 45);
      expect(body['lm_plan'], isTrue);
      expect(body.containsKey('cover_strength'), isFalse);
      expect(body.containsKey('seed'), isFalse);
      // The LM transcribes a sample's lyrics — singing them back would copy
      // the original song, so compositions are always instrumental.
      expect(body['instrumental'], isTrue);
      expect(body['format'], 'mp3');
    });

    test('groove request has the sample length, strength and no LM plan', () {
      const d = MusicDraft(
        mode: MusicMode.groove,
        caption: 'jazz trio',
        durationS: 90, // ignored: a cover is as long as its source
        coverStrength: 0.7,
        lmPlan: true,
      );
      final body = d.toRequest('abc123abc123', seed: 7);
      expect(body['mode'], 'groove');
      expect(body['cover_strength'], 0.7);
      expect(body.containsKey('duration_s'), isFalse);
      expect(body.containsKey('lm_plan'), isFalse);
      expect(body['seed'], 7);
      expect(body.containsKey('bpm'), isFalse);
    });
  });

  test('project survives a JSON round trip with takes and outputs', () {
    final p = MusicProject.create(name: 'lofi.mp3', sampleFile: 'sample-1.mp3')
        .copyWith(
          sampleId: '216ffb0ea82377a2d41843ca',
          sampleDurationS: 28.5,
          sourceDurationS: 192,
          windowStartS: 40,
          status: SampleStatus.ready,
          analysis: SampleAnalysis.fromJson(_lofiAnalysis),
          draft: const MusicDraft(mode: MusicMode.groove, coverStrength: 0.6),
          takes: [
            MusicTake.start(const MusicDraft(caption: 'x')).copyWith(
              jobId: 'job-1',
              status: TakeStatus.done,
              finalCaption: 'X.',
              outputs: const [
                MusicOutput(
                  fileName: 'take-1-00.mp3',
                  seed: 7,
                  durationS: 23.3,
                  lufs: -14,
                ),
              ],
            ),
          ],
        );
    final back = MusicProject.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
    );
    expect(back.sampleId, p.sampleId);
    expect(back.status, SampleStatus.ready);
    expect(back.analysis!.bpm, 81);
    expect(back.draft.mode, MusicMode.groove);
    expect(back.draft.coverStrength, 0.6);
    final take = back.takes.single;
    expect(take.status, TakeStatus.done);
    expect(take.finalCaption, 'X.');
    expect(take.outputs.single.seed, 7);
    expect(take.outputs.single.fileName, 'take-1-00.mp3');
    // Transient progress is not persisted.
    expect(take.queuePosition, isNull);
  });

  test('labels', () {
    expect(keyLabel('E major'), 'E dur');
    expect(keyLabel('F# minor'), 'F# moll');
    expect(keyLabel(''), '—');
    expect(timeSignatureLabel('6'), '6/8');
    expect(timeSignatureLabel('4'), '4/4');
    expect(formatSeconds(83.4), '1:23');
    expect(formatSeconds(9), '0:09');
  });

  test('default track length is the sample, within the slider range', () {
    final p = MusicProject.create(name: 'a', sampleFile: 'a');
    expect(p.copyWith(sampleDurationS: 28.5).defaultDurationS, 28.5);
    expect(p.copyWith(sampleDurationS: 6).defaultDurationS, kMinTrackSeconds);
  });

  group('MusicService', () {
    test('follow maps queue → running → done', () async {
      final states = [
        {'status': 'queued', 'queue_position': 2},
        {'status': 'running'},
        {
          'status': 'done',
          'outputs': [
            {'url': '/v1/audio/jobs/j/outputs/00.mp3', 'bytes': 3},
          ],
          'result': {
            'params': {'caption': 'Warm.'},
          },
        },
      ];
      var i = 0;
      final service = MusicService(
        client: MockClient((_) async => _fastapi(states[i++], 200)),
        pollInterval: Duration.zero,
      );
      final events = await service.follow('j').toList();
      expect(events[0], isA<MusicQueued>());
      expect((events[0] as MusicQueued).position, 2);
      expect(events[1], isA<MusicRunning>());
      final done = events[2] as MusicDone;
      expect((done.job['result'] as Map)['params'], {'caption': 'Warm.'});
    });

    test('follow reports server error text', () async {
      final service = MusicService(
        client: MockClient(
          (_) async => _fastapi({
            'status': 'error',
            'error': 'ACE-Step fronta je plná',
          }, 200),
        ),
        pollInterval: Duration.zero,
      );
      final events = await service.follow('j').toList();
      expect((events.single as MusicFailed).message, 'ACE-Step fronta je plná');
    });

    test(
      'a run of network failures is an interruption, not a failure',
      () async {
        final service = MusicService(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
          pollInterval: Duration.zero,
        );
        final events = await service.follow('j').toList();
        expect(events.single, isA<MusicInterrupted>());
      },
    );

    test('unknown sample on submit asks for a re-upload', () async {
      final service = MusicService(
        client: MockClient(
          (_) async => _fastapi('{"detail":"neznámá předloha"}', 404),
        ),
      );
      expect(
        () => service.generate({'sample_id': 'x'}),
        throwsA(isA<SampleGoneException>()),
      );
    });

    test('FastAPI detail becomes the error message', () async {
      final service = MusicService(
        client: MockClient(
          (_) async => _fastapi(
            '{"detail":"chybí caption — spusť analýzu nebo ho pošli v požadavku"}',
            409,
          ),
        ),
      );
      expect(
        () => service.generate({'sample_id': 'x'}),
        throwsA(
          isA<MusicServiceException>().having(
            (e) => e.message,
            'message',
            'HTTP 409: chybí caption — spusť analýzu nebo ho pošli v požadavku',
          ),
        ),
      );
    });

    test('truncated download is retried, then rejected', () async {
      var calls = 0;
      final service = MusicService(
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes([1, 2], 200);
        }),
      );
      await expectLater(
        service.download('/v1/audio/jobs/j/outputs/00.mp3', expectedBytes: 3),
        throwsA(isA<MusicServiceException>()),
      );
      expect(calls, 2);
    });
  });
}
