import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'model.dart';

/// Reads style maps — static packs written by `tools/stylemap` (a manifest,
/// one atlas image, one preview per picture). There is no job and no state on
/// the server; everything here is a GET.
///
/// `STYLEMAP_URL` is the directory holding `index.json`. For development
/// against the Mac that built the packs: `make stylemap-serve` and
/// `STYLEMAP_URL=http://<mac-ip>:8770` (cleartext, so `make debug` only).
class StyleMapService {
  static const _base = String.fromEnvironment(
    'STYLEMAP_URL',
    defaultValue: 'https://finetune.ol1n.com/stylemaps',
  );
  static const _cfId = String.fromEnvironment('CF_ACCESS_CLIENT_ID');
  static const _cfSecret = String.fromEnvironment('CF_ACCESS_CLIENT_SECRET');
  static const _timeout = Duration(seconds: 30);
  static const _atlasTimeout = Duration(minutes: 2);

  StyleMapService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// CF Access is optional so a LAN build works without it; through
  /// Cloudflare a missing token surfaces as a 403. Also handed to
  /// `NetworkImage` for the previews.
  Map<String, String> get headers => {
    if (_cfId.isNotEmpty) 'CF-Access-Client-Id': _cfId,
    if (_cfSecret.isNotEmpty) 'CF-Access-Client-Secret': _cfSecret,
  };

  String url(String path) => '$_base/$path';

  String thumbUrl(StyleMapPack pack, StyleMapImage im) =>
      url('${pack.id}/${pack.thumbPath(im)}');

  Future<http.Response> _get(String path, {Duration? timeout}) async {
    final http.Response r;
    try {
      r = await _client
          .get(Uri.parse(url(path)), headers: headers)
          .timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw StyleMapException('server neodpovídá ($_base)');
    } on http.ClientException catch (e) {
      throw StyleMapException('spojení selhalo: ${e.message}');
    }
    if (r.statusCode == 200) return r;
    throw StyleMapException(switch (r.statusCode) {
      403 => 'přístup odepřen (CF Access token)',
      404 => 'na serveru není: $path',
      _ => 'HTTP ${r.statusCode}',
    });
  }

  Future<List<StyleMapEntry>> fetchIndex() async {
    final r = await _get('index.json');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final p in j['packs'] as List? ?? const [])
        StyleMapEntry.fromJson(p as Map<String, dynamic>),
    ];
  }

  Future<StyleMapPack> fetchPack(String id) async {
    final r = await _get('$id/map.json');
    return StyleMapPack.fromJson(
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// The mosaic as one decoded image — drawn whole as the map and cropped as
  /// the instant placeholder of a preview.
  Future<ui.Image> fetchAtlas(StyleMapPack pack) async {
    final r = await _get(
      '${pack.id}/${pack.atlasPath}',
      timeout: _atlasTimeout,
    );
    final codec = await ui.instantiateImageCodec(r.bodyBytes);
    return (await codec.getNextFrame()).image;
  }

  void dispose() => _client.close();
}

class StyleMapException implements Exception {
  const StyleMapException(this.message);
  final String message;
  @override
  String toString() => message;
}
