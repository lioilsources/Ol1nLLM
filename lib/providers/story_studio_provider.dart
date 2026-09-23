import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/story_project.dart';
import '../services/story_service.dart';

final storyStudioProvider =
    StateNotifierProvider<StoryStudioNotifier, StoryStudioState>(
      (ref) => StoryStudioNotifier(),
    );

const _uuid = Uuid();

class StoryStudioState {
  /// Server catalog; empty until the first successful fetch.
  final List<StoryInfo> catalog;
  final bool catalogLoading;
  final String? catalogError;

  /// Most recently touched first.
  final List<StoryProject> projects;

  /// Null = the catalog is showing (start a new story).
  final String? activeId;

  /// Project id → shots waiting for review. Transient: fetched again whenever
  /// a job enters review.
  final Map<String, List<StoryKeyframe>> keyframes;
  final String? error;
  final String? info;

  const StoryStudioState({
    this.catalog = const [],
    this.catalogLoading = false,
    this.catalogError,
    this.projects = const [],
    this.activeId,
    this.keyframes = const {},
    this.error,
    this.info,
  });

  StoryProject? get active =>
      projects.firstWhereOrNull((p) => p.id == activeId);

  StoryInfo? story(String id) => catalog.firstWhereOrNull((s) => s.id == id);

  StoryStudioState copyWith({
    List<StoryInfo>? catalog,
    bool? catalogLoading,
    String? catalogError,
    bool clearCatalogError = false,
    List<StoryProject>? projects,
    String? activeId,
    bool clearActive = false,
    Map<String, List<StoryKeyframe>>? keyframes,
    String? error,
    bool clearError = false,
    String? info,
    bool clearInfo = false,
  }) => StoryStudioState(
    catalog: catalog ?? this.catalog,
    catalogLoading: catalogLoading ?? this.catalogLoading,
    catalogError: clearCatalogError
        ? null
        : (catalogError ?? this.catalogError),
    projects: projects ?? this.projects,
    activeId: clearActive ? null : (activeId ?? this.activeId),
    keyframes: keyframes ?? this.keyframes,
    error: clearError ? null : (error ?? this.error),
    info: clearInfo ? null : (info ?? this.info),
  );
}

/// StoryStudio: pick a story from the server catalog, cast its roles with
/// your own characters, and SPARK renders a minute-long narrated anime video.
///
/// One project = one server job. It can stop halfway in `review` (keyframes
/// ready, animation not started) and wait for the user's approval or
/// repaint request; everything else runs unattended for most of an hour.
/// The job id is persisted and [_resume] re-attaches on start, on return to
/// the foreground and a few seconds after a network blip — the job lives on
/// in the server's `jobs/<id>.json` meanwhile.
class StoryStudioNotifier extends StateNotifier<StoryStudioState>
    with WidgetsBindingObserver {
  StoryStudioNotifier({StoryService? service})
    : _service = service ?? StoryService(),
      super(const StoryStudioState()) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  static const _boxName = 'story_projects';
  static const _key = 'all';

  /// Pause before re-attaching after a network blip mid-poll.
  static const _interruptBackoff = Duration(seconds: 5);

  final StoryService _service;

  /// Live polls, keyed by server job id.
  final Map<String, StreamSubscription<StoryJobEvent>> _subs = {};

  /// Projects between „Spustit" and the server's job id — [_resume] must not
  /// declare them lost (returning from the photo picker fires `resumed`).
  final Set<String> _submitting = {};
  final Set<String> _downloading = {};

  /// Keyframe images, keyed by job / shot / repaint version.
  final Map<String, Future<Uint8List>> _keyframeCache = {};
  Timer? _saveTimer;
  Timer? _resumeTimer;

  late final Future<Directory> _dirFuture = _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/story_studio');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _init() async {
    final dir = await _dirFuture;
    StoryFiles.baseDir = dir.path;
    await _load();
    _resume();
    unawaited(loadCatalog());
  }

  @override
  // `state` is the notifier's own state here, hence the parameter name.
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _resume();
    if (lifecycle == AppLifecycleState.paused) unawaited(_persistNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs.values) {
      s.cancel();
    }
    _saveTimer?.cancel();
    _resumeTimer?.cancel();
    unawaited(_persistNow());
    _service.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw == null) return;
      final projects =
          (jsonDecode(raw as String) as List)
              .map((e) => StoryProject.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(
        projects: projects,
        activeId: projects.firstOrNull?.id,
      );
    } catch (e) {
      debugPrint('StoryStudioNotifier._load error: $e');
    }
  }

  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  Future<void> _persistNow() async {
    _saveTimer?.cancel();
    // Serialised before the first await: dispose() flushes through here, and
    // `state` is off limits once the notifier is gone.
    final json = jsonEncode([for (final p in state.projects) p.toJson()]);
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_key, json);
    } catch (e) {
      debugPrint('StoryStudioNotifier._persist error: $e');
    }
  }

  StoryProject? _byId(String id) =>
      state.projects.firstWhereOrNull((p) => p.id == id);

  void _update(
    String id,
    StoryProject Function(StoryProject p) f, {
    bool touch = true,
  }) {
    if (!mounted) return;
    final projects = [for (final p in state.projects) p.id == id ? f(p) : p];
    if (touch) projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: projects);
    _persistSoon();
  }

  // ── Catalog ──────────────────────────────────────────────────────────────

  Future<void> loadCatalog() async {
    if (state.catalogLoading) return;
    state = state.copyWith(catalogLoading: true, clearCatalogError: true);
    try {
      final catalog = await _service.fetchStories();
      if (!mounted) return;
      state = state.copyWith(catalog: catalog, catalogLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(catalogLoading: false, catalogError: _describe(e));
    }
  }

  // ── Resume ───────────────────────────────────────────────────────────────

  void _resume() {
    _resumeTimer?.cancel();
    for (final p in state.projects) {
      final jobId = p.jobId;
      if (jobId != null &&
          (p.status == StoryStatus.queued ||
              p.status == StoryStatus.running ||
              p.status == StoryStatus.review)) {
        // Review too: one poll confirms it still waits (or was approved from
        // another device) and loads the keyframes.
        _follow(p.id, jobId);
      } else if (p.status == StoryStatus.submitting &&
          !_submitting.contains(p.id)) {
        _fail(p.id, 'Přerušeno před odesláním', serverFailed: true);
      }
    }
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_interruptBackoff, () {
      if (mounted) _resume();
    });
  }

  // ── Start ────────────────────────────────────────────────────────────────

  /// Start [story] with [castPaths] = role → picked image (null = the
  /// server's default picture for that role). Images are copied into the
  /// studio's storage first: the picker's files are temporary, and a failed
  /// job has to be startable again with the same cast.
  Future<void> start(
    StoryInfo story, {
    required Map<String, String?> castPaths,
    required String lang,
    required bool review,
    required bool hd,
    Map<String, String> castWho = const {},
  }) async {
    try {
      final dir = await _dirFuture;
      final cast = <String, StoryCast>{};
      for (final role in story.characters) {
        final src = castPaths[role.role];
        if (src == null && !role.hasDefault) {
          state = state.copyWith(error: 'Chybí obrázek pro ${role.name}');
          return;
        }
        String? fileName;
        if (src != null) {
          final dot = src.lastIndexOf('.');
          final ext = dot > 0 && src.length - dot <= 5
              ? src.substring(dot).toLowerCase()
              : '.jpg';
          fileName = 'cast-${_uuid.v4()}$ext';
          await File(src).copy('${dir.path}/$fileName');
        }
        cast[role.role] = StoryCast(
          name: role.name,
          fileName: fileName,
          // jen u vlastního obrázku: výchozí postava je ta ze scénáře
          who: fileName == null ? '' : (castWho[role.role] ?? '').trim(),
        );
      }
      final project = StoryProject.create(
        story: story,
        cast: cast,
        lang: lang,
        review: review,
        hd: hd,
        seed: Random().nextInt(1 << 31),
      );
      state = state.copyWith(
        projects: [project, ...state.projects],
        activeId: project.id,
        clearError: true,
      );
      _persistSoon();
      await _submit(project.id);
    } catch (e) {
      state = state.copyWith(error: 'Příběh se nepodařilo spustit: $e');
    }
  }

  Future<void> _submit(String id) async {
    final p = _byId(id);
    if (p == null || _submitting.contains(id)) return;
    _submitting.add(id);
    _update(
      id,
      (p) => p.copyWith(
        status: StoryStatus.submitting,
        clearError: true,
        clearPhase: true,
        clearPosition: true,
        keyframe: 0,
        beat: 0,
      ),
    );
    try {
      final characters = <String, Uint8List>{};
      final who = <String, String>{};
      for (final e in p.cast.entries) {
        final path = e.value.path;
        if (path != null) characters[e.key] = await File(path).readAsBytes();
        if (e.value.who.isNotEmpty) who[e.key] = e.value.who;
      }
      final acc = await _service.submit(
        storyId: p.storyId,
        characters: characters,
        lang: p.lang,
        review: p.review,
        hd: p.hd,
        who: who,
        seed: p.seed,
      );
      _update(
        id,
        (p) => p.copyWith(
          jobId: acc.jobId,
          status: StoryStatus.queued,
          stage: p.review ? 'keyframes' : 'all',
          keyframes: acc.shots > 0 ? acc.shots : null,
          beats: acc.beats > 0 ? acc.beats : null,
          seconds: acc.seconds > 0 ? acc.seconds : null,
          minutesEst: acc.minutesEst > 0 ? acc.minutesEst : null,
          serverFailed: false,
        ),
      );
      _follow(id, acc.jobId);
    } catch (e) {
      // Nothing started on the server — „Zkusit znovu" submits again.
      _fail(id, _describe(e), serverFailed: true);
    } finally {
      _submitting.remove(id);
    }
  }

  // ── Following the job ────────────────────────────────────────────────────

  void _follow(String id, String jobId) {
    if (_subs.containsKey(jobId)) return;
    _subs[jobId] = _service
        .follow(jobId)
        .listen(
          (ev) {
            switch (ev) {
              case StoryProgress(:final view):
                _applyView(id, view);
              case StoryAwaitingReview(:final view):
                _applyView(id, view, status: StoryStatus.review);
                unawaited(_loadKeyframes(id));
              case StoryFinished(:final view):
                _applyView(id, view);
                unawaited(_download(id));
              case StoryJobFailed(:final message):
                _fail(id, message, serverFailed: true);
              case StoryInterrupted():
                _scheduleResume();
            }
          },
          onDone: () => _subs.remove(jobId),
          onError: (Object e) {
            _subs.remove(jobId);
            _scheduleResume();
          },
        );
  }

  void _applyView(String id, StoryJobView v, {StoryStatus? status}) => _update(
    id,
    (p) => p.copyWith(
      status:
          status ??
          (v.status == 'queued' ? StoryStatus.queued : StoryStatus.running),
      stage: v.stage,
      phase: v.phase,
      clearPhase: v.phase == null,
      keyframe: v.keyframe,
      keyframes: v.keyframes > 0 ? v.keyframes : null,
      beat: v.beat,
      beats: v.beats > 0 ? v.beats : null,
      position: v.position,
      clearPosition: v.position == null,
      clearError: true,
    ),
    touch: false,
  );

  void _fail(String id, String message, {required bool serverFailed}) =>
      _update(
        id,
        (p) => p.copyWith(
          status: StoryStatus.failed,
          error: message,
          serverFailed: serverFailed,
          clearPosition: true,
        ),
      );

  Future<void> _download(String id) async {
    final p = _byId(id);
    final jobId = p?.jobId;
    if (p == null || jobId == null || _downloading.contains(id)) return;
    _downloading.add(id);
    _update(
      id,
      (p) => p.copyWith(status: StoryStatus.running, phase: 'download'),
      touch: false,
    );
    try {
      final bytes = await _service.result(jobId);
      final dir = await _dirFuture;
      final fileName = 'story-$id.mp4';
      await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
      _update(
        id,
        (p) => p.copyWith(
          status: StoryStatus.done,
          videoFile: fileName,
          clearPhase: true,
          clearError: true,
        ),
      );
      if (mounted) {
        state = state.copyWith(info: 'Příběh „${p.title}" je hotový');
      }
    } catch (e) {
      // The video stays on the server — „Zkusit znovu" only re-downloads.
      _fail(id, 'Stažení selhalo: ${_describe(e)}', serverFailed: false);
    } finally {
      _downloading.remove(id);
    }
  }

  /// Failed here (network, download) → re-attach. Failed on the server → a
  /// new job with the same cast, but only once the server confirms that job
  /// is really gone or still broken: a job can be restarted from the server
  /// side (a fixed pipeline, a repaint), and resubmitting would throw away an
  /// hour of finished render.
  Future<void> retry(String id) async {
    final p = _byId(id);
    if (p == null) return;
    final jobId = p.jobId;
    if (p.serverFailed && jobId != null && await _aliveOnServer(jobId)) {
      _update(
        id,
        (p) => p.copyWith(
          status: StoryStatus.queued,
          clearError: true,
          serverFailed: false,
        ),
      );
      _follow(id, jobId);
      return;
    }
    if (p.serverFailed || jobId == null) {
      await _submit(id);
    } else {
      _update(
        id,
        (p) => p.copyWith(status: StoryStatus.queued, clearError: true),
      );
      _follow(id, p.jobId!);
    }
  }

  /// The server still knows this job and it is not in the error state — then
  /// following it again beats starting over. A network hiccup answers false,
  /// so the user keeps the old behaviour of submitting anew.
  Future<bool> _aliveOnServer(String jobId) async {
    try {
      return (await _service.job(jobId)).status != 'error';
    } on Exception {
      return false;
    }
  }

  // ── Review ───────────────────────────────────────────────────────────────

  Future<void> _loadKeyframes(String id) async {
    final jobId = _byId(id)?.jobId;
    if (jobId == null) return;
    try {
      final list = await _service.keyframes(jobId);
      if (!mounted) return;
      state = state.copyWith(keyframes: {...state.keyframes, id: list});
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: 'Záběry se nenačetly: ${_describe(e)}');
    }
  }

  Future<void> reloadKeyframes(String id) => _loadKeyframes(id);

  /// JPEG of one keyframe; cached per repaint round so scrolling the review
  /// grid doesn't download it again.
  Future<Uint8List> keyframeImage(StoryProject p, String shot) {
    final jobId = p.jobId;
    if (jobId == null) {
      return Future.error(const StoryServiceException('job ještě neběží'));
    }
    final key = '$jobId/$shot/${p.keyframesVersion}';
    return _keyframeCache.putIfAbsent(
      key,
      () => _service.keyframeImage(jobId, shot).catchError((Object e) {
        _keyframeCache.remove(key); // a failed fetch must be retryable
        throw e;
      }),
    );
  }

  /// Keyframes are fine — animate.
  Future<void> approve(String id) async {
    final p = _byId(id);
    final jobId = p?.jobId;
    if (p == null || jobId == null || p.status != StoryStatus.review) return;
    try {
      await _service.approve(jobId);
      _update(
        id,
        (p) => p.copyWith(
          status: StoryStatus.queued,
          stage: 'all',
          keyframe: p.keyframes,
          beat: 0,
          clearPhase: true,
        ),
      );
      _follow(id, jobId);
    } catch (e) {
      state = state.copyWith(error: 'Schválení neprošlo: ${_describe(e)}');
    }
  }

  /// Repaint [shots] with a new seed; [edits] = shot → new English
  /// description (those shots repaint from it). Comes back to review.
  Future<void> repaint(
    String id, {
    required Set<String> shots,
    Map<String, String> edits = const {},
  }) async {
    final p = _byId(id);
    final jobId = p?.jobId;
    final all = {...shots, ...edits.keys};
    if (p == null || jobId == null || all.isEmpty) return;
    try {
      await _service.approve(jobId, redo: shots.toList()..sort(), edits: edits);
      _update(
        id,
        (p) => p.copyWith(
          status: StoryStatus.queued,
          stage: 'redo',
          keyframe: 0,
          keyframes: all.length,
          keyframesVersion: p.keyframesVersion + 1,
          clearPhase: true,
        ),
      );
      _follow(id, jobId);
    } catch (e) {
      state = state.copyWith(error: 'Překreslení neprošlo: ${_describe(e)}');
    }
  }

  // ── Result ───────────────────────────────────────────────────────────────

  /// `sub` (burned-in subtitles) or `16x9`, downloaded on first use.
  Future<String?> variantPath(String id, String variant) async {
    final p = _byId(id);
    final jobId = p?.jobId;
    if (p == null || jobId == null) return null;
    final have = p.variantFiles[variant];
    if (have != null && File(StoryFiles.path(have)).existsSync()) {
      return StoryFiles.path(have);
    }
    try {
      final bytes = await _service.result(jobId, variant: variant);
      final dir = await _dirFuture;
      final fileName = 'story-$id-$variant.mp4';
      await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
      _update(
        id,
        (p) => p.copyWith(variantFiles: {...p.variantFiles, variant: fileName}),
        touch: false,
      );
      return StoryFiles.path(fileName);
    } catch (e) {
      state = state.copyWith(
        error: 'Varianta se nepodařila stáhnout: ${_describe(e)}',
      );
      return null;
    }
  }

  // ── Housekeeping ─────────────────────────────────────────────────────────

  void selectProject(String id) =>
      state = state.copyWith(activeId: id, clearError: true);

  /// Back to the catalog.
  void newStory() => state = state.copyWith(clearActive: true);

  /// Removes the project from the phone. A job still running on SPARK keeps
  /// running — the server has no cancel.
  Future<void> deleteProject(String id) async {
    final p = _byId(id);
    if (p == null) return;
    if (p.jobId != null) await _subs.remove(p.jobId)?.cancel();
    for (final path in [
      for (final c in p.cast.values)
        if (c.path != null) c.path!,
      if (p.videoPath != null) p.videoPath!,
      for (final f in p.variantFiles.values) StoryFiles.path(f),
    ]) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    final rest = state.projects.where((x) => x.id != id).toList();
    state = state.copyWith(
      projects: rest,
      keyframes: {...state.keyframes}..remove(id),
      activeId: state.activeId == id ? null : state.activeId,
      clearActive: state.activeId == id,
    );
    await _persistNow();
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearInfo() => state = state.copyWith(clearInfo: true);

  static String _describe(Object e) {
    if (e is SocketException) return 'server nedostupný (${e.message})';
    if (e is TimeoutException) return 'server neodpověděl včas';
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }
}
