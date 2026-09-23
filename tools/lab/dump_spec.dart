/// Pure logic behind the lab's workflow dump: where an override lands, how a
/// sweep expands, how a cell is named. Kept out of `dump.dart` so it can be
/// unit-tested without booting a dump (`test/dump_spec_test.dart`).
library;

import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/style_preset.dart';

/// Which of a prompt file's texts a model reads.
///
/// Three buckets where [PromptDialect] has two: its natural half splits again,
/// because a sentence written for a photoreal SDXL checkpoint and one written
/// for FLUX are not the same sentence. Lab-only, and deliberately not a field
/// on [ImageModelSpec] — the app has a single prompt box and would never read
/// it, and a registry field no app code reads rots.
enum PromptFamily {
  /// Danbooru tags — the booru-captioned lineages (Pony, Illustrious, …).
  danbooru,

  /// Phrases for the photoreal and vanilla SDXL checkpoints.
  juggernaut,

  /// FLUX, which reads a sentence.
  flux,
}

/// The family a model reads, derived from the registry rather than declared.
///
/// Dialect decides first: a booru checkpoint wants tags whatever it is built
/// on. The remaining split is FLUX vs SDXL, and "no checkpoint to patch" is
/// the FLUX test the rest of the lab already uses (`ckptName == null` —
/// a dedicated UNETLoader graph), plus the two gen-queue backends, which are
/// FLUX by construction. Every other entry in `kImageModels` runs a generic
/// SDXL template, so a new model lands in the right bucket on its own.
PromptFamily promptFamilyFor(ImageModelSpec m) {
  if (m.promptDialect == PromptDialect.booru) return PromptFamily.danbooru;
  final flux = m.kind != ImageBackendKind.comfyUi || m.preset?.ckptName == null;
  return flux ? PromptFamily.flux : PromptFamily.juggernaut;
}

/// One entry of the prompt file: the same subject written out per family,
/// under a shared id.
class PromptBody {
  const PromptBody({required this.id, required this.texts});

  final String id;
  final Map<PromptFamily, String> texts;

  /// The text this family reads.
  ///
  /// A missing family is an error, never a fallback onto a neighbour: handing
  /// a danbooru checkpoint a FLUX sentence returns a picture that looks like a
  /// measurement of that prompt and is not one. The plan blocks this before
  /// the dump ever runs; this is the backstop that keeps it true.
  String textFor(PromptFamily family) {
    final text = texts[family];
    if (text == null) {
      throw FormatException(
        'prompt "$id" nemá text pro ${family.name} — buď ho doplň, '
        'nebo z běhu vynech modely, které ho čtou',
      );
    }
    return text;
  }
}

/// Prompt bodies as the plan normalises them out of the YAML file:
/// `[{id, texts: {danbooru, juggernaut, flux}}]`.
///
/// Go owns the YAML parse (one parser in the system, and the run directory
/// keeps the JSON it produced), so anything malformed has been rejected with a
/// line number by the time this runs. The checks here are the ones that would
/// otherwise reach the graph: an id or a text that is empty, or a family name
/// this build does not know.
List<PromptBody> parsePromptBodies(List<dynamic> json) => [
      for (final (i, raw) in json.indexed) _promptBody(i, raw),
    ];

PromptBody _promptBody(int i, Object? raw) {
  if (raw is! Map) throw FormatException('prompt #$i není objekt');
  final id = raw['id'];
  if (id is! String || id.isEmpty) throw FormatException('prompt #$i nemá id');
  final texts = raw['texts'];
  if (texts is! Map) throw FormatException('prompt "$id" nemá texty');
  final byFamily = <PromptFamily, String>{};
  for (final entry in texts.entries) {
    final family = PromptFamily.values
        .where((f) => f.name == entry.key)
        .firstOrNull;
    if (family == null) {
      throw FormatException('prompt "$id": neznámá rodina "${entry.key}", '
          'čekám ${PromptFamily.values.map((f) => f.name).join('|')}');
    }
    final text = entry.value;
    if (text is! String || text.trim().isEmpty) {
      throw FormatException('prompt "$id" má prázdný text pro ${family.name}');
    }
    byFamily[family] = text;
  }
  if (byFamily.isEmpty) throw FormatException('prompt "$id" nemá žádný text');
  return PromptBody(id: id, texts: byFamily);
}

/// One column of the prompt axis: a line from the prompt box and, when a
/// prompt file is in play, the body it prefixes.
class PromptAxisEntry {
  const PromptAxisEntry({required this.prefix, this.body});

  final String prefix;
  final PromptBody? body;

  /// What the manifest lists for this column. With per-family bodies there is
  /// no single text to show, so the id names the column and the cell keeps the
  /// text that was really sent (read back out of the graph).
  String get label => body == null
      ? prefix
      : (prefix.isEmpty ? body!.id : '$prefix · ${body!.id}');

  String subjectFor(PromptFamily family) {
    if (body == null) return prefix;
    final text = body!.textFor(family);
    return prefix.isEmpty ? text : '$prefix, $text';
  }
}

/// The prompt axis: every line of the prompt box × every body from the file.
///
/// Without a file the box is the axis, exactly as before. With one, its lines
/// become prefixes — a shared instruction tried against each body — so the
/// axis is the product, and an empty box means one empty prefix rather than no
/// cells at all, because the file already carries the prompts.
List<PromptAxisEntry> buildPromptAxis({
  required List<String> prefixes,
  required List<PromptBody> bodies,
}) {
  if (bodies.isEmpty) {
    return [for (final p in prefixes) PromptAxisEntry(prefix: p)];
  }
  final heads = prefixes.isEmpty ? const [''] : prefixes;
  return [
    for (final prefix in heads)
      for (final body in bodies) PromptAxisEntry(prefix: prefix, body: body),
  ];
}

/// Style candidates from `--styles-file`: `[{id, label, block, …}]`.
///
/// Keys beyond the ones read here are tolerated on purpose — the candidates
/// file is a working document and grows fields (notes, texts for other model
/// families) before the app does. A missing `id` or `block` is still an error:
/// a candidate without text would dump as an unstyled cell labelled as styled.
List<StylePreset> parseStyleCandidates(List<dynamic> json) => [
      for (final (i, raw) in json.indexed) _candidate(i, raw),
    ];

StylePreset _candidate(int i, Object? raw) {
  if (raw is! Map) throw FormatException('kandidát #$i není objekt');
  final id = raw['id'];
  final block = raw['block'];
  if (id is! String || id.isEmpty) {
    throw FormatException('kandidát #$i nemá id');
  }
  if (block is! String || block.trim().isEmpty) {
    throw FormatException('kandidát "$id" nemá block');
  }
  return StylePreset(
    id: id,
    label: (raw['label'] as String?) ?? id,
    block: block,
    booru: raw['booru'] as String?,
    artist: raw['artist'] as String?,
    period: raw['period'] as String?,
  );
}

/// The dialect a cell's style text is written in: the model's own, unless the
/// `param.styleDialect` sweep asks for another — which is how the tags-vs-
/// phrases comparison can be repeated without hand-written id variants.
PromptDialect styleDialectFor(Object? param, PromptDialect model) {
  if (param == null) return model;
  for (final d in PromptDialect.values) {
    if (d.name == param) return d;
  }
  throw FormatException('param.styleDialect musí být '
      '${PromptDialect.values.map((d) => d.name).join('|')}, ne "$param"');
}

/// Where a cell's style text sits in the prompt. The app always sends
/// `end` (prefix, subject, style — [applyStylePreset]); the other two exist
/// for the lab, because CLIP weights early tokens more and the quality prefix
/// of the anime lineages comes first.
enum StylePosition {
  /// `prefix, subject, style` — what the app sends.
  end,

  /// `prefix, style, subject` — style ahead of the subject, prefix still first.
  front,

  /// `style, prefix, subject` — style ahead of everything.
  first,
}

StylePosition stylePositionFor(Object? param) {
  if (param == null) return StylePosition.end;
  for (final p in StylePosition.values) {
    if (p.name == param) return p;
  }
  throw FormatException('param.stylePosition musí být '
      '${StylePosition.values.map((p) => p.name).join('|')}, ne "$param"');
}

/// `param.qualityPrefix=on|off` — whether the preset's quality tags go in.
bool qualityPrefixFor(Object? param) => switch (param) {
      null || true || 'on' => true,
      false || 'off' => false,
      _ => throw FormatException(
          'param.qualityPrefix musí být on|off, ne "$param"'),
    };

/// The prompt a cell hands to the builder, and whether the builder should
/// still put the quality prefix in front of it.
///
/// `end` with the prefix on is exactly the app. `first` has to place the style
/// ahead of the prefix, so it writes the prefix itself and tells the builder
/// not to add it again. An empty subject stays empty, like in the app — a
/// style must never become the whole prompt.
({String prompt, bool builderPrefix}) composeCellPrompt({
  required String subject,
  required String? styleText,
  required String prefix,
  StylePosition position = StylePosition.end,
  bool qualityPrefix = true,
}) {
  if (styleText == null || subject.trim().isEmpty) {
    return (prompt: subject, builderPrefix: qualityPrefix);
  }
  return switch (position) {
    StylePosition.end =>
      (prompt: '$subject, $styleText', builderPrefix: qualityPrefix),
    StylePosition.front =>
      (prompt: '$styleText, $subject', builderPrefix: qualityPrefix),
    StylePosition.first => (
        prompt: [
          styleText,
          if (qualityPrefix && prefix.isNotEmpty) prefix,
          subject,
        ].join(', '),
        builderPrefix: false,
      ),
  };
}

/// The styles one dump renders.
///
/// Without [wanted] that is every candidate, or the whole registry when there
/// is no candidates file. With it, an id the file lacks falls back to the
/// registry — so a candidate can run next to the existing style it might
/// duplicate, under the same seed and reference, in one table. An id found
/// nowhere is an error: silently dropping it would cost the row the run was
/// started for, and that shows only after the GPU time.
List<StylePreset> selectStyles({
  required List<StylePreset>? candidates,
  required List<StylePreset> registry,
  required List<String> wanted,
}) {
  final pool = candidates ?? registry;
  if (wanted.isEmpty) return pool;
  // Pool order first, like before the fallback existed: the table keeps the
  // file's (or the registry's) order rather than the order of the flag.
  final picked = [for (final s in pool) if (wanted.contains(s.id)) s];
  for (final id in wanted) {
    if (picked.any((s) => s.id == id)) continue;
    final fallback = candidates == null
        ? null
        : registry.where((s) => s.id == id).firstOrNull;
    if (fallback == null) {
      throw FormatException(candidates == null
          ? 'styl "$id" není v registru'
          : 'styl "$id" není v kandidátech ani v registru');
    }
    picked.add(fallback);
  }
  return picked;
}

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
