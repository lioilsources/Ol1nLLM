/// Výtvarné styly nabízené vedle promptu.
///
/// Bloky jsou ověřené na serveru, ne vybrané od stolu: prvních 25 prošlo
/// srovnáním 10 modelů × 25 stylů, dalších 15 pak testem „reaguje na to
/// aspoň jeden model?" proti nezastylovanému výchozímu obrázku téhož modelu
/// (viz `docs/style-matrix.md`). 42 stylů podle konkrétních umělců prošlo
/// týmž testem na pěti modelech, už s textem pro každý dialekt zvlášť. Styly,
/// u kterých vyšel jen barevný posun bez převzetí stylu, se sem nedostaly.
/// Vlna 7 přidala 228 stylů (57 kultur, 61 umělců, 110 médií), změřených na
/// všech 17 modelech; o vyřazení rozhodl uživatel nad archy, ne metrika.
/// Text se připojuje **za** uživatelův prompt — vlastní zadání má přednost,
/// blok jen dobarvuje. Na uzlu se persistuje jen [StylePreset.id]: text je
/// z něj a z modelu uzlu odvoditelný, takže se (stejně jako u póz) neukládá
/// dvakrát.
library;

import 'style_quiet.dart';

part 'style_presets_artists.dart';
part 'style_presets_cultures.dart';
part 'style_presets_media.dart';

/// Jak model čte text stylu — rozhoduje, který text styl pošle
/// ([StylePreset.blockFor]). Nastavuje se výslovně na [ImageModelSpec].
///
/// Dvě hodnoty, ne tři: v ablaci třetí vlny (`docs/style-matrix.md`) FLUX (T5)
/// přečetl blok psaný pro CLIP stejně dobře jako přirozenou větu, kdežto anime
/// modely z danbooru tagů styl převzaly výrazně líp než z téhož popisu ve
/// frázích.
enum PromptDialect {
  /// Volná fráze — CLIP (SDXL base finetune, SD 1.5) i T5 (FLUX).
  natural,

  /// Danbooru tagy — Pony, Illustrious a anime SDXL finetuny.
  booru,
}

/// Co styl popisuje — sekce v pickeru. Umělec je autor, kultura místo a doba,
/// médium materiál obrazu.
enum StyleKind {
  culture('Kultury a epochy'),
  artist('Umělci'),
  medium('Média a techniky');

  const StyleKind(this.label);

  final String label;
}

class StylePreset {
  const StylePreset({
    this.kind = StyleKind.culture,
    required this.id,
    required this.label,
    required this.block,
    this.booru,
    this.artist,
    this.period,
    this.year,
  });

  final StyleKind kind;
  final String id;
  final String label;

  /// Text připojený za prompt — volná fráze, kterou čte CLIP i T5.
  final String block;

  /// Týž styl v danbooru tazích pro [PromptDialect.booru]. Bez jména umělce:
  /// Pony V6 měl jména v captionech zahashovaná a u Illustrious ani NoobAI
  /// tag umělce v ablaci nepomohl. Null = i booru model dostane [block], takže
  /// styly bez tagové varianty se chovají jako dřív.
  final String? booru;

  /// Autor a období u stylů podle konkrétního malíře. Jen pro UI — hledání
  /// a podtitulek; do promptu nejdou. Kulturní styly je nemají.
  final String? artist;
  final String? period;

  /// Řazení v pickeru: u umělce rok narození, u kultury přibližný začátek
  /// (př. n. l. záporně). Jen pro UI; média ho nemají a řadí se podle abecedy.
  final int? year;

  /// [label] s rokem na konci, jak ho ukazuje picker: „Vermeer (1632)“,
  /// „Jeskynní malba (Lascaux) (17 000 př. n. l.)“. Média rok nemají.
  String get labelWithYear {
    final y = year;
    if (y == null) return label;
    return y < 0 ? '$label (${_thousands(-y)} př. n. l.)' : '$label ($y)';
  }

  /// Text, který dostane model daného dialektu.
  ///
  /// Tagy se escapují až tady, ne v registru: ten zůstává čitelný danbooru
  /// slovník, ale ComfyUI by `oil painting (medium)` přečetlo jako `oil
  /// painting` + `medium` s vahou 1.1 a tag by se nikdy nepotkal.
  String blockFor(PromptDialect dialect) => switch (dialect) {
    PromptDialect.booru => escapeTagParens(booru ?? block),
    PromptDialect.natural => block,
  };
}

/// [tags] se závorkami zapsanými tak, aby je parser vah v ComfyUI nechal být.
/// Už escapovaná závorka se nedotkne, takže opakované volání nic nezmění.
String escapeTagParens(String tags) =>
    tags.replaceAllMapped(RegExp(r'(?<!\\)[()]'), (m) => '\\${m[0]}');

const kStylePresets = <StylePreset>[
  ..._kCultureStyles,
  ..._kArtistStyles,
  ..._kMediumStyles,
];

/// [kStylePresets] v pořadí pickeru: kultury a umělci podle [StylePreset.year]
/// (při shodě drží pořadí registru, takže období jednoho autora jdou po sobě),
/// média podle české abecedy. Registr sám zůstává v pořadí měření.
final List<StylePreset> kStylePresetsSorted = () {
  final indexed = kStylePresets.indexed.toList();
  indexed.sort((a, b) {
    final (ia, sa) = a;
    final (ib, sb) = b;
    if (sa.kind != sb.kind) return sa.kind.index - sb.kind.index;
    final byKey = sa.kind == StyleKind.medium
        ? compareCzech(sa.label, sb.label)
        : (sa.year ?? 0).compareTo(sb.year ?? 0);
    return byKey != 0 ? byKey : ia - ib;
  });
  return List<StylePreset>.unmodifiable(indexed.map((e) => e.$2));
}();

/// 25000 → „25 000“; čtyřmístné roky (1632) se neoddělují, jak je v češtině
/// zvykem.
String _thousands(int n) {
  if (n < 10000) return '$n';
  final s = '$n';
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u00a0');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Česká abeceda bez locale balíku: háčková písmena za základním, „ch“ za
/// „h“; čárka a kroužek rozhodují až při jinak shodných řetězcích.
int compareCzech(String a, String b) {
  final ka = _czechKey(a), kb = _czechKey(b);
  for (var i = 0; i < ka.length && i < kb.length; i++) {
    if (ka[i] != kb[i]) return ka[i] - kb[i];
  }
  final byLength = ka.length - kb.length;
  return byLength != 0 ? byLength : a.compareTo(b);
}

List<int> _czechKey(String s) {
  final lower = _foldAcuteRing(s.toLowerCase());
  final key = <int>[];
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    if (c == 'c' && i + 1 < lower.length && lower[i + 1] == 'h') {
      key.add('h'.codeUnitAt(0) * 4 + 2);
      i++;
    } else if (_hacek.containsKey(c)) {
      key.add(_hacek[c]!.codeUnitAt(0) * 4 + 1);
    } else {
      key.add(c.codeUnitAt(0) * 4);
    }
  }
  return key;
}

const _hacek = {'č': 'c', 'ř': 'r', 'š': 's', 'ž': 'z'};

String _foldAcuteRing(String s) {
  const from = 'áéěíóúůýďťň';
  const to = 'aeeiouuydtn';
  final buf = StringBuffer();
  for (final unit in s.split('')) {
    final i = from.indexOf(unit);
    buf.write(i < 0 ? unit : to[i]);
  }
  return buf.toString();
}

StylePreset? styleById(String? id) {
  if (id == null) return null;
  for (final s in kStylePresets) {
    if (s.id == id) return s;
  }
  return null;
}

/// Prompt + text stylu v dialektu modelu. Prázdný prompt zůstane prázdný
/// (foto root), aby se styl nestal jediným obsahem zadání.
///
/// Text je odvozený z (styleId, dialekt modelu) a obojí je na uzlu
/// (`styleId`, `modelId`), takže retry i export zůstávají deterministické.
String applyStyle(
  String prompt,
  String? styleId, {
  PromptDialect dialect = PromptDialect.natural,
  bool front = false,
}) => applyStylePreset(
  prompt,
  styleById(styleId),
  dialect: dialect,
  front: front,
);

/// Same rule, but for a preset the caller already holds — the lab vets style
/// candidates that are not (yet) in [kStylePresets], and looking them up by id
/// would silently drop their text.
///
/// [front] puts the block ahead of the prompt. Repose does that: the lab's
/// restyle runs moved the picture 2–4× more with the style in front, because
/// a style at the end lands in the CLIP chunk with the least weight.
String applyStylePreset(
  String prompt,
  StylePreset? style, {
  PromptDialect dialect = PromptDialect.natural,
  bool front = false,
}) {
  if (style == null || !styleApplies(prompt, style)) return prompt;
  final block = style.blockFor(dialect);
  return front ? '$block, $prompt' : '$prompt, $block';
}

/// Whether [applyStylePreset] adds [style] to [prompt] at all — not on an
/// empty prompt. Anything that depends on a style going out asks this, not
/// whether one is selected.
bool styleApplies(String prompt, StylePreset? style) =>
    style != null && prompt.trim().isNotEmpty;

/// Restyle (the app's repose, the lab's restyle flow) puts the style in front
/// of the prompt: in the lab's runs it moved the picture 2–4× more there,
/// because a style at the end lands in the CLIP chunk with the least weight.
/// Every other flow appends it.
const bool kRestyleStyleInFront = true;

/// True when the lab saw [modelId] paint the same picture with [styleId] as
/// without it ([kStyleQuietOn], `tools/lab/reactions.py`). A pair that was
/// never measured is not quiet: an unmeasured style is shown as usual, the
/// same rule as a LoRA of unknown family.
bool styleQuietOn(String? styleId, String modelId) =>
    styleId != null && (kStyleQuietOn[modelId]?.contains(styleId) ?? false);

/// Models to suggest when a style is quiet on the current one, in the order
/// the matrix ranked their willingness to take a style (`docs/style-matrix.md`:
/// sdxl-base repaints the whole picture even for a medium, Juggernaut has the
/// widest range, schnell holds styles well).
const kStyleFallbackModels = [
  'sdxl-base',
  'juggernaut-xl',
  'juggernaut-xl-lightning',
  'flux-schnell',
];

/// The first fallback that is available, is not [modelId] and is not quiet on
/// [styleId] itself; null when none qualifies.
String? styleAlternativeModel(
  String styleId,
  String modelId,
  Iterable<String> availableIds,
) {
  final available = availableIds.toSet();
  for (final id in kStyleFallbackModels) {
    if (id != modelId && available.contains(id) && !styleQuietOn(styleId, id)) {
      return id;
    }
  }
  return null;
}

/// Hledání v pickeru: [query] proti labelu, autorovi a období, bez ohledu na
/// velikost písmen a diakritiku — „zrzavy" najde Zrzavého, „cezanne" Cézanna,
/// „1920" autory z té doby.
bool styleMatchesQuery(StylePreset style, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  return _fold(style.labelWithYear).contains(q) ||
      (style.artist != null && _fold(style.artist!).contains(q)) ||
      (style.period != null && _fold(style.period!).contains(q));
}

// Precomposed letters only, so every accented character is one code unit and
// its index lines up with the plain one.
const _accented = 'áäàâãåčćçďéěëèêíïìîľĺňñóöòôõřŕšśťúůüùûýÿžź';
const _plain = 'aaaaaacccdeeeeeiiiillnnooooorrsstuuuuuyyzz';

/// Lower-case without Czech/Slovak/common diacritics — shared by the style and
/// hairstyle pickers' search.
String foldDiacritics(String s) => _fold(s);

String _fold(String s) {
  final buf = StringBuffer();
  for (final unit in s.toLowerCase().split('')) {
    final i = _accented.indexOf(unit);
    buf.write(i < 0 ? unit : _plain[i]);
  }
  return buf.toString();
}
