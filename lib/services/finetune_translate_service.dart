import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// One answer from the gallery's translator.
class TranslateResult {
  const TranslateResult({required this.text, required this.translator});

  /// Comma-separated Danbooru tags — what goes to the model.
  final String text;

  /// `alias@promptVersion`, recorded on the node so the eval can group on it.
  final String translator;
}

/// Prose → Danbooru tags, via the FINETUNE gallery (`POST /api/translate`).
///
/// The booru-trained checkpoints (Pony, Illustrious, NoobAI, Animagine…) read
/// tags and degrade on prose. The translation lives in the gallery on purpose:
/// one system prompt, one vocabulary filter (WD14's tag list), one cache keyed
/// by hash — so this app, the lab and the benchmark receive identical tags for
/// identical input, and the version string on every node means something.
///
/// The contract with the caller is **fail open**: any failure (gallery down,
/// translator off, model not running, timeout, no credentials) returns null,
/// and the caller sends the user's words as written and records no translator.
/// Never a different translation, never a blocked generation. The gallery has
/// no fallback model for the same reason — a silent swap would corrupt the
/// provenance the eval relies on.
class FinetuneTranslateService {
  FinetuneTranslateService({http.Client? client})
    : _client = client ?? http.Client();

  static const _baseUrl = String.fromEnvironment(
    'FINETUNE_URL',
    defaultValue: 'https://finetune.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  /// Short on purpose: this sits in front of every generation on a tags
  /// model. A translation that takes longer is not worth waiting for — the
  /// prose goes out instead and the node says so.
  static const _timeout = Duration(seconds: 12);

  /// What the gallery already answered, so a retry or a repeated prompt costs
  /// nothing and works without the gallery. Entries keep the translator
  /// version they came from — the eval still tells them apart after the
  /// server bumps its prompt — and expire so the bump is picked up.
  static const _boxName = 'finetune_translate_cache';
  static const _ttl = Duration(days: 7);

  final http.Client _client;
  Box<dynamic>? _box;

  Future<Box<dynamic>?> _cache() async {
    if (_box != null) return _box;
    try {
      return _box = await Hive.openBox(_boxName);
    } catch (e) {
      debugPrint('[translate] cache unavailable: $e');
      return null;
    }
  }

  /// [text] as Danbooru tags, or null when that cannot be done right now.
  Future<TranslateResult?> translate(String text) async {
    final key = text.trim();
    if (key.isEmpty) return null;
    if (_cfId.isEmpty || _cfSecret.isEmpty) return null;

    final box = await _cache();
    final hit = box?.get(key);
    if (hit is Map) {
      final at = DateTime.tryParse(hit['at'] as String? ?? '');
      final cachedText = hit['text'];
      final cachedTranslator = hit['translator'];
      if (at != null &&
          DateTime.now().difference(at) < _ttl &&
          cachedText is String &&
          cachedTranslator is String) {
        return TranslateResult(text: cachedText, translator: cachedTranslator);
      }
    }

    try {
      final resp = await _client
          .post(
            Uri.parse('$_baseUrl/api/translate'),
            headers: {
              'CF-Access-Client-Id': _cfId,
              'CF-Access-Client-Secret': _cfSecret,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': key, 'language': 'tags'}),
          )
          .timeout(_timeout);
      // 502 = model down, 503 = translator off or vocabulary not loaded yet.
      // Both mean "send prose"; neither is worth surfacing per generation.
      if (resp.statusCode != 200) {
        debugPrint('[translate] ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final out = (json['text'] as String? ?? '').trim();
      final translator = json['translator'] as String? ?? '';
      if (out.isEmpty || translator.isEmpty) return null;
      await box?.put(key, {
        'text': out,
        'translator': translator,
        'at': DateTime.now().toIso8601String(),
      });
      return TranslateResult(text: out, translator: translator);
    } catch (e) {
      debugPrint('[translate] failed open: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}
