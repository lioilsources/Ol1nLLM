import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;

/// Identifies which infrastructure layer produced an HTTP error and formats
/// a human-readable Czech message for display in the app.
///
/// Layer detection priority:
///   1. Cloudflare edge  — `server: cloudflare` header or `cf-ray` header
///   2. Go Gateway       — `{"error":{"type":"gateway_error",...}}`
///   3. nim-kontext-proxy — `{"detail":...}` (FastAPI/Pydantic)
///   4. OpenAI / LiteLLM — `{"error":{"message":"...","type":"..."}}`
///   5. Fallback         — `[service] HTTP {code} při {step}: {snippet}`
class HttpLayerError {
  final String layer;
  final int? code;
  final String message;

  const HttpLayerError({required this.layer, this.code, required this.message});

  @override
  String toString() => '[$layer] $message';

  // ── HTTP response parsing ──────────────────────────────────────────────────

  static HttpLayerError parse({
    required int statusCode,
    required String body,
    required Map<String, String> headers,
    required String step,
    required String service,
  }) {
    final server = headers['server']?.toLowerCase() ?? '';
    final hasCfRay = headers.containsKey('cf-ray');
    final isCfEdge = server.contains('cloudflare') || hasCfRay;

    // 1–4. Try JSON parse first — origin errors arrive via Cloudflare too
    //      so cf-ray/server headers cannot distinguish origin vs edge errors.
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) json = decoded.cast<String, dynamic>();
    } catch (_) {}

    if (json != null) {
      // 1. Gateway: {"error":{"type":"gateway_error"}}
      final errField = json['error'];
      if (errField is Map && errField['type'] == 'gateway_error') {
        final msg = (errField['message'] as String?) ?? 'upstream service nedostupný';
        return HttpLayerError(layer: 'Gateway', code: statusCode, message: msg);
      }

      // 2. nim-kontext-proxy FastAPI: {"detail":...}
      if (json.containsKey('detail')) {
        return _parseProxyDetail(json['detail'], statusCode);
      }

      // 3. OpenAI / LiteLLM / NIM: {"error":{"message":"...","type":"..."}}
      if (errField is Map) {
        final msg = (errField['message'] as String?) ?? _snippet(body);
        final type = errField['type'] as String?;
        final suffix = (type != null && type.isNotEmpty) ? ' ($type)' : '';
        return HttpLayerError(layer: service, code: statusCode, message: '$msg$suffix');
      }

      // 4. Cloudflare edge JSON errors: {"error":"error code: 1001"} / {"error":"unauthorized"}
      if (errField is String) {
        return HttpLayerError(layer: 'Cloudflare', code: statusCode, message: errField);
      }
    }

    // 5. Non-JSON body: classify by CF headers (HTML error pages from CF edge)
    if (isCfEdge) {
      return switch (statusCode) {
        403 => HttpLayerError(
            layer: 'Cloudflare',
            code: 403,
            message: 'přístup odepřen (CF Access token neplatný nebo chybí)',
          ),
        524 => HttpLayerError(
            layer: 'Cloudflare',
            code: 524,
            message: 'server neodpověděl včas (524 origin timeout)',
          ),
        502 => HttpLayerError(
            layer: 'Cloudflare',
            code: 502,
            message: 'server nedostupný (502 bad gateway)',
          ),
        _ => HttpLayerError(
            layer: 'Cloudflare',
            code: statusCode,
            message: 'chyba $statusCode při $step',
          ),
      };
    }

    // 6. Fallback
    return HttpLayerError(
      layer: service,
      code: statusCode,
      message: 'HTTP $statusCode při $step: ${_snippet(body)}',
    );
  }

  static HttpLayerError _parseProxyDetail(dynamic detail, int statusCode) {
    String detailStr;
    if (detail is List && detail.isNotEmpty) {
      // Pydantic v2: [{type, loc, msg, input, ...}]
      final first = detail.first;
      if (first is Map) {
        final msg = (first['msg'] as String?) ?? detail.toString();
        final loc = (first['loc'] as List?)?.join('.') ?? '';
        detailStr = loc.isNotEmpty ? '$msg @ $loc' : msg;
      } else {
        detailStr = detail.toString();
      }
    } else {
      detailStr = detail?.toString() ?? '';
    }

    return switch (statusCode) {
      404 => HttpLayerError(
          layer: 'nim-proxy',
          code: 404,
          message: detailStr.contains('job not found')
              ? 'job nenalezen – proxy byl restartován? Zkus generovat znovu.'
              : 'nenalezeno: $detailStr',
        ),
      409 => HttpLayerError(
          layer: 'nim-proxy',
          code: 409,
          message: 'výsledek ještě není připraven: $detailStr',
        ),
      422 => HttpLayerError(
          layer: 'nim-proxy',
          code: 422,
          message: 'neplatný request: $detailStr',
        ),
      _ => HttpLayerError(
          layer: 'nim-proxy',
          code: statusCode,
          message: 'chyba $statusCode: $detailStr',
        ),
    };
  }

  // ── Job error string from nim-kontext-proxy ────────────────────────────────

  /// Parses the `error` field from a nim-kontext-proxy job status response
  /// (format: "ExceptionType: message") into a layer-identified error string.
  static String parseJobError(String jobError) {
    if (jobError.contains('HTTPError: 422')) {
      return '[NIM] neplatný request – chybí pole `image` nebo neplatné parametry';
    }
    if (jobError.contains('NIM returned no artifacts') ||
        jobError.contains('NIM artifact missing base64')) {
      return '[NIM] inference nevrátil výsledek (prázdná odpověď)';
    }
    if (RegExp(r'HTTPError:\s*5\d\d').hasMatch(jobError)) {
      return '[NIM] inference selhal: ${_excerpt(jobError)}';
    }
    if (jobError.contains('ConnectionError') ||
        jobError.contains('ConnectionRefusedError') ||
        jobError.contains('ConnectTimeout')) {
      return '[NIM] container nedostupný – zkontroluj `docker ps`';
    }
    return '[nim-proxy→NIM] ${_excerpt(jobError)}';
  }

  // ── Exception parsing ──────────────────────────────────────────────────────

  /// Converts a caught exception into a layer-identified error.
  static HttpLayerError fromException(
    Object e,
    String step,
    String service, {
    Duration? timeout,
  }) {
    if (e is TimeoutException) {
      final secs = timeout?.inSeconds ?? e.duration?.inSeconds ?? '?';
      return HttpLayerError(
        layer: service,
        message: 'timeout při $step (${secs}s) – server neodpověděl',
      );
    }
    if (e is SocketException) {
      return HttpLayerError(
        layer: 'Síť',
        message: 'nelze se připojit při $step ($service): ${e.message}',
      );
    }
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return HttpLayerError(
      layer: service,
      message: msg.startsWith('[') ? msg : 'chyba při $step: $msg',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _snippet(String body) {
    final s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  static String _excerpt(String s) =>
      s.length > 150 ? '${s.substring(0, 150)}…' : s;
}
