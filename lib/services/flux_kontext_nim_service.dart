import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_backend.dart';

const kBackendFluxKontextNim = 'flux_kontext_nim';

/// Calls the FLUX.1-Kontext NIM API at POST /v1/infer.
///
/// Unlike FLUX Schnell, Kontext supports img2img by accepting an optional
/// base64-encoded input image. Response schema also differs: top-level
/// "image" string instead of artifacts[0].base64.
class FluxKontextNimService implements ImageBackend {
  FluxKontextNimService();

  static const _baseUrl = String.fromEnvironment(
    'FLUX_KONTEXT_NIM_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _generateTimeout = Duration(seconds: 180);

  final http.Client _client = http.Client();

  Map<String, String> get _authHeaders {
    if (_cfId.isEmpty || _cfSecret.isEmpty) {
      throw Exception(
        'CF Access credentials not configured. '
        'Build with --dart-define=CF_ACCESS_CLIENT_ID=... --dart-define=CF_ACCESS_CLIENT_SECRET=...',
      );
    }
    return {
      'Content-Type': 'application/json',
      'CF-Access-Client-Id': _cfId,
      'CF-Access-Client-Secret': _cfSecret,
    };
  }

  @override
  String get id => kBackendFluxKontextNim;

  @override
  String get label => 'FLUX Kontext';

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    yield* _infer(prompt: prompt, imageB64: null, n: n);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield* _infer(prompt: prompt, imageB64: base64Encode(image), n: n);
  }

  Stream<GenEvent> _infer({
    required String prompt,
    required String? imageB64,
    required int n,
  }) async* {
    final images = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      yield GenRunning(i, n);
      try {
        final bodyMap = <String, dynamic>{
          'prompt': prompt,
          'aspect_ratio': imageB64 != null ? 'match_input_image' : '1:1',
          'cfg_scale': 3.5,
          'steps': 30,
          'seed': Random().nextInt(1 << 31),
        };
        if (imageB64 != null) {
          bodyMap['image'] = 'data:image/png;base64,$imageB64';
        }

        final resp = await _client
            .post(
              Uri.parse('$_baseUrl/nim/flux-kontext/v1/infer'),
              headers: _authHeaders,
              body: jsonEncode(bodyMap),
            )
            .timeout(_generateTimeout);

        if (resp.statusCode != 200) {
          yield GenFailed('Kontext NIM chyba ${resp.statusCode}: ${resp.body}');
          return;
        }

        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        // Kontext NIM returns top-level "image" string, not artifacts[].base64.
        final b64 = json['image'] as String?;
        if (b64 == null || b64.isEmpty) {
          yield const GenFailed('Kontext NIM: prázdná odpověď');
          return;
        }
        images.add(base64Decode(b64));
      } catch (e) {
        yield GenFailed('Kontext NIM chyba: $e');
        return;
      }
    }
    yield GenComplete(images);
  }

  @override
  Stream<GenEvent> follow(String jobId) async* {
    yield const GenFailed('Kontext NIM job nelze obnovit');
  }

  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _client.close();
}
