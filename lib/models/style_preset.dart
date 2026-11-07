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
}) => applyStylePreset(prompt, styleById(styleId), dialect: dialect);

/// Same rule, but for a preset the caller already holds — the lab vets style
/// candidates that are not (yet) in [kStylePresets], and looking them up by id
/// would silently drop their text.
String applyStylePreset(
  String prompt,
  StylePreset? style, {
  PromptDialect dialect = PromptDialect.natural,
}) {
  if (style == null || prompt.trim().isEmpty) return prompt;
  return '$prompt, ${style.blockFor(dialect)}';
}

/// Hledání v pickeru: [query] proti labelu, autorovi a období, bez ohledu na
/// velikost písmen a diakritiku — „zrzavy" najde Zrzavého, „cezanne" Cézanna,
/// „1920" autory z té doby.
bool styleMatchesQuery(StylePreset style, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  return _fold(style.label).contains(q) ||
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
