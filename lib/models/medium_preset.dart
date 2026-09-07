import 'style_preset.dart';

/// Render medium — **čím je obraz zhotovený**, deklarované jako vlastní osa
/// a postavené na začátek promptu.
///
/// Osa vznikla z konkrétního selhání. Stylové bloky v [kStylePresets] samy
/// medium jmenují („woodblock print", „stone relief"), ale jen jako vlečnou
/// větu uvnitř výčtu, který jinak popisuje paletu a motivy. Stylová matice
/// (`docs/style-matrix.md`) zaznamenala následek: tradice, jejichž celé
/// tvrzení *je* medium (asyrský, mezopotámský, hebrejský reliéf), spadnou na
/// většině modelů na béžovou stěnu — model si vezme barvu a způsob vykreslení
/// zahodí.
///
/// Hypotéza je převzatá z Tsumiki (`MangaPrompts`, `blocks/medium.yaml`),
/// která má **25 stylových bloků znak po znaku shodných** s tímhle repem a na
/// tomtéž korpusu došla ke stejnému závěru: medium musí být vlastní,
/// **dopředu umístěná** osa, ne vlečná věta. Dopředu proto, že FLUX/T5 i CLIP
/// váží rané tokeny nejvíc — stejný důvod, proč se řetězený img2img prompt
/// skládá od nejnovějšího (viz „Prompt chaining" v CLAUDE.md).
///
/// Bloky jsou proto **ortogonální ke stylu**: říkají jen jak je to udělané,
/// nikdy odkud to je. Blok, který by jmenoval tradici nebo paletu, by se
/// s [kStylePresets] pral a A/B by měřilo dvě změny naráz.
///
/// Osa je zatím **experiment, ne doporučení**. Jestli deklarované medium
/// béžovou stěnu opravdu rozbije, rozhodne A/B v FINETUNE gallery
/// (`?group=medium`, kontrolní rameno `medium=none`). Do té doby appka žádné
/// medium nepředvolí.
class MediumPreset {
  const MediumPreset({
    required this.id,
    required this.label,
    required this.block,
  });

  /// Id se persistuje na uzlu a exportuje do galerie, takže se nepřejmenovává.
  /// Prefix `medium_` drží jmenný prostor oddělený od [StylePreset.id] —
  /// v galerii jsou obě osy sloupce téhož řádku.
  final String id;
  final String label;

  /// Text postavený **před** prompt. Začíná členem („a woodblock print…"),
  /// protože uvozuje celé zadání, ne dobarvuje jeho konec.
  final String block;
}

/// Šest ramen, ne čtrnáct: osa má rozdělit prostor „jak je to vykreslené",
/// ne vyjmenovat materiály. Materiál, který nese jen jedna tradice (mozaika,
/// vitráž, tapiserie), patří do jejího stylového bloku — jako samostatné
/// rameno by dostal příliš málo hodnocení na to, aby z něj šel udělat závěr.
const kMediumPresets = <MediumPreset>[
  MediumPreset(
    id: 'medium_photoreal',
    label: 'Fotografie',
    block:
        'a photorealistic photograph, true-to-life detail, natural skin '
        'texture, realistic lighting and depth of field',
  ),
  MediumPreset(
    id: 'medium_illustration',
    label: 'Ilustrace',
    block:
        'a drawn illustration, deliberate linework, flat stylised shapes, '
        'no photographic depth of field',
  ),
  MediumPreset(
    id: 'medium_painting',
    label: 'Malba',
    block:
        'a painting, visible brushwork and pigment texture, edges built by the '
        'brush rather than by focus, painted surface throughout',
  ),
  MediumPreset(
    id: 'medium_ink',
    label: 'Kresba tuší',
    block:
        'an ink drawing, forms built from brush and pen strokes, dry-brush and '
        'hatching for tone, large areas of bare paper',
  ),
  MediumPreset(
    id: 'medium_relief',
    label: 'Reliéf',
    block:
        'a carved relief, the whole image cut into a solid surface at shallow '
        'depth, raking light casting real shadows off every carved edge, tool '
        'marks and material grain across the face of it',
  ),
  MediumPreset(
    id: 'medium_print',
    label: 'Tisk z desky',
    block:
        'a printed impression on paper, carved block and engraved lines, flat '
        'unmodulated ink areas, tone made only of lines and dots, absorbent '
        'paper texture',
  ),
];

MediumPreset? mediumById(String? id) {
  if (id == null) return null;
  for (final m in kMediumPresets) {
    if (m.id == id) return m;
  }
  return null;
}

/// Blok media + prompt + blok stylu, v tomhle pořadí.
///
/// Jediné místo, kde se efektivní prompt skládá. Vzniklo s osou media — dvě
/// volitelné přípony volané na šesti místech se rozejdou, a pak už nejde říct,
/// co která buňka v matici opravdu poslala.
///
/// **Bez media je výsledek znak po znaku shodný s [applyStyle]** — to je celý
/// smysl kontrolního ramene A/B: `medium=none` musí být přesně to, co appka
/// posílala předtím, jinak se neporovnává medium, ale dvě různé změny naráz.
/// Drží to test v `test/medium_preset_test.dart`.
String composePrompt(String prompt, {String? styleId, String? mediumId}) =>
    composePromptWith(
      prompt,
      style: styleById(styleId),
      medium: mediumById(mediumId),
    );

/// Totéž pro presety, které volající už drží — lab prověřuje kandidáty, kteří
/// v registrech (zatím) nejsou, a hledání podle id by jejich text tiše zahodilo.
String composePromptWith(
  String prompt, {
  StylePreset? style,
  MediumPreset? medium,
}) {
  final styled = applyStylePreset(prompt, style);
  // Prázdný prompt zůstane prázdný (foto root) — stejné pravidlo jako u stylu:
  // medium samo o sobě není zadání, a jako jediný obsah by z reference udělalo
  // generování.
  if (medium == null || styled.trim().isEmpty) return styled;
  return '${medium.block}, $styled';
}
