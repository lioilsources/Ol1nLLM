/// Výtvarné styly nabízené vedle promptu.
///
/// Bloky jsou ověřené na serveru: každý z nich prošel srovnáním 10 modelů ×
/// 25 stylů (viz `docs/style-matrix.md`). Text se připojuje **za** uživatelův
/// prompt — vlastní zadání má přednost, blok jen dobarvuje. Na uzlu se
/// persistuje jen [StylePreset.id]: blok je z něj odvoditelný, takže se
/// (stejně jako u póz) neukládá dvakrát.
class StylePreset {
  const StylePreset({
    required this.id,
    required this.label,
    required this.block,
  });

  final String id;
  final String label;

  /// Text připojený za prompt.
  final String block;
}

const kStylePresets = <StylePreset>[
  StylePreset(
    id: 'maya',
    label: 'Classic Maya mural / relief',
    block:
        'classic maya mural style, formal profile and three-quarter views, intricate geometric patterns, jade green and deep red colors, hieroglyphic decorative elements, stylized proportions',
  ),
  StylePreset(
    id: 'aztec',
    label: 'Aztec codex / stone relief',
    block:
        'aztec codex and stone relief style, bold black outlines, vibrant red turquoise and gold accents, geometric feather and sun motifs, formal stylized figures',
  ),
  StylePreset(
    id: 'inca',
    label: 'Inca textile and goldwork',
    block:
        'inca textile and goldwork inspired style, precise geometric patterns, rich gold and deep red tones, formal frontal composition, stylized strong bodies',
  ),
  StylePreset(
    id: 'ledger',
    label: 'Plains ledger art',
    block:
        'plains ledger art style, bold outlines, flat colors, dynamic movement lines, symbolic geometric patterns, earth tones with bright accents',
  ),
  StylePreset(
    id: 'ashanti',
    label: 'Ashanti (Ghana)',
    block:
        'ashanti inspired style, rich gold tones, geometric textile patterns, strong stylized figures, decorative symbols, warm earth and gold palette',
  ),
  StylePreset(
    id: 'dogon',
    label: 'Dogon (Mali)',
    block:
        'dogon sculptural style, elongated stylized figures, abstract geometric forms, strong vertical lines, earthy wood-like tones, ritualistic presence',
  ),
  StylePreset(
    id: 'himba',
    label: 'Himba (Namibia)',
    block:
        'himba inspired style, rich red ochre skin tones, minimal clothing emphasis, strong natural anatomy, warm desert light, textured skin details',
  ),
  StylePreset(
    id: 'maasai',
    label: 'Maasai',
    block:
        'maasai inspired style, bold red and beadwork patterns, elongated elegant figures, strong vertical composition, vibrant contrasting colors',
  ),
  StylePreset(
    id: 'aboriginal',
    label: 'Aboriginal dot painting',
    block:
        'australian aboriginal dot painting style, intricate dot patterns, earth pigment colors, x-ray style internal forms, symbolic story elements, flat ceremonial composition',
  ),
  StylePreset(
    id: 'polynesian',
    label: 'Traditional Polynesian',
    block:
        'traditional polynesian style, bold geometric tattoos, strong black outlines, stylized powerful bodies, warm skin tones, carved wood aesthetic',
  ),
  StylePreset(
    id: 'filipino',
    label: 'Traditional Filipino',
    block:
        'traditional filipino style, intricate weaving patterns, soft warm colors, graceful elongated figures, decorative textile motifs',
  ),
  StylePreset(
    id: 'burmese',
    label: 'Burmese temple painting',
    block:
        'traditional burmese temple painting style, flowing elegant lines, rich gold and red tones, ornate decorative details, soft idealized faces, luminous atmosphere',
  ),
  StylePreset(
    id: 'assyrian',
    label: 'Assyrian palace relief',
    block:
        'assyrian palace relief style, strong black outlines, low-relief shading, formal profile views, detailed hair and beard patterns, monumental composition',
  ),
  StylePreset(
    id: 'mesopotamian',
    label: 'Mesopotamian relief',
    block:
        'mesopotamian relief style, composite profile views, formal hierarchical proportions, detailed patterned hair, carved stone texture, earthy tones',
  ),
  StylePreset(
    id: 'arabian',
    label: 'Pre-Islamic Arabian',
    block:
        'pre-islamic arabian style, elegant elongated figures, soft desert tones, flowing drapery, refined facial features, calm monumental presence',
  ),
  StylePreset(
    id: 'hebrew',
    label: 'Ancient Near Eastern Hebrew',
    block:
        'ancient near eastern hebrew inspired style, simple strong outlines, modest earth palette, solemn dignified figures, subtle patterned textiles, formal composition',
  ),
  StylePreset(
    id: 'indian',
    label: 'Classical Indian miniature',
    block:
        'detailed indian miniature painting, flat vibrant colors, intricate decorative patterns, stylized elongated figures, ornate borders, rich reds and golds',
  ),
  StylePreset(
    id: 'ukiyoe',
    label: 'Ukiyo-e woodblock',
    block:
        'ukiyo-e style, bold black outlines, flat color areas, elegant curved lines, stylized hair and clothing folds, limited color palette, japanese woodblock print aesthetic',
  ),
  StylePreset(
    id: 'chineseink',
    label: 'Chinese ink wash',
    block:
        'traditional chinese ink wash painting, flowing black ink brushstrokes, minimal color, elegant empty space, soft gradients, expressive line work, misty atmosphere',
  ),
  StylePreset(
    id: 'romanfresco',
    label: 'Roman fresco',
    block:
        'roman fresco style, soft pastel colors, slightly weathered texture, classical drapery, calm idealized faces, muted earth and ochre palette, wall-painting look',
  ),
  StylePreset(
    id: 'greek',
    label: 'Classical Greek',
    block:
        'classical greek inspired painting, idealized muscular anatomy, clean marble-like skin, balanced composition, soft drapery folds, harmonious proportions, muted earth tones',
  ),
  StylePreset(
    id: 'persian',
    label: 'Persian miniature',
    block:
        'persian miniature style, highly detailed decorative patterns, rich jewel tones, flattened perspective, elegant elongated figures, intricate clothing and background ornaments',
  ),
  StylePreset(
    id: 'baroque',
    label: 'Dramatic Baroque',
    block:
        'dramatic baroque painting, strong chiaroscuro lighting, deep shadows, rich dark colors, dynamic composition, emotional intensity, detailed fabric folds',
  ),
  StylePreset(
    id: 'artnouveau',
    label: 'Art Nouveau',
    block:
        'art nouveau style, flowing organic lines, decorative floral motifs, elegant elongated figures, soft pastel colors, ornamental details, graceful curves',
  ),
  StylePreset(
    id: 'egyptian',
    label: 'Ancient Egyptian wall painting',
    block:
        'ancient egyptian wall painting style, strict side profile views, flat bold colors, hierarchical proportions, black outlines, ochre skin tones, hieroglyphic decorative elements, formal composition',
  ),
];

StylePreset? styleById(String? id) {
  if (id == null) return null;
  for (final s in kStylePresets) {
    if (s.id == id) return s;
  }
  return null;
}

/// Prompt + blok stylu. Prázdný prompt zůstane prázdný (foto root), aby se
/// styl nestal jediným obsahem zadání.
String applyStyle(String prompt, String? styleId) {
  final style = styleById(styleId);
  if (style == null || prompt.trim().isEmpty) return prompt;
  return '$prompt, ${style.block}';
}
