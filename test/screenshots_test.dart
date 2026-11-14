@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/core/constants/theme.dart';
import 'package:ol1n_llm/models/agent_step.dart';
import 'package:ol1n_llm/models/conversation.dart';
import 'package:ol1n_llm/models/figure_clip.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/image_session.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/models/message.dart';
import 'package:ol1n_llm/models/music_project.dart';
import 'package:ol1n_llm/models/story_project.dart';
import 'package:ol1n_llm/models/video_scene.dart';
import 'package:ol1n_llm/providers/chat_provider.dart';
import 'package:ol1n_llm/providers/image_studio_provider.dart';
import 'package:ol1n_llm/providers/music_studio_provider.dart';
import 'package:ol1n_llm/providers/story_studio_provider.dart';
import 'package:ol1n_llm/screens/chat_screen.dart';
import 'package:ol1n_llm/screens/image_studio_screen.dart';
import 'package:ol1n_llm/screens/music_studio_screen.dart';
import 'package:ol1n_llm/screens/story_studio_screen.dart';
import 'package:ol1n_llm/services/music_service.dart';
import 'package:ol1n_llm/services/persona_service.dart';
import 'package:ol1n_llm/services/story_service.dart';
import 'package:ol1n_llm/screens/style_map_screen.dart';
import 'package:ol1n_llm/stylemap/model.dart';
import 'package:ol1n_llm/stylemap/service.dart';
import 'package:ol1n_llm/stylemap/stylemap.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Renders the app's screens to `test/screenshots/*.png` so the store page
/// (repo `ol1n.now`, `apps/ol1nllm/`) can show them without a phone:
///
///     flutter test test/screenshots_test.dart --update-goldens
///
/// Tagged so a plain `flutter test --exclude-tags screenshots` skips it —
/// goldens compare pixels, and a different Skia or font version would red
/// the build over a rendering difference that is not a regression.
///
/// Nothing on screen is invented where the app would show server output:
///
/// * chat answers are the captured frames the parser tests already pin
///   (`law_stream.sse`, `leads_stream.sse`, `law_agent_step*.json`);
/// * `fixtures/screenshots/{scenes,stories,dances,checkpoints}.json` are the
///   live catalogs (2026-10-06) the app reads at startup, and `loras.json`
///   a subset of the live LoRA list;
/// * `fixtures/screenshots/img/` are outputs of the app's own workflows from
///   a lab run (`painters-dancer-img2img-repose`, seed 777), downscaled.
///   The style map (`fixtures/screenshots/stylemap/`) is a pack
///   `tools/stylemap` built from the whole of that run — manifest and atlas
///   as written, and only the previews the shots show.
///   One liberty: the root round's four tiles are that prompt's baseline on
///   two models × two flows, not four batch variants of one request.
///
/// The music project is the one the layout test in
/// `music_studio_flow_test.dart` uses — a sample analysis, not a capture.
const _phone = Size(390, 844);
const _fx = 'test/fixtures';
const _shots = '$_fx/screenshots';

const _fallback = ['Apple Color Emoji', 'Apple Symbols'];

late Directory _tmp;

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is unset — run this through `flutter test`.');
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) {
    fail('no material_fonts at ${dir.path} — run `flutter precache`.');
  }
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Italic', 'Light']) {
    roboto.addFont(read('${dir.path}/Roboto-$f.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('${dir.path}/MaterialIcons-Regular.otf'))).load();
  // `fontFamily: 'monospace'` (source paths, code spans) and the persona
  // emoji come from the host. Only macOS ships these files; elsewhere they
  // render as boxes, one more reason this suite is not CI's.
  const mono = '/System/Library/Fonts/Menlo.ttc';
  if (File(mono).existsSync()) {
    await (FontLoader('monospace')..addFont(read(mono))).load();
  }
  const emoji = '/System/Library/Fonts/Apple Color Emoji.ttc';
  // ☐ in the agent's checklist is in neither Roboto nor the emoji font.
  const symbols = '/System/Library/Fonts/Apple Symbols.ttf';
  if (File(symbols).existsSync()) {
    await (FontLoader('Apple Symbols')..addFont(read(symbols))).load();
  }
  if (File(emoji).existsSync()) {
    await (FontLoader('Apple Color Emoji')..addFont(read(emoji))).load();
  }
}

ThemeData get _theme {
  final t = AppTheme.dark;
  const fb = _fallback;
  return t.copyWith(
    // A style without a family resolves to the block test font, and the
    // AppBar title is the one themed style that never inherits one.
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle: t.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
        fontFamilyFallback: fb,
      ),
    ),
    textTheme: t.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: fb),
    primaryTextTheme: t.primaryTextTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: fb,
    ),
  );
}

/// The app as `OllamaApp` builds it, minus the debug ribbon, with [home] as
/// the first route and [container] holding the seeded providers.
Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        title: 'Ol1nLLM',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamilyFallback: _fallback),
          child: home,
        ),
      ),
    );

void _phoneView(WidgetTester tester) {
  // 3×: the store's lightbox zooms into these, and at 2× the 11 pt labels
  // are already soft at the size they are first shown.
  tester.view.physicalSize = _phone * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Real time in the real zone: file reads, asset loads and image decodes
/// never finish inside the fake-async zone a widget test runs in.
Future<void> _settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await _settle(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screenshots/$name.png'),
  );
}

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

dynamic _json(String path) => jsonDecode(File(path).readAsStringSync());

// ── Chat ────────────────────────────────────────────────────────────────

/// Answer text and the terminating frame of a captured RAG stream.
(String, Map<String, dynamic>) _sse(String name) {
  final text = StringBuffer();
  var done = <String, dynamic>{};
  for (final line in File('$_fx/$name.sse').readAsLinesSync()) {
    if (!line.startsWith('data:')) continue;
    final Object? obj;
    try {
      obj = jsonDecode(line.substring(5));
    } catch (_) {
      continue;
    }
    if (obj is! Map) continue;
    if (obj['delta'] is String) text.write(obj['delta']);
    if (obj['done'] == true) done = obj.cast();
  }
  return (text.toString(), done);
}

final _t0 = DateTime(2026, 10, 6, 9);

Conversation _ragConversation({
  required String id,
  required String persona,
  required String question,
  required String fixture,
  required int minutesAgo,
}) {
  final (answer, done) = _sse(fixture);
  final at = _t0.subtract(Duration(minutes: minutesAgo));
  return Conversation(
    id: id,
    title: question,
    personaId: persona,
    updatedAt: at,
    activeLeafId: '$id-a',
    messages: [
      Message(
        id: '$id-q',
        role: MessageRole.user,
        content: question,
        createdAt: at,
        personaId: persona,
      ),
      Message(
        id: '$id-a',
        parentId: '$id-q',
        role: MessageRole.assistant,
        content: answer,
        createdAt: at,
        sources: LibrarySource.listFrom(done['sources']),
      ),
    ],
  );
}

/// The lease the agent fixtures draft, cut off after [steps] agent turns.
Conversation _agentConversation(List<String> steps) {
  const id = 'agent';
  final asks = [
    'Potřebuju nájemní smlouvu na byt.',
    'Jméno nebo firma pronajímatele?: Jana Dvořáková\n'
        'Datum narození, nebo IČO pronajímatele?: 3. 5. 1971\n'
        'Adresa pronajímatele?: Krátká 12, 602 00 Brno',
    'Do kdy nájem trvá (jen u doby určité)?: 30. 9. 2027',
  ];
  final messages = <Message>[];
  String? parent;
  for (var i = 0; i < steps.length; i++) {
    final raw = (_json('$_fx/law_agent_${steps[i]}.json') as Map)
        .cast<String, dynamic>();
    final step = AgentStep.fromJson(raw);
    messages.add(
      Message(
        id: '$id-u$i',
        parentId: parent,
        role: MessageRole.user,
        content: asks[i],
        createdAt: _t0,
        personaId: 'pravnik_smlouvy',
      ),
    );
    messages.add(
      Message(
        id: '$id-a$i',
        parentId: '$id-u$i',
        role: MessageRole.assistant,
        content: raw['odpoved'] as String,
        createdAt: _t0,
        agentStep: step,
      ),
    );
    parent = '$id-a$i';
  }
  return Conversation(
    id: id,
    title: 'Nájemní smlouva na byt',
    personaId: 'pravnik_smlouvy',
    updatedAt: _t0,
    activeLeafId: parent,
    messages: messages,
  );
}

Future<ProviderContainer> _chat(
  WidgetTester tester,
  List<Conversation> conversations, {
  String? activeId,
}) async {
  _phoneView(tester);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final notifier = container.read(chatProvider.notifier);
  // The persona registry is an asset: without it the title has no emoji and
  // the input bar falls back to the vLLM hint.
  await tester.runAsync(() => container.read(personaListProvider.future));
  // ignore: invalid_use_of_protected_member
  notifier.state = ChatState(
    conversations: conversations,
    activeId: activeId ?? conversations.firstOrNull?.id,
  );
  await tester.pumpWidget(_app(container, const ChatScreen()));
  await _settle(tester);
  return container;
}

// ── Style map ───────────────────────────────────────────────────────────

/// A pack read from disk the way the app reads it from the gallery.
class _FileStyleMaps extends StyleMapService {
  _FileStyleMaps(this.pack, this.atlas);

  static const dir = '$_shots/stylemap';

  final StyleMapPack pack;
  final ui.Image atlas;

  /// Previews a shot asked for and the fixtures do not have.
  final missing = <int>{};

  @override
  Future<List<StyleMapEntry>> fetchIndex() async => [
    StyleMapEntry(
      id: pack.id,
      title: pack.title,
      count: pack.images.length,
      atlasPath: pack.atlasPath,
    ),
  ];

  @override
  Future<StyleMapPack> fetchPack(String id) async => pack;

  // The screen disposes what it is given.
  @override
  Future<ui.Image> fetchAtlas(StyleMapPack pack) async => atlas.clone();

  @override
  ImageProvider thumb(StyleMapPack pack, StyleMapImage im) {
    final file = File('$dir/${pack.id}/${pack.thumbPath(im)}');
    if (!file.existsSync()) missing.add(im.index);
    return FileImage(file);
  }

  /// Printed so a refresh knows which previews to copy from the built pack.
  void report() {
    if (missing.isNotEmpty) debugPrint('STYLEMAP-MISSING ${missing.join(' ')}');
  }
}

// ── Image Studio ────────────────────────────────────────────────────────

const _dancer =
    'full body photo of a young woman dancing in a studio, one arm raised '
    'above her head, plain light grey backdrop, soft light, photorealistic';

GenNode _node(
  String id,
  List<String> files, {
  String? parent,
  String? source,
  String prompt = _dancer,
  String? style,
  bool repose = false,
  String model = 'juggernaut-xl',
}) => GenNode(
  id: id,
  parentId: parent,
  sourceImageId: source,
  prompt: prompt,
  status: GenStatus.ready,
  images: [for (final f in files) GenImage(id: f, fileName: '$f.png')],
  isRepose: repose,
  modelId: model,
  styleId: style,
  seed: 777,
  createdAt: _t0,
);

List<GenNode> get _tree => [
  _node('root', const [
    'repose-juggernaut-xl-baseline',
    'img2img-juggernaut-xl-baseline',
    'repose-juggernaut-xl-lightning-baseline',
    'img2img-juggernaut-xl-lightning-baseline',
  ]),
  _node(
    'klimt',
    const ['repose-juggernaut-xl-klimt-golden'],
    parent: 'root',
    source: 'repose-juggernaut-xl-baseline',
    style: 'klimt-golden',
    repose: true,
  ),
  _node(
    'hopper',
    const ['repose-juggernaut-xl-hopper'],
    parent: 'root',
    source: 'repose-juggernaut-xl-baseline',
    style: 'hopper',
    repose: true,
  ),
  _node(
    'vangogh',
    const ['repose-juggernaut-xl-vangogh-arles'],
    parent: 'root',
    source: 'repose-juggernaut-xl-baseline',
    style: 'vangogh-arles',
    repose: true,
  ),
  _node(
    'monet',
    const ['img2img-juggernaut-xl-monet'],
    parent: 'hopper',
    source: 'repose-juggernaut-xl-hopper',
    prompt: 'softer light, garden behind her',
    style: 'monet',
  ),
];

Future<ProviderContainer> _studio(
  WidgetTester tester, {
  String current = 'root',
  String? selected,
  String? style,
}) async {
  _phoneView(tester);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final notifier = container.read(imageStudioProvider.notifier);
  // Let the startup catalog fetches fail (no network under test) before the
  // state is seeded, so they cannot blank the catalogs afterwards.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  GenImage.baseDir = '${_tmp.path}/image_studio';
  final scenes = _json('$_shots/scenes.json') as Map;
  final nodes = _tree;
  final older = ImageSession.create(
    id: 'older',
    nodes: [
      _node('o', const [
        'repose-juggernaut-xl-kahlo',
      ], prompt: 'portrait in the style of Frida Kahlo, flowers in her hair'),
    ],
    currentNodeId: 'o',
    modelId: 'juggernaut-xl',
  );
  final live = ImageSession.create(
    id: 'live',
    nodes: nodes,
    currentNodeId: current,
    modelId: 'juggernaut-xl',
    exportedAt: _t0,
    exportedImageCount: 8,
  );
  // ignore: invalid_use_of_protected_member
  notifier.state = ImageStudioState(
    nodes: nodes,
    currentNodeId: current,
    selectedImageId: selected,
    modelId: 'juggernaut-xl',
    selectedStyleId: style,
    availableCheckpoints: (_json('$_shots/checkpoints.json') as List).cast(),
    availableLoras: (_json('$_shots/loras.json') as List).cast(),
    availableScenes: [
      for (final s in scenes['scenes'] as List)
        VideoScene.fromJson((s as Map).cast()),
    ],
    videoCustom: VideoCustomSpec.fromJson((scenes['custom'] as Map).cast()),
    availableDances: [
      for (final d in _json('$_shots/dances.json') as List)
        FigureClip.fromJson((d as Map).cast()),
    ],
    sessions: [live, older],
    activeSessionId: 'live',
  );
  await tester.pumpWidget(_app(container, const ImageStudioScreen()));
  await _settle(tester);
  return container;
}

// ── Music Studio ────────────────────────────────────────────────────────

const _analysis = {
  'caption':
      'A chill lo-fi hip-hop groove with mellow electric piano, a dusty '
      'drum loop and a warm sub bass.',
  'genre': 'Lo-fi hip hop',
  'bpm': 81,
  'keyscale': 'E major',
  'timesignature': '4',
  'instrumental': true,
  'duration_s': 28.5,
  'source': {'caption': 'lm', 'bpm': 'lm', 'keyscale': 'lm'},
};

Future<void> _music(WidgetTester tester, MusicStudioState state) async {
  _phoneView(tester);
  final dir = Directory('${_tmp.path}/music_studio')..createSync();
  final notifier = MusicStudioNotifier.preloaded(
    state,
    service: MusicService(
      client: MockClient((_) async => http.Response('', 500)),
    ),
    dir: dir,
  );
  final container = ProviderContainer(
    overrides: [musicStudioProvider.overrideWith((_) => notifier)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(_app(container, const MusicStudioScreen()));
  await _settle(tester, rounds: 2);
}

MusicStudioState get _musicState {
  final analysis = SampleAnalysis.fromJson(_analysis);
  final draft = MusicDraft.fromAnalysis(analysis);
  MusicTake take(MusicMode mode, String hint, List<MusicOutput> outputs) =>
      MusicTake.start(
        MusicDraft(
          mode: mode,
          caption: draft.caption,
          bpm: 81,
          keyscale: 'E major',
          hint: hint,
        ),
      ).copyWith(status: TakeStatus.done, outputs: outputs);
  final p =
      MusicProject.create(
        name: 'lofi-ukazka.mp3',
        sampleFile: 'sample.mp3',
      ).copyWith(
        sampleId: 'ab12ab12ab12ab12ab12ab12',
        sampleDurationS: 28.5,
        sourceDurationS: 192,
        windowStartS: 40,
        status: SampleStatus.ready,
        analysis: analysis,
        draft: draft,
        takes: [
          take(MusicMode.vibe, 'add a string section and a slow build', const [
            MusicOutput(fileName: 'a.mp3', seed: 2147483000, durationS: 123),
            MusicOutput(fileName: 'b.mp3', seed: 8, durationS: 118),
          ]),
          take(MusicMode.groove, 'jazz trio, upright bass, brushes', const [
            MusicOutput(fileName: 'c.mp3', seed: 41, durationS: 28.5),
          ]),
        ],
      );
  return MusicStudioState(projects: [p], activeId: p.id);
}

// ── Story Studio ────────────────────────────────────────────────────────

Future<ProviderContainer> _story(
  WidgetTester tester, {
  StoryStudioState Function(List<StoryInfo> catalog)? seed,
}) async {
  _phoneView(tester);
  final stories = File('$_shots/stories.json').readAsBytesSync();
  final notifier = StoryStudioNotifier(
    service: StoryService(
      client: MockClient(
        (r) async => r.url.path.endsWith('/stories')
            ? http.Response.bytes(
                stories,
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('{"error":"not under test"}', 404),
      ),
      pollInterval: const Duration(days: 1),
    ),
  );
  final container = ProviderContainer(
    overrides: [storyStudioProvider.overrideWith((_) => notifier)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(_app(container, const StoryStudioScreen()));
  await _settle(tester);
  if (seed != null) {
    // ignore: invalid_use_of_protected_member
    notifier.state = seed(notifier.state.catalog);
    await _settle(tester, rounds: 2);
  }
  return container;
}

/// Scroll the first vertical scrollable by [dy] logical pixels.
Future<void> _scroll(WidgetTester tester, double dy, {Finder? of}) async {
  await tester.drag(of ?? find.byType(Scrollable).first, Offset(0, -dy));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadRealFonts();
    _tmp = Directory.systemTemp.createTempSync('ol1n-shots-');
    PathProviderPlatform.instance = _FakePaths(_tmp.path);
    Hive.init(_tmp.path);
    final img = Directory('${_tmp.path}/image_studio')..createSync();
    for (final f in Directory('$_shots/img').listSync().whereType<File>()) {
      f.copySync('${img.path}/${f.uri.pathSegments.last}');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    _tmp.deleteSync(recursive: true);
  });

  group('chat', () {
    Conversation law() => _ragConversation(
      id: 'law',
      persona: 'pravnik',
      question: 'Jaká je výpovědní doba u pracovního poměru?',
      fixture: 'law_stream',
      minutesAgo: 0,
    );
    Conversation leads() => _ragConversation(
      id: 'leads',
      persona: 'leads',
      question: 'Které školy kupují tablety pro výuku?',
      fixture: 'leads_stream',
      minutesAgo: 30,
    );

    testWidgets('01 role picker', (tester) async {
      await _chat(tester, const []);
      await _shoot(tester, '01-chat-role');
    });

    testWidgets('02 Právník answers from the statute', (tester) async {
      await _chat(tester, [law()]);
      await _shoot(tester, '02-chat-pravnik');
    });

    testWidgets('03 the paragraphs the answer was built from', (tester) async {
      await _chat(tester, [law()]);
      await _scroll(tester, 5000);
      await _tap(tester, find.textContaining('Zdroje ('));
      await _scroll(tester, 5000);
      await _shoot(tester, '03-chat-zdroje');
    });

    testWidgets('04 one source, opened', (tester) async {
      await _chat(tester, [law()]);
      await _scroll(tester, 5000);
      await _tap(tester, find.textContaining('Zdroje ('));
      await _scroll(tester, 5000);
      await _tap(tester, find.textContaining('§ 51 odst. 1–3'));
      await _shoot(tester, '04-chat-zdroj-detail');
    });

    testWidgets('05 Leads: companies from the contract register', (
      tester,
    ) async {
      await _chat(tester, [leads()]);
      await _tap(tester, find.textContaining('Zdroje ('));
      await _shoot(tester, '05-chat-leads');
    });

    testWidgets('06 contract agent asks by cards', (tester) async {
      await _chat(tester, [
        _agentConversation(['step1_start']),
      ]);
      await _scroll(tester, 5000);
      await _shoot(tester, '06-chat-smlouvy-otazky');
    });

    testWidgets('07 contract agent hands over the document', (tester) async {
      await _chat(tester, [
        _agentConversation(['step1_start', 'step2_answers', 'step7_document']),
      ]);
      await _scroll(tester, 5000);
      await _scroll(tester, 5000);
      await tester.scrollUntilVisible(
        find.text('Otevřít'),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      await _scroll(tester, -260);
      await _shoot(tester, '07-chat-smlouvy-dokument');
    });

    testWidgets('08 history drawer', (tester) async {
      await _chat(tester, [
        law(),
        leads(),
        _agentConversation(['step1_start']),
      ]);
      await _tap(tester, find.byTooltip('Open navigation menu'));
      await _shoot(tester, '08-chat-historie');
    });
  });

  group('image studio', () {
    const first = 'repose-juggernaut-xl-baseline';

    testWidgets('10 a round of four, the tree above it', (tester) async {
      await _studio(tester, selected: first);
      await _shoot(tester, '10-studio-kolo');
    });

    testWidgets('11 a styled round further down the tree', (tester) async {
      await _studio(
        tester,
        current: 'klimt',
        selected: 'repose-juggernaut-xl-klimt-golden',
        style: 'klimt-golden',
      );
      await _shoot(tester, '11-studio-styl-vysledek');
    });

    for (final (name, chip) in [
      ('12-studio-modely', '_ModelChip'),
      ('13-studio-styly', '_StyleChip'),
      ('14-studio-pozy', '_PoseChip'),
      ('15-studio-lora', '_LoraChip'),
    ]) {
      testWidgets('$name picker', (tester) async {
        await _studio(tester);
        await _tap(tester, _byTypeName(chip));
        await _shoot(tester, name);
      });
    }

    for (final (name, icon) in [
      ('16-studio-kadernik', Icons.content_cut),
      ('17-studio-rozhybat', Icons.movie_outlined),
      ('18-studio-3d', Icons.view_in_ar),
      ('19-studio-zachovej-pozu', Icons.directions_walk),
      ('20-studio-inpaint', Icons.auto_fix_high),
    ]) {
      testWidgets('$name from a tile', (tester) async {
        await _studio(tester);
        // Inside a tile: the tree's repose badge is the same icon.
        await _tap(
          tester,
          find.descendant(
            of: _byTypeName('_ImageTile'),
            matching: find.byIcon(icon),
          ),
        );
        if (icon == Icons.auto_fix_high) {
          await _settle(tester);
          // Paint over the hair, the way the mask editor is used.
          final g = await tester.startGesture(const Offset(170, 270));
          for (final o in const [Offset(215, 250), Offset(240, 285)]) {
            await g.moveTo(o);
            await tester.pump(const Duration(milliseconds: 30));
          }
          await g.up();
        }
        await _shoot(tester, name);
      });
    }

    testWidgets('21 session history', (tester) async {
      await _studio(tester);
      await _tap(tester, find.byTooltip('Session history'));
      await _shoot(tester, '21-studio-historie');
    });
  });

  group('style map', () {
    const set = 'dancer-painters';

    Future<(StyleMapPack, _FileStyleMaps)> open(WidgetTester tester) async {
      _phoneView(tester);
      final pack = StyleMapPack.fromJson(
        (_json('${_FileStyleMaps.dir}/$set/map.json') as Map).cast(),
      );
      final atlas = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File(
            '${_FileStyleMaps.dir}/$set/${pack.atlasPath}',
          ).readAsBytesSync(),
        );
        return (await codec.getNextFrame()).image;
      });
      addTearDown(atlas!.dispose);
      final service = _FileStyleMaps(pack, atlas);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(container, StyleMapScreen(pick: true, service: service)),
      );
      await _settle(tester);
      return (pack, service);
    }

    /// A finger on the mosaic cell of the picture made with [style] on
    /// [model] (the repose round — the run has an img2img one too).
    Future<void> pick(
      WidgetTester tester,
      StyleMapPack pack,
      String style,
      String model,
    ) async {
      final im = pack.images.firstWhere(
        (im) =>
            im.styleId == style &&
            im.modelId == model &&
            im.id.contains('repose'),
      );
      final box = tester.getRect(find.byKey(StyleMap.mosaicKey));
      final rect = StyleMapView(
        viewport: box.size,
        aspect: pack.aspect,
      ).rect.shift(box.topLeft);
      await tester.tapAt(
        rect.topLeft +
            Offset(
              (im.col + 0.5) * rect.width / pack.cols,
              (im.row + 0.5) * rect.height / pack.rows,
            ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      // The sharp preview is a file read and a decode away.
      await _settle(tester);
    }

    testWidgets('50 the mosaic, a finger on Klimt', (tester) async {
      final (pack, service) = await open(tester);
      await pick(tester, pack, 'klimt-golden', 'juggernaut-xl');
      await _shoot(tester, '50-mapa-mozaika');
      service.report();
    });

    testWidgets('51 two measured properties as axes', (tester) async {
      final (pack, service) = await open(tester);
      await pick(tester, pack, 'vangogh-arles', 'juggernaut-xl');
      await _tap(tester, find.byKey(const ValueKey('stylemap-mode-pad')));
      await _shoot(tester, '51-mapa-osy');
      service.report();
    });

    testWidgets('52 the wheel of dominant hues', (tester) async {
      final (pack, service) = await open(tester);
      await pick(tester, pack, 'matisse-cutout', 'juggernaut-xl');
      await _tap(tester, find.byKey(const ValueKey('stylemap-mode-hue')));
      await _shoot(tester, '52-mapa-barvy');
      service.report();
    });

    testWidgets('53 search and facets', (tester) async {
      final (pack, service) = await open(tester);
      await pick(tester, pack, 'monet', 'juggernaut-xl');
      await _tap(tester, find.byKey(StyleMap.filterKey));
      await _shoot(tester, '53-mapa-filtr');
      service.report();
    });
  });

  group('music studio', () {
    testWidgets('30 what the studio heard', (tester) async {
      await _music(tester, _musicState);
      await _shoot(tester, '30-hudba-analyza');
    });

    testWidgets('31 vibe or groove, then compose', (tester) async {
      await _music(tester, _musicState);
      await tester.scrollUntilVisible(
        find.textContaining('Složit'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _shoot(tester, '31-hudba-slozit');
    });

    testWidgets('33 record what is playing around', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (_) async => null,
      );
      await _music(tester, const MusicStudioState());
      await _tap(tester, find.text('Nahrát z okolí'));
      await _shoot(tester, '33-hudba-nahrat');
    });
  });

  group('story studio', () {
    testWidgets('40 catalog', (tester) async {
      await _story(tester);
      await _shoot(tester, '40-pribeh-katalog');
    });

    testWidgets('41 cast the roles', (tester) async {
      await _story(tester);
      await _tap(tester, find.text('Ztracený deštník'));
      await _shoot(tester, '41-pribeh-obsazeni');
    });

    testWidgets('42 the script', (tester) async {
      await _story(tester);
      await _tap(tester, find.text('Ztracený deštník'));
      await _scroll(tester, 520);
      await _shoot(tester, '42-pribeh-scenar');
    });

    testWidgets('43 rendering', (tester) async {
      await _story(
        tester,
        seed: (catalog) {
          final story = catalog.firstWhere((s) => s.id == 'dragon_bubbles');
          final p =
              StoryProject.create(
                story: story,
                cast: {
                  for (final r in story.characters)
                    r.role: StoryCast(name: r.name),
                },
                lang: 'cs',
                review: false,
                hd: false,
                seed: 1002,
              ).copyWith(
                jobId: 'job-under-test',
                status: StoryStatus.running,
                stage: 'all',
                phase: 'render',
                beat: 6,
              );
          return StoryStudioState(
            catalog: catalog,
            projects: [p],
            activeId: p.id,
          );
        },
      );
      await _tap(tester, find.text('Scénář'));
      await _shoot(tester, '43-pribeh-render');
    });
  });
}
