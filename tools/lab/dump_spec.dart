/// Pure logic behind the lab's workflow dump: where an override lands, how a
/// sweep expands, how a cell is named. Kept out of `dump.dart` so it can be
/// unit-tested without booting a dump (`test/dump_spec_test.dart`).
library;

/// Where a value should be written.
enum OverrideKind {
  /// A real `_prepare` argument — re-enters the builder instead of editing the
  /// finished graph. Denoise is computed by a three-way rule and latent/pose
  /// switch the ControlNet branch, so post-editing those would lie.
  param,

  /// A synthetic node the app injects (`__cn_apply__`, `__depth_pre__`, …).
  syntheticNode,

  /// A literal node id from the template asset, written as `#5`.
  nodeId,

  /// Every node of a class, e.g. `KSampler`.
  nodeClass,
}

class OverrideTarget {
  const OverrideTarget({
    required this.kind,
    required this.scope,
    required this.input,
    required this.optional,
  });

  final OverrideKind kind;

  /// Node id, class name, or the parameter name for [OverrideKind.param].
  final String scope;

  /// Input key inside the node; empty for [OverrideKind.param].
  final String input;

  /// `?`-prefixed targets tolerate zero matches (a deliberately mixed plan).
  final bool optional;

  String get label => optional ? '?$raw' : raw;
  String get raw =>
      kind == OverrideKind.param ? 'param.$scope' : '$scope.$input';
}

class OverrideSpec {
  const OverrideSpec(this.target, this.value);
  final OverrideTarget target;
  final Object value;
}

/// Parses `[?]<scope>.<input>=<value>`.
///
/// A target that matches nothing is a hard error at apply time — a ControlNet
/// strength sweep over a flow without a ControlNet is a meaningless run, and
/// finding out after the GPU time is spent is the expensive way to learn it.
OverrideSpec parseOverride(String entry) {
  final eq = entry.indexOf('=');
  if (eq < 1) {
    throw FormatException('override musí být cíl=hodnota: "$entry"');
  }
  var target = entry.substring(0, eq).trim();
  final rawValue = entry.substring(eq + 1).trim();
  final optional = target.startsWith('?');
  if (optional) target = target.substring(1);

  if (target.startsWith('param.')) {
    final name = target.substring('param.'.length);
    if (name.isEmpty) throw FormatException('chybí jméno parametru: "$entry"');
    return OverrideSpec(
      OverrideTarget(
        kind: OverrideKind.param,
        scope: name,
        input: '',
        optional: optional,
      ),
      coerce(rawValue),
    );
  }
  final dot = target.lastIndexOf('.');
  if (dot < 1 || dot == target.length - 1) {
    throw FormatException('override cíl musí být <uzel|třída>.<vstup>: "$entry"');
  }
  final scope = target.substring(0, dot);
  final input = target.substring(dot + 1);
  final kind = scope.startsWith('#')
      ? OverrideKind.nodeId
      : scope.startsWith('__')
          ? OverrideKind.syntheticNode
          : OverrideKind.nodeClass;
  return OverrideSpec(
    OverrideTarget(
      kind: kind,
      scope: kind == OverrideKind.nodeId ? scope.substring(1) : scope,
      input: input,
      optional: optional,
    ),
    coerce(rawValue),
  );
}

/// `6` → int, `0.5` → double, `true` → bool, `"karras"` → String (quotes
/// stripped so a numeric-looking string can be forced).
Object coerce(String raw) {
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    return raw.substring(1, raw.length - 1);
  }
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  final i = int.tryParse(raw);
  if (i != null) return i;
  final d = double.tryParse(raw);
  if (d != null) return d;
  return raw;
}

/// Applies post-hoc overrides to a finished graph and returns, per target, the
/// node ids it hit. Throws when a non-optional target hits nothing.
Map<String, List<String>> applyOverrides(
  Map<String, dynamic> wf,
  List<OverrideSpec> specs,
) {
  final applied = <String, List<String>>{};
  for (final spec in specs) {
    final t = spec.target;
    if (t.kind == OverrideKind.param) continue; // handled by the caller
    final hits = <String>[];
    wf.forEach((id, node) {
      final map = (node as Map).cast<String, dynamic>();
      final inputs = (map['inputs'] as Map?)?.cast<String, dynamic>();
      if (inputs == null) return;
      final matches = switch (t.kind) {
        OverrideKind.nodeId => id == t.scope,
        OverrideKind.syntheticNode => id == t.scope,
        OverrideKind.nodeClass => map['class_type'] == t.scope,
        OverrideKind.param => false,
      };
      if (!matches || !inputs.containsKey(t.input)) return;
      inputs[t.input] = spec.value;
      hits.add(id);
    });
    if (hits.isEmpty && !t.optional) {
      throw StateError(
        'override "${t.raw}" netrefil žádný uzel — v tomhle grafu neexistuje. '
        'Buď je cíl překlep, nebo tahle flow ten uzel nemá; '
        'úmyslně smíšený plán označ "?${t.raw}".',
      );
    }
    if (hits.isNotEmpty) applied[t.raw] = hits;
  }
  return applied;
}

/// One sweep axis: `<target>=<v1>|<v2>|…`. Values stay literal strings all the
/// way from the caller so no float arithmetic can turn 0.3 into
/// 0.30000000000000004 in a filename.
class Sweep {
  const Sweep(this.target, this.values, this.label);
  final OverrideTarget target;
  final List<String> values;
  final String label;

  bool get isEmpty => values.isEmpty;
}

Sweep parseSweep(String? entry, String? label) {
  if (entry == null || entry.trim().isEmpty) {
    return const Sweep(
      OverrideTarget(
        kind: OverrideKind.nodeClass,
        scope: '',
        input: '',
        optional: true,
      ),
      [],
      '',
    );
  }
  final eq = entry.indexOf('=');
  if (eq < 1) throw FormatException('sweep musí být cíl=v1|v2: "$entry"');
  final values = entry
      .substring(eq + 1)
      .split('|')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  if (values.isEmpty) throw FormatException('sweep bez hodnot: "$entry"');
  final spec = parseOverride('${entry.substring(0, eq)}=${values.first}');
  final auto = spec.target.kind == OverrideKind.param
      ? spec.target.scope
      : spec.target.input;
  return Sweep(spec.target, values, (label == null || label.isEmpty) ? auto : label);
}

/// Filename-safe rendering of a sweep value: `0.5` → `0p5`, `dpmpp_2m` kept.
///
/// A LoRA sweep passes whole filenames, whose extension would otherwise turn
/// every cell id into `…-style-usnr-thin-paintpsafetensors`. The extension
/// carries no information — every LoRA has it — so it is dropped from the id
/// while the value itself stays whole for the graph.
String sanitizeValue(String v) {
  if (v.endsWith('.safetensors')) {
    v = v.substring(0, v.length - '.safetensors'.length);
  }
  final buf = StringBuffer();
  for (final c in v.split('')) {
    if (RegExp(r'[A-Za-z0-9_-]').hasMatch(c)) {
      buf.write(c);
    } else if (c == '.') {
      buf.write('p');
    } else {
      buf.write('_');
    }
  }
  return buf.toString();
}

/// `<flow>[@<label>-<value>]__<model>__<style>[__pNN]`.
///
/// Underscore-safe by construction: consumers split on `__` with maxsplit 2,
/// and the optional prompt index is appended after the style segment.
String cellId({
  required String flow,
  required String model,
  required String style,
  String? variantLabel,
  String? variantValue,
  int? promptIndex,
}) {
  final variant = (variantLabel == null || variantValue == null)
      ? ''
      : '@$variantLabel-${sanitizeValue(variantValue)}';
  final idx = promptIndex == null
      ? ''
      : '__p${promptIndex.toString().padLeft(2, '0')}';
  return '$flow$variant' '__$model' '__$style$idx';
}
