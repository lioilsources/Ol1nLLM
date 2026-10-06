import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/voice.dart';
import '../services/voice_service.dart';

final voiceStudioProvider =
    StateNotifierProvider<VoiceStudioNotifier, VoiceStudioState>(
      (ref) => VoiceStudioNotifier(),
    );

class VoiceStudioState {
  /// The server's catalogue; empty until [VoiceStudioNotifier.loadVoices]
  /// succeeds.
  final List<Voice> voices;

  /// Details of the cloned voices, keyed by stored id (not `custom:…`).
  final Map<String, StoredVoice> stored;

  /// Persona id → voice id. Personas missing here speak [kDefaultVoiceId].
  final Map<String, String> personaVoices;

  final bool loading;

  /// A reference sample is going up.
  final bool uploading;

  /// Where synthesised audio and downloaded references live; null until the
  /// directory is known.
  final String? dir;

  final String? error;
  final String? info;

  const VoiceStudioState({
    this.voices = const [],
    this.stored = const {},
    this.personaVoices = const {},
    this.loading = false,
    this.uploading = false,
    this.dir,
    this.error,
    this.info,
  });

  List<Voice> get customVoices => voices.where((v) => v.isCustom).toList();

  Voice? voice(String id) => voices.firstWhereOrNull((v) => v.id == id);

  String voiceIdForPersona(String? personaId) =>
      personaVoices[personaId] ?? kDefaultVoiceId;

  /// Name to show for voice [id] — the stored name of a clone, the tidied
  /// preset name, or the bare id while the catalogue is not loaded.
  String voiceLabel(String id) {
    final v = voice(id);
    if (v == null) return id.substring(id.indexOf(':') + 1);
    return stored[v.storedId]?.name ?? v.label;
  }

  VoiceStudioState copyWith({
    List<Voice>? voices,
    Map<String, StoredVoice>? stored,
    Map<String, String>? personaVoices,
    bool? loading,
    bool? uploading,
    String? dir,
    String? error,
    String? info,
    bool clearError = false,
    bool clearInfo = false,
  }) => VoiceStudioState(
    voices: voices ?? this.voices,
    stored: stored ?? this.stored,
    personaVoices: personaVoices ?? this.personaVoices,
    loading: loading ?? this.loading,
    uploading: uploading ?? this.uploading,
    dir: dir ?? this.dir,
    error: clearError ? null : error ?? this.error,
    info: clearInfo ? null : info ?? this.info,
  );
}

/// Voices live on the server (they are shared with everything else that
/// talks to the audio service); the phone keeps only which persona speaks
/// with which voice, and a cache of what was already said.
class VoiceStudioNotifier extends StateNotifier<VoiceStudioState> {
  VoiceStudioNotifier({VoiceService? service})
    : _service = service ?? VoiceService(),
      _dirOverride = null,
      super(const VoiceStudioState()) {
    unawaited(_init());
  }

  /// Tests: given state, service and storage; nothing read from Hive or
  /// path_provider.
  @visibleForTesting
  VoiceStudioNotifier.preloaded(
    VoiceStudioState state, {
    required VoiceService service,
    required Directory dir,
  }) : _service = service,
       _dirOverride = dir,
       super(state.copyWith(dir: dir.path));

  static const _boxName = 'voice_studio';
  static const _personaKey = 'persona_voices';

  final VoiceService _service;
  final Directory? _dirOverride;

  late final Future<Directory> _dirFuture = _dirOverride != null
      ? Future.value(_dirOverride)
      : _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/voice_studio');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _init() async {
    try {
      final dir = await _dirFuture;
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_personaKey);
      if (!mounted) return;
      state = state.copyWith(
        dir: dir.path,
        personaVoices: raw == null
            ? null
            : (jsonDecode(raw as String) as Map).cast<String, String>(),
      );
    } catch (e) {
      debugPrint('VoiceStudioNotifier._init error: $e');
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearInfo() => state = state.copyWith(clearInfo: true);

  // ── Catalogue ────────────────────────────────────────────────────────────

  Future<void>? _loadingVoices;

  /// Fetch the catalogue. Concurrent callers share one request.
  Future<void> loadVoices() => _loadingVoices ??= _loadVoices().whenComplete(
    () => _loadingVoices = null,
  );

  Future<void> _loadVoices() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final voices = await _service.voices();
      // The list names a clone only by id; name, rights and length need one
      // more request each. A clone whose details fail still shows by id.
      final stored = <String, StoredVoice>{};
      await Future.wait([
        for (final v in voices.where((v) => v.isCustom))
          () async {
            try {
              stored[v.storedId] = await _service.stored(v.storedId);
            } on Exception catch (e) {
              debugPrint('[voice] detail ${v.storedId}: $e');
            }
          }(),
      ]);
      if (!mounted) return;
      state = state.copyWith(voices: voices, stored: stored, loading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: 'Hlasy se nepodařilo načíst: $e',
      );
    }
  }

  // ── Cloned voices ────────────────────────────────────────────────────────

  /// Upload [samplePath] as a new voice and return its id (`custom:…`).
  /// Throws [VoiceServiceException] — the form that asked is still open and
  /// shows the reason itself (a snackbar would sit behind its sheet).
  Future<String> createVoice({
    required String samplePath,
    required String fileName,
    required String name,
    required String language,
    required String rights,
    required String source,
  }) async {
    final voiceId = voiceIdFor(name);
    if (voiceId == null) {
      throw const VoiceServiceException(
        'Jméno hlasu musí obsahovat aspoň dvě písmena nebo číslice.',
      );
    }
    state = state.copyWith(uploading: true, clearError: true);
    try {
      await _service.upload(
        sample: File(samplePath),
        fileName: fileName,
        voiceId: voiceId,
        name: name.trim(),
        language: language,
        rights: rights,
        source: source.trim(),
      );
      await _loadVoices();
      if (mounted) {
        state = state.copyWith(info: 'Hlas „${name.trim()}“ je uložený.');
      }
      return 'custom:$voiceId';
    } on VoiceServiceException {
      rethrow;
    } on Exception catch (e) {
      throw VoiceServiceException('Server není dostupný ($e)');
    } finally {
      if (mounted) state = state.copyWith(uploading: false);
    }
  }

  /// Delete a cloned voice on the server. Personas that spoke with it fall
  /// back to the default voice.
  Future<void> deleteVoice(Voice voice) async {
    try {
      await _service.delete(voice.storedId);
      final personaVoices = {
        for (final e in state.personaVoices.entries)
          if (e.value != voice.id) e.key: e.value,
      };
      state = state.copyWith(
        voices: [...state.voices.where((v) => v.id != voice.id)],
        stored: {...state.stored}..remove(voice.storedId),
        personaVoices: personaVoices,
      );
      await _savePersonaVoices();
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: 'Hlas se nepodařilo smazat: $e');
      }
    }
  }

  /// Local file with the reference sample of a cloned voice, downloaded on
  /// first use.
  Future<String> referencePath(Voice voice) async {
    final dir = await _dirFuture;
    final file = File('${dir.path}/ref-${voice.storedId}.wav');
    if (!file.existsSync()) {
      await file.writeAsBytes(await _service.reference(voice.storedId));
    }
    return file.path;
  }

  // ── Persona voices ───────────────────────────────────────────────────────

  /// Give persona [personaId] voice [voiceId]; null returns it to the
  /// default.
  Future<void> setPersonaVoice(String personaId, String? voiceId) async {
    final next = {...state.personaVoices};
    if (voiceId == null || voiceId == kDefaultVoiceId) {
      next.remove(personaId);
    } else {
      next[personaId] = voiceId;
    }
    state = state.copyWith(personaVoices: next);
    await _savePersonaVoices();
  }

  Future<void> _savePersonaVoices() async {
    if (_dirOverride != null) return;
    final json = jsonEncode(state.personaVoices);
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_personaKey, json);
    } catch (e) {
      debugPrint('VoiceStudioNotifier._savePersonaVoices error: $e');
    }
  }

  // ── Speech ───────────────────────────────────────────────────────────────

  final Map<String, Future<String>> _inFlight = {};

  /// Path of [text] spoken by [voiceId] — from disk when it was said before,
  /// otherwise synthesised now. Throws [VoiceServiceException] with a message
  /// for the user (the engine is down, the text is empty, the network went).
  Future<String> speak(String text, String voiceId) async {
    final spoken = speakableText(text);
    if (spoken.isEmpty) {
      throw const VoiceServiceException('V odpovědi není co číst.');
    }
    // The language depends on what the voice can speak; without the
    // catalogue the request would go out as Czech even for an English voice.
    if (state.voices.isEmpty) await loadVoices();
    final language = speechLanguage(state.voice(voiceId));
    final name = speechFileName(voiceId, language, spoken);
    return _inFlight[name] ??=
        _synthesise(
          name,
          speechRequest(text: spoken, voiceId: voiceId, language: language),
        ).whenComplete(() {
          // Block body: returning the removed future would make it wait on
          // itself.
          _inFlight.remove(name);
        });
  }

  Future<String> _synthesise(String name, Map<String, dynamic> body) async {
    final dir = await _dirFuture;
    final file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 0) return file.path;
    try {
      final bytes = await _service.speak(body);
      // Written whole, then renamed: a half-written file would otherwise be
      // taken for finished audio next time.
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return file.path;
    } on VoiceServiceException {
      rethrow;
    } on Exception catch (e) {
      throw VoiceServiceException('Server není dostupný ($e)');
    }
  }
}
