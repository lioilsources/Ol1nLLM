import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/core/constants/theme.dart';
import 'package:ol1n_llm/models/music_project.dart';
import 'package:ol1n_llm/providers/music_studio_provider.dart';
import 'package:ol1n_llm/screens/music_studio_screen.dart';
import 'package:ol1n_llm/services/music_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

const _analysis = {
  'caption': 'A chill lo-fi hip-hop groove with mellow electric piano.',
  'genre': 'Lo-fi hip hop',
  'bpm': 81,
  'keyscale': 'E major',
  'timesignature': '4',
  'instrumental': true,
  'duration_s': 28.5,
  'source': {'caption': 'lm', 'bpm': 'lm', 'keyscale': 'lm'},
  'warnings': ['librosa 161.5 je oktávová záměna'],
};

/// The audio service as the app sees it: upload, analyze job, generate job,
/// outputs. Records what the app sent.
class _FakeAudioServer {
  final requests = <http.Request>[];
  var sampleKnown = true;

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    if (path == '/v1/audio/vibe/samples') {
      sampleKnown = true;
      return _json({
        'sample_id': 'ab12ab12ab12ab12ab12ab12',
        'filename': 'lofi.mp3',
        'bytes': 3,
        'source_duration_s': 192.0,
        'window_start_s': 40.0,
        'duration_s': 28.5,
        'analysis': null,
      });
    }
    if (path == '/v1/audio/vibe/analyze') {
      return _json({
        'job_id': 'an-1',
        'status': 'queued',
        'queue_position': 1,
      }, 202);
    }
    if (path == '/v1/audio/vibe/generate') {
      if (!sampleKnown) return _json({'detail': 'neznámá předloha'}, 404);
      return _json({
        'job_id': 'gen-1',
        'status': 'queued',
        'queue_position': 1,
      }, 202);
    }
    if (path == '/v1/audio/jobs/an-1') {
      return _json({
        'status': 'done',
        'task': 'analyze',
        'outputs': [],
        'result': _analysis,
      });
    }
    if (path == '/v1/audio/jobs/gen-1') {
      return _json({
        'status': 'done',
        'task': 'vibe',
        'outputs': [
          for (final i in [0, 1])
            {
              'url': '/v1/audio/jobs/gen-1/outputs/0$i.mp3',
              'filename': '0$i.mp3',
              'duration': 23.3,
              'loudness_lufs': -14.0,
              'seed': 7 + i,
              'bytes': 4,
            },
        ],
        'result': {
          'params': {'caption': 'A chill lo-fi groove. More strings'},
        },
      });
    }
    if (path.startsWith('/v1/audio/jobs/gen-1/outputs/')) {
      return http.Response.bytes([1, 2, 3, 4], 200);
    }
    return http.Response('nope', 500);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('music_studio_');
    // The app calls Hive.initFlutter() in main(); saves here go to the temp dir.
    Hive.init(dir.path);
  });
  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('sample → analysis → compose → downloaded variants', () async {
    final server = _FakeAudioServer();
    final n = MusicStudioNotifier.preloaded(
      const MusicStudioState(),
      service: MusicService(
        client: MockClient(server.handle),
        pollInterval: Duration.zero,
      ),
      dir: dir,
    );
    final picked = File('${dir.path}/picked.mp3')..writeAsBytesSync([9, 9, 9]);

    await n.addSample(picked.path, 'lofi.mp3');
    await _until(() => n.state.active?.status == SampleStatus.ready);
    var p = n.state.active!;
    expect(p.sampleId, 'ab12ab12ab12ab12ab12ab12');
    expect(p.sourceDurationS, 192);
    expect(p.analysis!.bpm, 81);
    // The draft starts from what the server heard.
    expect(p.draft.caption, startsWith('A chill'));
    expect(p.draft.keyscale, 'E major');
    // The picker's temp file is copied: the project owns its sample.
    expect(File(p.samplePath).readAsBytesSync(), [9, 9, 9]);

    n.updateDraft((d) => d.copyWith(hint: 'more strings', variations: 2));
    await n.generate();
    await _until(() => n.state.active!.takes.first.status == TakeStatus.done);
    p = n.state.active!;
    final take = p.takes.single;
    expect(take.finalCaption, 'A chill lo-fi groove. More strings');
    expect(take.jobId, isNull);
    expect([for (final o in take.outputs) o.seed], [7, 8]);
    expect(File(take.outputs.first.path).readAsBytesSync(), [1, 2, 3, 4]);

    final gen = server.requests.firstWhere(
      (r) => r.url.path.endsWith('/generate'),
    );
    final body = jsonDecode(gen.body) as Map<String, dynamic>;
    expect(body['user_hint'], 'more strings');
    expect(body['bpm'], 81);
    expect(body['instrumental'], isTrue);

    await n.deleteProject(p.id);
    expect(n.state.projects, isEmpty);
    expect(File(take.outputs.first.path).existsSync(), isFalse);
    n.dispose();
    // dispose() flushes the Hive save; let it land before tearDown.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('a server that forgot the sample gets it uploaded again', () async {
    final server = _FakeAudioServer();
    final n = MusicStudioNotifier.preloaded(
      const MusicStudioState(),
      service: MusicService(
        client: MockClient(server.handle),
        pollInterval: Duration.zero,
      ),
      dir: dir,
    );
    final picked = File('${dir.path}/picked.mp3')..writeAsBytesSync([1]);
    await n.addSample(picked.path, 'lofi.mp3');
    await _until(() => n.state.active?.status == SampleStatus.ready);

    server.sampleKnown = false; // e.g. the data volume was wiped
    await n.generate();
    await _until(() => n.state.active!.takes.first.status == TakeStatus.done);
    final uploads = server.requests.where(
      (r) => r.url.path.endsWith('/samples'),
    );
    expect(uploads.length, 2);
    n.dispose();
    // dispose() flushes the Hive save; let it land before tearDown.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  group('screen layout at iPhone 12 mini width', () {
    Future<void> pump(WidgetTester tester, MusicStudioState state) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final notifier = MusicStudioNotifier.preloaded(
        state,
        service: MusicService(
          client: MockClient((_) async => http.Response('', 500)),
        ),
        dir: dir,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [musicStudioProvider.overrideWith((_) => notifier)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const MusicStudioScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    MusicProject project({
      SampleStatus status = SampleStatus.ready,
      MusicDraft? draft,
      List<MusicTake> takes = const [],
    }) =>
        MusicProject.create(
          name:
              'Velmi dlouhý název souboru s předlohou — lo-fi beat na studium.mp3',
          sampleFile: 'sample.mp3',
        ).copyWith(
          sampleId: 'ab12ab12ab12ab12ab12ab12',
          sampleDurationS: 28.5,
          sourceDurationS: 192,
          windowStartS: 40,
          status: status,
          analysis: status == SampleStatus.ready
              ? SampleAnalysis.fromJson(_analysis)
              : null,
          draft:
              draft ??
              MusicDraft.fromAnalysis(SampleAnalysis.fromJson(_analysis)),
          error: status == SampleStatus.failed
              ? 'HTTP 502: ACE-Step /release_task nedostupný'
              : null,
          takes: takes,
        );

    MusicTake take(TakeStatus status, {MusicMode mode = MusicMode.vibe}) =>
        MusicTake.start(
          MusicDraft(
            mode: mode,
            caption: 'x',
            bpm: 81,
            keyscale: 'F# minor',
            hint: 'more cinematic, add a string section and a slow build',
            lmPlan: true,
          ),
        ).copyWith(
          status: status,
          queuePosition: 3,
          error: status == TakeStatus.failed
              ? 'Stažení selhalo: server nedostupný'
              : null,
          outputs: status == TakeStatus.done
              ? const [
                  MusicOutput(
                    fileName: 'a.mp3',
                    seed: 2147483000,
                    durationS: 123,
                  ),
                  MusicOutput(fileName: 'b.mp3', seed: 8, durationS: 23),
                ]
              : const [],
        );

    testWidgets('empty', (tester) async {
      await pump(tester, const MusicStudioState());
      expect(find.text('Nahrát z okolí'), findsOneWidget);
      expect(find.text('Vybrat soubor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recorder sheet', (tester) async {
      // No native recorder under flutter test: answer every call with null
      // (hasPermission → false), which is also the denied-permission path.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (_) async => null,
      );
      await pump(tester, const MusicStudioState());
      await tester.tap(find.text('Nahrát z okolí'));
      await tester.pumpAndSettle();
      expect(find.text('0:00 / 1:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.mic).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('povol ho v Nastavení'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final status in SampleStatus.values) {
      testWidgets('sample ${status.name}', (tester) async {
        final p = project(status: status);
        await pump(tester, MusicStudioState(projects: [p], activeId: p.id));
        expect(tester.takeException(), isNull);
        // Settings and the compose button exist only once the server heard
        // the sample.
        expect(
          find.text('Co studio slyšelo'),
          status == SampleStatus.ready ? findsOneWidget : findsNothing,
        );
        if (status == SampleStatus.ready) {
          await tester.scrollUntilVisible(
            find.text('Složit 2 varianty'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
        }
        if (status == SampleStatus.failed) {
          expect(find.text('Znovu'), findsOneWidget);
        }
      });
    }

    for (final mode in MusicMode.values) {
      testWidgets('settings + every take state, ${mode.name}', (tester) async {
        final p = project(
          draft: MusicDraft.fromAnalysis(
            SampleAnalysis.fromJson(_analysis),
          ).copyWith(mode: mode),
          takes: [for (final s in TakeStatus.values) take(s, mode: mode)],
        );
        await pump(tester, MusicStudioState(projects: [p], activeId: p.id));
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(list, const Offset(0, -300));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        expect(find.textContaining('Ve frontě (3.)'), findsOneWidget);
        expect(find.textContaining('Stažení selhalo'), findsOneWidget);
      });
    }

    testWidgets('a full analysis has nothing to listen to again', (
      tester,
    ) async {
      final p = project();
      await pump(tester, MusicStudioState(projects: [p], activeId: p.id));
      expect(find.text('Poslechnout znovu'), findsNothing);
    });

    testWidgets('an analysis without the LM caption offers to listen again', (
      tester,
    ) async {
      final p = project().copyWith(
        analysis: SampleAnalysis.fromJson({
          ..._analysis,
          'caption': '',
          'source': {'caption': 'none', 'bpm': 'librosa'},
          'warnings': ['LM analýza selhala: LLM Understanding failed'],
        }),
      );
      await pump(tester, MusicStudioState(projects: [p], activeId: p.id));
      expect(find.text('Poslechnout znovu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('groove shows fidelity, vibe shows length and LM plan', (
      tester,
    ) async {
      final p = project();
      await pump(tester, MusicStudioState(projects: [p], activeId: p.id));
      expect(find.text('Délka'), findsOneWidget);
      expect(find.text('Rozvrhnout skladbu přes LM'), findsOneWidget);
      expect(find.text('Věrnost'), findsNothing);
      await tester.tap(find.text('Groove'));
      await tester.pump();
      expect(find.text('Věrnost'), findsOneWidget);
      expect(find.text('drží rytmus'), findsOneWidget);
      expect(find.text('Délka'), findsNothing);
      expect(tester.takeException(), isNull);
      // Let the debounced save fire (Hive is not set up here; it logs).
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
