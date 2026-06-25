import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_backend.dart';

/// Calls the FLUX NIM native API at POST /v1/infer.
///
/// Uses the native NIM endpoint (not the OpenAI-compatible one) so we can
/// disable the safety checker. Each request generates exactly one image;
/// n>1 is fulfilled by sequential requests.
class FluxNimService implements ImageBackend {
  FluxNimService();

  static const _baseUrl = String.fromEnvironment(
    'FLUX_NIM_URL',
    defaultValue: 'https://llm.ol1n.com',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');

  static const _generateTimeout = Duration(seconds: 120);

  final http.Client _client = http.Client();

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_cfId.isNotEmpty) 'CF-Access-Client-Id': _cfId,
    if (_cfSecret.isNotEmpty) 'CF-Access-Client-Secret': _cfSecret,
  };

  @override
  String get id => kBackendFluxNim;

  @override
  String get label => 'FLUX NIM';

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    // NIM supports only n=1 per request — run n sequential requests.
    final images = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      yield GenRunning(i, n);
      try {
        final body = jsonEncode({
          'prompt': prompt,
          'width': 1024,
          'height': 1024,
          'steps': 4,
          'seed': Random().nextInt(1 << 31),
        });
        final resp = await _client
            .post(
              Uri.parse('$_baseUrl/nim/flux-schnell/v1/infer'),
              headers: _authHeaders,
              body: body,
            )
            .timeout(_generateTimeout);

        if (resp.statusCode != 200) {
          yield GenFailed('NIM chyba ${resp.statusCode}: ${resp.body}');
          return;
        }

        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final artifacts = json['artifacts'] as List?;
        final b64 = artifacts != null && artifacts.isNotEmpty
            ? (artifacts.first as Map<String, dynamic>)['base64'] as String?
            : null;
        if (b64 == null || b64.isEmpty) {
          yield const GenFailed('NIM: prázdná odpověď');
          return;
        }
        images.add(base64Decode(b64));
      } catch (e) {
        yield GenFailed('NIM chyba: $e');
        return;
      }
    }
    yield GenComplete(images);
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield const GenFailed('FLUX NIM nepodporuje img2img');
  }

  @override
  Stream<GenEvent> follow(String jobId) async* {
    yield const GenFailed('NIM job nelze obnovit');
  }

  @override
  Future<void> interrupt() async {}

  @override
  void dispose() => _client.close();
}
