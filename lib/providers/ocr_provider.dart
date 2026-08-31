import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr_scan.dart';
import '../services/media_service.dart';

final ocrProvider = StateNotifierProvider<OcrNotifier, OcrState>(
  (ref) => OcrNotifier(),
);

class OcrState {
  /// Scan history, newest-first.
  final List<OcrScan> scans;
  final bool isRunning;

  /// Last error surfaced to the user (for a one-shot snackbar).
  final String? error;

  const OcrState({
    this.scans = const [],
    this.isRunning = false,
    this.error,
  });

  OcrState copyWith({
    List<OcrScan>? scans,
    bool? isRunning,
    String? error,
    bool clearError = false,
  }) => OcrState(
    scans: scans ?? this.scans,
    isRunning: isRunning ?? this.isRunning,
    error: clearError ? null : (error ?? this.error),
  );
}

class OcrNotifier extends StateNotifier<OcrState> {
  OcrNotifier() : super(const OcrState()) {
    _load();
  }

  // Images stored as files in applicationSupportDirectory/ocr; the box holds
  // only the JSON index (same reason as image_sessions_v2 — avoid OOM).
  static const _boxName = 'ocr_scans_v1';
  static const _key = 'all';

  final MediaService _media = MediaService();

  late final Future<Directory> _dirFuture = _initDir();

  Future<Directory> _initDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/ocr');
    await dir.create(recursive: true);
    return dir;
  }

  /// Run OCR on [bytes]; on success prepend the scan to history and persist.
  Future<void> scan(Uint8List bytes) async {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true, clearError: true);
    try {
      final text = await _media.ocr(imageBytes: bytes);
      final dir = await _dirFuture;
      final scan = await OcrScan.save(
        bytes: bytes,
        dir: dir,
        text: text,
        ext: _extOf(bytes),
      );
      final scans = [scan, ...state.scans];
      state = state.copyWith(scans: scans, isRunning: false);
      await _persist(scans);
    } catch (e) {
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      state = state.copyWith(isRunning: false, error: msg);
    }
  }

  Future<void> delete(String id) async {
    final target = state.scans.firstWhereOrNull((s) => s.id == id);
    if (target != null) {
      try {
        await File(target.imagePath).delete();
      } catch (_) {}
    }
    final scans = state.scans.where((s) => s.id != id).toList();
    state = state.copyWith(scans: scans);
    await _persist(scans);
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw == null) return;
      final scans =
          (jsonDecode(raw as String) as List)
              .map((e) => OcrScan.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(scans: scans);
    } catch (e) {
      debugPrint('OcrNotifier._load error: $e');
    }
  }

  Future<void> _persist(List<OcrScan> scans) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_key, jsonEncode(scans.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('OcrNotifier._persist error: $e');
    }
  }

  static String _extOf(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }

  @override
  void dispose() {
    _media.dispose();
    super.dispose();
  }
}
