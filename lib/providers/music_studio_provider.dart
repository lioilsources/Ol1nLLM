import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/music_project.dart';
import '../services/music_service.dart';

final musicStudioProvider =
    StateNotifierProvider<MusicStudioNotifier, MusicStudioState>(
      (ref) => MusicStudioNotifier(),
    );

const _uuid = Uuid();

class MusicStudioState {
  /// Most recently touched first.
  final List<MusicProject> projects;
  final String? activeId;
  final String? error;
  final String? info;

  const MusicStudioState({
    this.projects = const [],
    this.activeId,
    this.error,
    this.info,
  });

  MusicProject? get active =>
      projects.firstWhereOrNull((p) => p.id == activeId);

  MusicStudioState copyWith({
    List<MusicProject>? projects,
    String? activeId,
    bool clearActive = false,
    String? error,
    bool clearError = false,
    String? info,
    bool clearInfo = false,
  }) => MusicStudioState(
    projects: projects ?? this.projects,
    activeId: clearActive ? null : (activeId ?? this.activeId),
    error: clearError ? null : (error ?? this.error),
    info: clearInfo ? null : (info ?? this.info),
  );
}

/// MusicStudio: a sample goes up, the server listens to it (analysis job),
/// the user adjusts what it heard, and each „Složit" is one server job with
/// 1–4 variants downloaded as mp3.
///
/// Jobs live in the audio service's SQLite (unlike gen-queue's in-memory
/// TTL), so a take suspended for hours still finishes on resume: the job id
/// is persisted and [_resume] re-attaches to anything still in flight.
class MusicStudioNotifier extends StateNotifier<MusicStudioState>
    with WidgetsBindingObserver {
  MusicStudioNotifier({MusicService? service})
    : _service = service ?? MusicService(),
      _dirOverride = null,
      super(const MusicStudioState()) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  /// Tests: given state, service and storage; no lifecycle observer, no
  /// path_provider, nothing loaded from Hive.
  @visibleForTesting
  MusicStudioNotifier.preloaded(
    super.state, {
    required MusicService service,
    required Directory dir,
  }) : _service = service,
       _dirOverride = dir {
    MusicFiles.baseDir = dir.path;
  }

  final Directory? _dirOverride;

  static const _boxName = 'music_projects';
  static const _key = 'all';

  /// Pause before re-attaching after a network blip mid-poll.
  static const _interruptBackoff = Duration(seconds: 5);

  final MusicService _service;

  /// Live polls, keyed by server job id.
  final Map<String, StreamSubscription<MusicJobEvent>> _subs = {};
  Timer? _saveTimer;
  Timer? _resumeTimer;

  late final Future<Directory> _dirFuture = _dirOverride != null
      ? Future.value(_dirOverride)
      : _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/music_studio');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _init() async {
    final dir = await _dirFuture;
    MusicFiles.baseDir = dir.path;
    await _load();
    _resume();
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
    if (_dirOverride == null) WidgetsBinding.instance.removeObserver(this);
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
              .map((e) => MusicProject.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(
        projects: projects,
        activeId: projects.firstOrNull?.id,
      );
    } catch (e) {
      debugPrint('MusicStudioNotifier._load error: $e');
    }
  }

  /// Draft edits arrive per keystroke; the box holds the whole list, so writes
  /// are coalesced.
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
      debugPrint('MusicStudioNotifier._persist error: $e');
    }
  }

  MusicProject? _byId(String id) =>
      state.projects.firstWhereOrNull((p) => p.id == id);

  void _update(
    String id,
    MusicProject Function(MusicProject p) f, {
    bool touch = true,
  }) {
    if (!mounted) return;
    final projects = [for (final p in state.projects) p.id == id ? f(p) : p];
    if (touch) projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: projects);
    _persistSoon();
  }

  void _updateTake(
    String projectId,
    String takeId,
    MusicTake Function(MusicTake t) f,
  ) => _update(
    projectId,
    (p) =>
        p.copyWith(takes: [for (final t in p.takes) t.id == takeId ? f(t) : t]),
  );

  // ── Resume ───────────────────────────────────────────────────────────────

  /// Re-attach to everything still in flight (app start, foreground, or a
  /// few seconds after a network blip).
  void _resume() {
    _resumeTimer?.cancel();
    for (final p in state.projects) {
      if (p.status == SampleStatus.analyzing && p.analyzeJobId != null) {
        _followAnalysis(p.id, p.analyzeJobId!);
      } else if (!_starting.contains(p.id) &&
          (p.status == SampleStatus.uploading ||
              (p.status == SampleStatus.analyzing && p.analyzeJobId == null))) {
        // Killed mid-upload: nothing on the server to wait for, start over.
        unawaited(_startAnalysis(p.id));
      }
      for (final t in p.takes.where((t) => t.inFlight)) {
        if (t.jobId != null) {
          _followTake(p.id, t.id, t.jobId!);
        } else if (!_submitting.contains(t.id)) {
          _updateTake(
            p.id,
            t.id,
            (t) => t.copyWith(
              status: TakeStatus.failed,
              error: 'Přerušeno před odesláním',
            ),
          );
        }
      }
    }
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_interruptBackoff, () {
      if (mounted) _resume();
    });
  }

  // ── Sample & analysis ────────────────────────────────────────────────────

  /// Copy the picked file into the app's storage (the picker's copy is
  /// temporary) and start upload + analysis.
  Future<void> addSample(String sourcePath, String name) async {
    try {
      final dir = await _dirFuture;
      final dot = name.lastIndexOf('.');
      final ext = dot > 0 && name.length - dot <= 6
          ? name.substring(dot).toLowerCase()
          : '';
      final fileName = 'sample-${_uuid.v4()}$ext';
      await File(sourcePath).copy('${dir.path}/$fileName');
      final project = MusicProject.create(name: name, sampleFile: fileName);
      state = state.copyWith(
        projects: [project, ...state.projects],
        activeId: project.id,
        clearError: true,
      );
      _persistSoon();
      await _startAnalysis(project.id);
    } catch (e) {
      state = state.copyWith(error: 'Předlohu se nepodařilo načíst: $e');
    }
  }

  Future<void> retryAnalysis() async {
    final id = state.activeId;
    if (id != null) await _startAnalysis(id);
  }

  /// Projects between upload start and the analysis job id. Returning from
  /// the iOS file picker fires `resumed`, and [_resume] would otherwise start
  /// a second upload of a sample that is still going up.
  final Set<String> _starting = {};

  Future<void> _startAnalysis(String id, {bool reupload = false}) async {
    final p = _byId(id);
    if (p == null || (_starting.contains(id) && !reupload)) return;
    _starting.add(id);
    try {
      await _uploadAndAnalyze(p, reupload: reupload);
    } finally {
      _starting.remove(id);
    }
  }

  Future<void> _uploadAndAnalyze(
    MusicProject p, {
    required bool reupload,
  }) async {
    final id = p.id;
    _update(
      id,
      (p) => p.copyWith(status: SampleStatus.uploading, clearError: true),
    );
    try {
      var sampleId = p.sampleId;
      if (sampleId == null || reupload) {
        final up = await _service.uploadSample(File(p.samplePath), p.name);
        sampleId = up.sampleId;
        _update(
          id,
          (p) => p.copyWith(
            sampleId: up.sampleId,
            sampleDurationS: up.durationS,
            sourceDurationS: up.sourceDurationS,
            windowStartS: up.windowStartS,
          ),
        );
        // Same bytes were analysed before (the id is their hash).
        if (up.analysis != null && !reupload) {
          _applyAnalysis(id, up.analysis!);
          return;
        }
      }
      _update(id, (p) => p.copyWith(status: SampleStatus.analyzing));
      final jobId = await _service.analyze(sampleId);
      _update(id, (p) => p.copyWith(analyzeJobId: jobId));
      _followAnalysis(id, jobId);
    } on SampleGoneException {
      if (!reupload) return _uploadAndAnalyze(p, reupload: true);
      _failAnalysis(id, 'Server předlohu nepřijal');
    } catch (e) {
      _failAnalysis(id, _describe(e));
    }
  }

  void _failAnalysis(String id, String message) => _update(
    id,
    (p) => p.copyWith(
      status: SampleStatus.failed,
      error: message,
      clearAnalyzeJobId: true,
    ),
  );

  void _followAnalysis(String id, String jobId) {
    if (_subs.containsKey(jobId)) return;
    _subs[jobId] = _service
        .follow(jobId)
        .listen(
          (ev) {
            switch (ev) {
              case MusicDone(:final job):
                final result = job['result'];
                if (result is Map<String, dynamic>) {
                  _applyAnalysis(id, result);
                } else {
                  _failAnalysis(id, 'Analýza nic nevrátila');
                }
              case MusicFailed(:final message):
                _failAnalysis(id, message);
              case MusicInterrupted():
                _scheduleResume();
              case MusicQueued() || MusicRunning():
                break;
            }
          },
          onDone: () => _subs.remove(jobId),
          onError: (Object e) {
            _subs.remove(jobId);
            _scheduleResume();
          },
        );
  }

  /// A fresh analysis resets what it describes (caption, tempo, key, meter);
  /// mode, hint, length and variant count are the user's and stay.
  void _applyAnalysis(String id, Map<String, dynamic> json) {
    final analysis = SampleAnalysis.fromJson(json);
    _update(
      id,
      (p) => p.copyWith(
        analysis: analysis,
        status: SampleStatus.ready,
        clearAnalyzeJobId: true,
        clearError: true,
        draft: p.draft.copyWith(
          caption: analysis.caption,
          bpm: analysis.bpm,
          keyscale: analysis.keyscale,
          timesignature: analysis.timesignature.isEmpty
              ? '4'
              : analysis.timesignature,
        ),
      ),
    );
  }

  // ── Draft ────────────────────────────────────────────────────────────────

  void updateDraft(MusicDraft Function(MusicDraft d) f) {
    final id = state.activeId;
    if (id == null) return;
    _update(
      id,
      (p) => p.copyWith(draft: f(p.draft), touch: false),
      touch: false,
    );
  }

  /// Back to what the server heard.
  void resetDraftFromAnalysis() {
    final a = state.active?.analysis;
    if (a == null) return;
    updateDraft(
      (d) => d.copyWith(
        caption: a.caption,
        bpm: a.bpm,
        keyscale: a.keyscale,
        timesignature: a.timesignature.isEmpty ? '4' : a.timesignature,
      ),
    );
  }

  /// Load a take's settings back into the draft.
  void reuseTake(String takeId) {
    final t = state.active?.takes.firstWhereOrNull((t) => t.id == takeId);
    if (t != null) updateDraft((_) => t.draft);
  }

  // ── Compose ──────────────────────────────────────────────────────────────

  /// Takes between „Složit" and the server's job id — [_resume] must not
  /// declare them lost.
  final Set<String> _submitting = {};

  Future<void> generate() async {
    final p = state.active;
    if (p == null || p.status != SampleStatus.ready || p.sampleId == null) {
      return;
    }
    if (p.draft.caption.trim().isEmpty && p.draft.hint.trim().isEmpty) {
      state = state.copyWith(error: 'Chybí popis — napiš, co má znít');
      return;
    }
    final take = MusicTake.start(p.draft);
    _update(p.id, (p) => p.copyWith(takes: [take, ...p.takes]));
    await _submitTake(p.id, take.id);
  }

  Future<void> retryTake(String takeId) async {
    final p = state.active;
    final t = p?.takes.firstWhereOrNull((t) => t.id == takeId);
    if (p == null || t == null) return;
    _updateTake(
      p.id,
      takeId,
      (t) => t.copyWith(status: TakeStatus.queued, clearError: true),
    );
    if (t.jobId != null) {
      // The job exists (typically done, only the download failed).
      _followTake(p.id, takeId, t.jobId!);
    } else {
      await _submitTake(p.id, takeId);
    }
  }

  Future<void> _submitTake(
    String projectId,
    String takeId, {
    bool reupload = false,
  }) async {
    final p = _byId(projectId);
    final t = p?.takes.firstWhereOrNull((t) => t.id == takeId);
    if (p == null || t == null) return;
    _submitting.add(takeId);
    try {
      var sampleId = p.sampleId!;
      if (reupload) {
        final up = await _service.uploadSample(File(p.samplePath), p.name);
        sampleId = up.sampleId;
        _update(projectId, (p) => p.copyWith(sampleId: sampleId));
      }
      final jobId = await _service.generate(t.draft.toRequest(sampleId));
      _updateTake(projectId, takeId, (t) => t.copyWith(jobId: jobId));
      _followTake(projectId, takeId, jobId);
    } on SampleGoneException {
      if (!reupload) {
        _submitting.remove(takeId);
        return _submitTake(projectId, takeId, reupload: true);
      }
      _failTake(projectId, takeId, 'Server předlohu nepřijal');
    } catch (e) {
      _failTake(projectId, takeId, _describe(e));
    } finally {
      _submitting.remove(takeId);
    }
  }

  void _failTake(String projectId, String takeId, String message) =>
      _updateTake(
        projectId,
        takeId,
        (t) => t.copyWith(
          status: TakeStatus.failed,
          error: message,
          clearQueuePosition: true,
        ),
      );

  void _followTake(String projectId, String takeId, String jobId) {
    if (_subs.containsKey(jobId)) return;
    _subs[jobId] = _service
        .follow(jobId)
        .listen(
          (ev) {
            switch (ev) {
              case MusicQueued(:final position):
                _updateTake(
                  projectId,
                  takeId,
                  (t) => t.copyWith(
                    status: TakeStatus.queued,
                    queuePosition: position,
                  ),
                );
              case MusicRunning():
                _updateTake(
                  projectId,
                  takeId,
                  (t) => t.status == TakeStatus.running
                      ? t
                      : t.copyWith(
                          status: TakeStatus.running,
                          clearQueuePosition: true,
                        ),
                );
              case MusicDone(:final job):
                unawaited(_completeTake(projectId, takeId, job));
              case MusicFailed(:final message):
                _updateTake(
                  projectId,
                  takeId,
                  (t) => t.copyWith(
                    status: TakeStatus.failed,
                    error: message,
                    clearJobId: true,
                    clearQueuePosition: true,
                  ),
                );
              case MusicInterrupted():
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

  Future<void> _completeTake(
    String projectId,
    String takeId,
    Map<String, dynamic> job,
  ) async {
    final manifest = job['result'] as Map<String, dynamic>?;
    final params = manifest?['params'] as Map<String, dynamic>?;
    try {
      final dir = await _dirFuture;
      final outputs = <MusicOutput>[];
      for (final o in (job['outputs'] as List).cast<Map<String, dynamic>>()) {
        final bytes = await _service.download(
          o['url'] as String,
          expectedBytes: (o['bytes'] as num?)?.toInt(),
        );
        final fileName = 'take-$takeId-${o['filename']}';
        await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
        outputs.add(
          MusicOutput(
            fileName: fileName,
            seed: (o['seed'] as num?)?.toInt(),
            durationS: (o['duration'] as num?)?.toDouble() ?? 0,
            lufs: (o['loudness_lufs'] as num?)?.toDouble(),
          ),
        );
      }
      _updateTake(
        projectId,
        takeId,
        (t) => t.copyWith(
          status: TakeStatus.done,
          outputs: outputs,
          finalCaption: params?['caption'] as String?,
          clearJobId: true,
          clearQueuePosition: true,
          clearError: true,
        ),
      );
    } catch (e) {
      // The job stays on the server — „Zkusit znovu" only re-downloads.
      _updateTake(
        projectId,
        takeId,
        (t) => t.copyWith(
          status: TakeStatus.failed,
          error: 'Stažení selhalo: ${_describe(e)}',
          clearQueuePosition: true,
        ),
      );
    }
  }

  // ── Housekeeping ─────────────────────────────────────────────────────────

  void selectProject(String id) =>
      state = state.copyWith(activeId: id, clearError: true);

  Future<void> deleteTake(String takeId) async {
    final p = state.active;
    final t = p?.takes.firstWhereOrNull((t) => t.id == takeId);
    if (p == null || t == null) return;
    if (t.jobId != null) await _subs.remove(t.jobId)?.cancel();
    await _deleteFiles(t.outputs.map((o) => o.path));
    _update(
      p.id,
      (p) => p.copyWith(takes: p.takes.where((x) => x.id != takeId).toList()),
    );
  }

  Future<void> deleteProject(String id) async {
    final p = _byId(id);
    if (p == null) return;
    for (final jobId in [p.analyzeJobId, ...p.takes.map((t) => t.jobId)]) {
      if (jobId != null) await _subs.remove(jobId)?.cancel();
    }
    await _deleteFiles([
      p.samplePath,
      for (final t in p.takes) ...t.outputs.map((o) => o.path),
    ]);
    final rest = state.projects.where((x) => x.id != id).toList();
    state = state.copyWith(
      projects: rest,
      activeId: state.activeId == id ? rest.firstOrNull?.id : state.activeId,
      clearActive: rest.isEmpty,
    );
    await _persistNow();
  }

  Future<void> _deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearInfo() => state = state.copyWith(clearInfo: true);

  static String _describe(Object e) {
    if (e is SocketException) return 'server nedostupný (${e.message})';
    if (e is TimeoutException) return 'server neodpověděl včas';
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }
}
