import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

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

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_cfId.isNotEmpty) 'CF-Access-Client-Id': _cfId,
    if (_cfSecret.isNotEmpty) 'CF-Access-Client-Secret': _cfSecret,
  };

  @override
  String get id => kBackendFluxKontextNim;

  @override
  String get label => 'FLUX Kontext';

  @override
  Stream<GenEvent> generate({required String prompt, required int n}) async* {
    yield* _infer(prompt: prompt, imageB64: null, n: n);
  }

  // Dimensions supported by the Kontext TRT buffer. Input images must use
  // values from this set on both axes to avoid tensor size mismatch errors.
  static const _supportedDims = [
    672, 688, 720, 752, 800, 832, 880, 944, 1024,
    1104, 1184, 1248, 1328, 1392, 1456, 1504, 1568,
  ];

  static int _snap(int v) => _supportedDims.reduce(
        (a, b) => (a - v).abs() <= (b - v).abs() ? a : b,
      );

  static Uint8List _snapImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final sw = _snap(decoded.width);
    final sh = _snap(decoded.height);
    if (sw == decoded.width && sh == decoded.height) return bytes;
    final resized = img.copyResize(decoded, width: sw, height: sh,
        interpolation: img.Interpolation.cubic);
    return Uint8List.fromList(img.encodePng(resized));
  }

  @override
  Stream<GenEvent> edit({
    required Uint8List image,
    required String prompt,
    required int n,
  }) async* {
    yield* _infer(prompt: prompt, imageB64: base64Encode(_snapImage(image)), n: n);
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
        final artifacts = json['artifacts'] as List?;
        final b64 = artifacts != null && artifacts.isNotEmpty
            ? (artifacts.first as Map<String, dynamic>)['base64'] as String?
            : null;
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
