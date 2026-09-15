/// Výtvarné styly nabízené vedle promptu.
///
/// Bloky jsou ověřené na serveru, ne vybrané od stolu: prvních 25 prošlo
/// srovnáním 10 modelů × 25 stylů, dalších 15 pak testem „reaguje na to
/// aspoň jeden model?" proti nezastylovanému výchozímu obrázku téhož modelu
/// (viz `docs/style-matrix.md`). 42 stylů podle konkrétních umělců prošlo
/// týmž testem na pěti modelech, už s textem pro každý dialekt zvlášť. Styly,
/// u kterých vyšel jen barevný posun bez převzetí stylu, se sem nedostaly.
/// Text se připojuje **za** uživatelův prompt — vlastní zadání má přednost,
/// blok jen dobarvuje. Na uzlu se persistuje jen [StylePreset.id]: text je
/// z něj a z modelu uzlu odvoditelný, takže se (stejně jako u póz) neukládá
/// dvakrát.
library;

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

class StylePreset {
  const StylePreset({
    required this.id,
    required this.label,
    required this.block,
    this.booru,
    this.artist,
    this.period,
  });

  final String id;
  final String label;

  /// Text připojený za prompt — volná fráze, kterou čte CLIP i T5.
  final String block;

  /// Týž styl v danbooru tazích pro [PromptDialect.booru]. Bez jména umělce:
  /// Pony V6 měl jména v captionech zahashovaná a u Illustrious ani NoobAI
  /// tag umělce v ablaci nepomohl. Null = i booru model dostane [block], takže
  /// styly bez tagové varianty se chovají jako dřív.
  final String? booru;

  /// Autor a období u stylů podle konkrétního malíře. Jen pro UI — sekce
  /// v pickeru a podtitulek; do promptu nejdou. Kulturní styly je nemají.
  final String? artist;
  final String? period;

  /// Text, který dostane model daného dialektu.
  String blockFor(PromptDialect dialect) => switch (dialect) {
    PromptDialect.booru => booru ?? block,
    PromptDialect.natural => block,
  };
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
    booru:
        'codex, mesoamerican, stone relief, black outline, thick outlines, flat color, red theme, turquoise, gold, geometric pattern, sun symbol, feather pattern, traditional media',
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
    booru:
        'kente, african, geometric pattern, patterned background, gold, yellow theme, orange theme, warm colors, symbols, stylized, traditional media',
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
    booru:
        'african, red ochre, earth tones, orange theme, warm lighting, desert, textured, painting (medium), traditional media',
  ),
  StylePreset(
    id: 'maasai',
    label: 'Maasai',
    block:
        'maasai inspired style, bold red and beadwork patterns, elongated elegant figures, strong vertical composition, vibrant contrasting colors',
    booru:
        'african, beadwork, beads, red theme, geometric pattern, vertical composition, vibrant colors, high contrast, stylized, traditional media',
  ),
  StylePreset(
    id: 'aboriginal',
    label: 'Aboriginal dot painting',
    block:
        'australian aboriginal dot painting style, intricate dot patterns, earth pigment colors, x-ray style internal forms, symbolic story elements, flat ceremonial composition',
    booru:
        'aboriginal art, dot painting, pointillism, dots, earth tones, brown theme, orange theme, symbols, abstract, flat color, traditional media',
  ),
  StylePreset(
    id: 'polynesian',
    label: 'Traditional Polynesian',
    block:
        'traditional polynesian style, bold geometric tattoos, strong black outlines, stylized powerful bodies, warm skin tones, carved wood aesthetic',
    booru:
        'polynesian, tribal tattoo, tribal pattern, geometric pattern, black outline, thick outlines, wood carving, warm colors, brown theme, stylized, traditional media',
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
    booru:
        'temple mural, southeast asian, gold, red theme, ornate, flowing lines, glowing, soft lighting, painting (medium), traditional media',
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
    booru:
        'ancient, stone relief, carved, from side, profile, patterned hair, stone texture, brown theme, sepia, stylized, traditional media',
  ),
  StylePreset(
    id: 'arabian',
    label: 'Pre-Islamic Arabian',
    block:
        'pre-islamic arabian style, elegant elongated figures, soft desert tones, flowing drapery, refined facial features, calm monumental presence',
    booru:
        'ancient, desert, brown theme, beige, muted colors, flowing lines, elongated, elegant, soft lighting, painting (medium), traditional media',
  ),
  StylePreset(
    id: 'hebrew',
    label: 'Ancient Near Eastern Hebrew',
    block:
        'ancient near eastern hebrew inspired style, simple strong outlines, modest earth palette, solemn dignified figures, subtle patterned textiles, formal composition',
    booru:
        'ancient, lineart, thick outlines, earth tones, brown theme, muted colors, textile pattern, flat color, solemn, traditional media',
  ),
  StylePreset(
    id: 'indian',
    label: 'Classical Indian miniature',
    block:
        'detailed indian miniature painting, flat vibrant colors, intricate decorative patterns, stylized elongated figures, ornate borders, rich reds and golds',
    booru:
        'indian miniature, miniature painting, gouache (medium), flat color, intricate pattern, ornate border, border, red theme, gold, stylized, traditional media',
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
  // Text Muchova plakátu z třetí vlny: na juggernautu byl původní obecný blok
  // bledá tapeta, Mucha plakát se svatozáří, na ostatních modelech stejné.
  // Id zůstává — je na uzlech.
  StylePreset(
    id: 'artnouveau',
    label: 'Art Nouveau',
    block:
        'art nouveau lithograph poster by Alphonse Mucha, woman framed by a circular halo motif, flowing decorative hair, ornamental mosaic border, pale pastel tones with gold, elegant whiplash lines, stylised flowers, flat poster colours',
    booru:
        'art nouveau, poster, halo, circle, ornate border, mosaic, flowing hair, flower, pastel colors, gold, flat color, thick outlines, elegant, lithograph',
  ),
  StylePreset(
    id: 'egyptian',
    label: 'Ancient Egyptian wall painting',
    block:
        'ancient egyptian wall painting style, strict side profile views, flat bold colors, hierarchical proportions, black outlines, ochre skin tones, hieroglyphic decorative elements, formal composition',
  ),
  StylePreset(
    id: 'byzantine',
    label: 'Byzantská ikona',
    block:
        'byzantine icon style, flat gold leaf ground, elongated solemn figures, stylized drapery folds, red and deep blue robes, hieratic frontal composition',
    booru:
        'byzantine art, religious icon, gold background, tempera, flat color, elongated, stylized, red and blue, symmetry, facing viewer, traditional media',
  ),
  StylePreset(
    id: 'illumination',
    label: 'Iluminovaný rukopis',
    block:
        'medieval illuminated manuscript style, gold leaf, ornate vine border, flat jewel colours, stylized figure inside a decorated initial, vellum texture',
  ),
  StylePreset(
    id: 'stainedglass',
    label: 'Vitráž',
    block:
        'gothic stained glass window style, bold black lead lines, luminous saturated colour panels, flat shapes, backlit glow, geometric tracery',
    booru:
        'stained glass, mosaic, lead lines, black outline, vibrant colors, flat color, backlighting, glowing, geometric pattern, gothic',
  ),
  StylePreset(
    id: 'impressionist',
    label: 'Impresionismus',
    block:
        'impressionist plein air painting, broken brushstrokes, vibrating complementary colours, soft daylight, loose edges, atmospheric immediacy',
  ),
  StylePreset(
    id: 'woodcut',
    label: 'Expresionistický dřevořez',
    block:
        'german expressionist woodcut print, harsh carved lines, stark black and white, angular distorted forms, visible gouge marks, raw emotional energy',
  ),
  StylePreset(
    id: 'artdeco',
    label: 'Art Deco plakát',
    block:
        'art deco poster style, streamlined geometric forms, strong symmetry, metallic gold and black, flat colour blocks, elegant stylized figure',
    booru:
        'art deco, 1920s (style), retro artstyle, poster (medium), geometric, symmetry, gold, black and gold, flat color, streamlined',
  ),
  StylePreset(
    id: 'constructivist',
    label: 'Konstruktivistický plakát',
    block:
        'russian constructivist poster style, bold diagonal composition, red black and cream, geometric shapes, photomontage feel, heavy sans-serif blocks',
    booru:
        'constructivism, soviet poster, poster (medium), diagonal composition, red theme, black and white, geometric shapes, photomontage, limited palette, retro artstyle',
  ),
  StylePreset(
    id: 'secession',
    label: 'Vídeňská secese',
    block:
        'vienna secession style, flat gilded ornament, geometric mosaic patterns, elongated figure, decorative square motifs, gold and muted green',
    booru:
        'vienna secession, art nouveau, gold, gilded, mosaic, geometric pattern, square pattern, ornate, flat color, green and gold, elongated',
  ),
  StylePreset(
    id: 'minoan',
    label: 'Minojská freska',
    block:
        'minoan fresco style, flowing curved contours, terracotta and marine blue, stylized profile with large eye, spiral and wave motifs, plaster texture',
  ),
  StylePreset(
    id: 'thangka',
    label: 'Tibetská thangka',
    block:
        'tibetan thangka painting style, precise symmetrical composition, rich mineral pigments, gold outlines, ornate halo and cloud motifs, flat stylized figures',
  ),
  StylePreset(
    id: 'rinpa',
    label: 'Rinpa zlatý paraván',
    block:
        'japanese rinpa screen style, gold leaf background, bold flat silhouettes, stylized waves and grasses, mineral pigments, decorative asymmetry',
    booru:
        'rinpa, folding screen, japanese art, gold background, gold leaf, flat color, silhouette, stylized waves, grass, asymmetry, traditional media',
  ),
  StylePreset(
    id: 'dunhuang',
    label: 'Dunhuang jeskynní malba',
    block:
        'dunhuang cave mural style, flowing celestial ribbons, ochre and lapis pigments, weathered plaster texture, serene stylized figures, flat halo',
  ),
  StylePreset(
    id: 'minhwa',
    label: 'Korejská minhwa',
    block:
        'korean minhwa folk painting style, flat cheerful colours, naive charming proportions, decorative peonies and tigers motifs, hanji paper texture',
  ),
  StylePreset(
    id: 'papercut',
    label: 'Vystřihovánka',
    block:
        'traditional paper cut style, single flat colour silhouette, intricate symmetrical cutouts, sharp negative space, decorative floral lattice',
    booru:
        'paper cutout, papercraft, silhouette, single color, limited palette, symmetry, negative space, floral pattern, lattice, flat color',
  ),
  StylePreset(
    id: 'huichol',
    label: 'Huichol příze',
    block:
        'huichol yarn painting style, dense parallel yarn lines, vivid contrasting colours, symbolic peyote and deer motifs, flat filled forms',
    booru:
        'yarn art, yarn, string art, parallel lines, vibrant colors, high contrast, psychedelic, symbols, flat color, mexican folk art',
  ),
  // Třetí vlna — styly podle konkrétních umělců, po autorech jako
  // v tools/lab/candidates/artists.json. Zahozené a proč: docs/style-matrix.md.
  StylePreset(
    id: 'davinci',
    label: 'Da Vinci — sfumato portrét',
    block:
        'portrait painting by Leonardo da Vinci, sfumato, soft smoky shadows without hard edges, enigmatic half smile, muted olive umber and dark green palette, hazy distant landscape, high renaissance oil on poplar',
    booru:
        'oil painting (medium), traditional media, renaissance, sfumato, soft shading, muted colors, brown theme, dark green background, faint smile, realistic, fine art parody',
    artist: 'Leonardo da Vinci',
    period: 'sfumato, c. 1490–1510',
  ),
  StylePreset(
    id: 'davinci-chalk',
    label: 'Da Vinci — červená křída (studie)',
    block:
        'red chalk figure study by Leonardo da Vinci, sanguine on toned paper, fine parallel hatching, anatomical precision, unfinished sketch edges, faint mirror handwriting notes in the margin',
    booru:
        'sketch, traditional media, red chalk, sanguine, monochrome, hatching, anatomy study, unfinished, paper texture, renaissance, sepia theme',
    artist: 'Leonardo da Vinci',
    period: 'studie křídou a stříbrnou tužkou',
  ),
  StylePreset(
    id: 'picasso-blue',
    label: 'Picasso — modré období',
    block:
        'blue period painting by Pablo Picasso, monochrome cold blue and blue-green palette, gaunt melancholic figure, elongated hands, hunched posture, flat sombre background, thin dry paint',
    booru:
        'oil painting (medium), traditional media, blue theme, monochrome, melancholy, thin, hunched, elongated hands, flat background, post-impressionism, fine art parody',
    artist: 'Pablo Picasso',
    period: 'modré období 1901–1904',
  ),
  StylePreset(
    id: 'picasso-rose',
    label: 'Picasso — růžové období (harlekýni)',
    block:
        'rose period painting by Pablo Picasso, warm pink ochre and terracotta palette, harlequin diamond costume, circus saltimbanque figure, quiet dignity, flat dusty background, delicate thin paint',
    booru:
        'oil painting (medium), traditional media, pink theme, orange theme, harlequin, checkered clothes, circus, muted colors, flat background, melancholy, fine art parody',
    artist: 'Pablo Picasso',
    period: 'růžové období 1904–1906',
  ),
  StylePreset(
    id: 'picasso-cubist',
    label: 'Picasso — kubistický portrét (Dora Maar)',
    block:
        'cubist portrait by Pablo Picasso, face shown in profile and frontal view at once, both eyes on one side, fractured angular planes, thick black outlines, bold flat red yellow green and purple, patterned wallpaper',
    booru:
        'cubism, abstract face, asymmetrical eyes, angular, thick outlines, flat color, multicolored, geometric, oil painting (medium), traditional media, patterned background, fine art parody',
    artist: 'Pablo Picasso',
    period: 'figurální kubismus 1937–1940',
  ),
  StylePreset(
    id: 'basquiat',
    label: 'Basquiat',
    block:
        'neo-expressionist painting by Jean-Michel Basquiat, raw scrawled figure with skull-like head, three-pointed crown, exposed anatomy lines, graffiti text fragments and crossed-out words, oil stick and acrylic on rough canvas, chaotic bright colours',
    booru:
        'graffiti, scribble, crown, skull, rough sketch, acrylic paint (medium), traditional media, text, crayon (medium), messy, colorful, thick outlines, flat color, naive art',
    artist: 'Jean-Michel Basquiat',
    period: '1981–1983',
  ),
  StylePreset(
    id: 'hockney-pool',
    label: 'Hockney — bazén, ploché akryly',
    block:
        '1960s Los Angeles acrylic painting by David Hockney, flat clean colour fields, turquoise swimming pool with stylised ripples, modernist house and palm trees, crisp shadows, bright even sunlight, deadpan cool stillness',
    booru:
        'acrylic paint (medium), traditional media, flat color, pool, blue theme, palm tree, minimalism, clean lines, sunlight, mid-century, pop art, sharp shadows',
    artist: 'David Hockney',
    period: 'Los Angeles 1964–1972',
  ),
  StylePreset(
    id: 'monet',
    label: 'Monet — figura v plenéru',
    block:
        'plein air painting by Claude Monet, figure with parasol in a windswept meadow, dappled sunlight and moving clouds, loose feathery brushstrokes, lavender and green shadows, bright airy sky, form dissolving in light',
    booru:
        'impressionism, oil painting (medium), traditional media, parasol, meadow, wind, dappled sunlight, painterly, loose brushwork, pastel colors, sky, cloud',
    artist: 'Claude Monet',
    period: 'figury v plenéru, 1870s',
  ),
  StylePreset(
    id: 'kahlo',
    label: 'Frida Kahlo',
    block:
        'self-portrait painting by Frida Kahlo, frontal gaze, joined eyebrows, flowers braided into hair, embroidered Tehuana dress, lush tropical leaves and a small monkey, flat naive Mexican folk retablo style, saturated colours',
    booru:
        'traditional media, oil painting (medium), naive art, thick eyebrows, flower in hair, mexican, embroidery, monkey, leaf background, looking at viewer, flat shading, vivid colors, folk art',
    artist: 'Frida Kahlo',
    period: 'autoportréty 1930–1950',
  ),
  StylePreset(
    id: 'goya-black',
    label: 'Goya — černé malby',
    block:
        'black painting by Francisco Goya, murky black brown and ochre palette, grotesque haunted figure emerging from darkness, wild frantic brushstrokes, gaping mouth and staring eyes, nightmare mural on plaster',
    booru:
        'oil painting (medium), traditional media, dark, black background, brown theme, horror, grotesque, wide-eyed, open mouth, painterly, rough brushwork, nightmare, romanticism',
    artist: 'Francisco Goya',
    period: 'černé malby 1819–1823',
  ),
  StylePreset(
    id: 'goya-caprichos',
    label: 'Goya — Caprichos (lept, akvatinta)',
    block:
        'etching and aquatint by Francisco Goya from Los Caprichos, monochrome sepia print, grainy aquatint shadows, satirical grotesque figure, owls and bats in the gloom, hand-written caption below',
    booru:
        'etching, monochrome, sepia, traditional media, satire, grotesque, owl, bat, dark, grainy, caption, ink (medium), print',
    artist: 'Francisco Goya',
    period: 'Caprichos, lepty 1797–1799',
  ),
  StylePreset(
    id: 'kandinsky-early',
    label: 'Kandinskij — raná pohádková tempera',
    block:
        'early tempera painting by Wassily Kandinsky before abstraction, fairy-tale folk scene, rider in old Russian costume, jewel-like dabs of colour on dark ground, glowing pointillist dots, medieval towers, night blue with gold and crimson',
    booru:
        'tempera (medium), traditional media, fairy tale, russian clothes, horseback riding, dark background, pointillism, glowing, jewel tones, night, castle, folk art, colorful',
    artist: 'Vasilij Kandinskij',
    period: 'pohádkové tempery 1903–1909 (před abstrakcí)',
  ),
  StylePreset(
    id: 'vangogh-arles',
    label: 'Van Gogh — Arles, impasto portrét',
    block:
        'portrait painting by Vincent van Gogh in Arles, thick impasto brushstrokes, vivid complementary colours, yellow and blue, green shadows on the face, flat patterned background, directional hatched strokes following the form, visible paint ridges',
    booru:
        'oil painting (medium), traditional media, impasto, post-impressionism, thick brushstrokes, yellow theme, blue theme, complementary colors, painterly, textured, flat background, visible brushstrokes',
    artist: 'Vincent van Gogh',
    period: 'Arles 1888–1889 (portréty)',
  ),
  StylePreset(
    id: 'vangogh-saintremy',
    label: 'Van Gogh — Saint-Rémy, vířivé tahy',
    block:
        'late painting by Vincent van Gogh in Saint-Rémy, swirling turbulent brushstrokes, spiralling sky and cypress, rhythmic curling lines around the figure, deep blue and glowing yellow, restless energy, thick oil',
    booru:
        'oil painting (medium), traditional media, impasto, swirl, spiral, night sky, cypress, blue theme, yellow theme, post-impressionism, painterly, dynamic brushstrokes',
    artist: 'Vincent van Gogh',
    period: 'Saint-Rémy 1889–1890 (víry)',
  ),
  StylePreset(
    id: 'lautrec-poster',
    label: 'Toulouse-Lautrec — plakát (litografie)',
    block:
        'lithograph poster by Henri de Toulouse-Lautrec, flat bold colour areas, sinuous black silhouette contours, Moulin Rouge dancer, spattered crachis texture, cropped Japanese composition, bold hand-lettered title, ochre red and black',
    booru:
        'poster, lithograph, flat color, thick outlines, silhouette, dancer, can-can, cabaret, art nouveau, limited palette, red, black, text, cropped, ukiyo-e influence',
    artist: 'Henri de Toulouse-Lautrec',
    period: 'litografické plakáty 1891–1896',
  ),
  StylePreset(
    id: 'lautrec-cabaret',
    label: 'Toulouse-Lautrec — kabaret na kartonu',
    block:
        'cabaret painting by Henri de Toulouse-Lautrec, thinned oil on raw cardboard, streaky diagonal strokes, sickly green gaslight on the face, red lips and orange hair, Montmartre bar interior, unfinished sketchy edges, brown cardboard showing through',
    booru:
        'oil painting (medium), traditional media, sketchy, cardboard, streaky, green skin, gaslight, bar, cabaret, post-impressionism, unfinished, brown theme, loose brushwork',
    artist: 'Henri de Toulouse-Lautrec',
    period: 'kabaretní malby 1888–1895',
  ),
  StylePreset(
    id: 'mucha-slav-epic',
    label: 'Mucha — Slovanská epopej',
    block:
        'monumental egg tempera painting by Alphonse Mucha from the Slav Epic, pale luminous blue and white tones, crowd of Slavic figures in linen folk dress, glowing symbolic figure hovering above, misty historical vision, soft muted fresco-like surface',
    booru:
        'tempera (medium), traditional media, pale colors, blue theme, white theme, crowd, folk costume, linen, glowing, floating, mist, historical, symbolism, epic, soft shading',
    artist: 'Alfons Mucha',
    period: 'Slovanská epopej 1910–1928',
  ),
  StylePreset(
    id: 'kubista',
    label: 'Kubišta — kuboexpresionismus',
    block:
        'Czech cubo-expressionist painting by Bohumil Kubista, figure built from sharp crystalline facets, cold blue green and ochre planes, dramatic raking light and deep shadow, tense angular composition, intense staring face, dense heavy oil',
    booru:
        'cubism, expressionism, oil painting (medium), traditional media, angular, geometric, faceted, blue theme, green theme, ochre, dramatic lighting, sharp shadows, intense, staring',
    artist: 'Bohumil Kubišta',
    period: 'kuboexpresionismus 1910–1912',
  ),
  StylePreset(
    id: 'schiele',
    label: 'Schiele',
    block:
        'figure drawing by Egon Schiele, nervous jagged contour line, contorted angular pose, bony elongated hands, gouache and watercolour patches of orange red and sickly green on bare paper, empty white background, raw expressionist intensity',
    booru:
        'expressionism, watercolor (medium), traditional media, sketch, jagged lines, contorted, bony, long fingers, thin, white background, orange, green skin, angular, nude, unfinished',
    artist: 'Egon Schiele',
    period: '1910–1918',
  ),
  StylePreset(
    id: 'klimt-golden',
    label: 'Klimt — zlaté období',
    block:
        'golden period painting by Gustav Klimt, figure wrapped in a flat gold leaf robe of spirals and rectangles, realistic softly painted face and hands, mosaic ornament, byzantine gold background, embrace, jewel colours',
    booru:
        'art nouveau, gold, gold leaf, mosaic, spiral pattern, ornate, flat pattern, realistic face, jewel tones, hug, traditional media, oil painting (medium), decorative',
    artist: 'Gustav Klimt',
    period: 'zlaté období 1901–1909',
  ),
  StylePreset(
    id: 'vermeer',
    label: 'Vermeer',
    block:
        'painting by Johannes Vermeer, soft daylight from a window on the left, pearl earring and turban, ultramarine and lemon yellow, quiet domestic interior, pointillé highlights, calm serene stillness, smooth Dutch golden age oil',
    booru:
        'oil painting (medium), traditional media, baroque, window light, soft lighting, pearl earring, turban, blue theme, yellow theme, indoors, calm, realistic, smooth shading',
    artist: 'Johannes Vermeer',
    period: 'Delft 1660s',
  ),
  StylePreset(
    id: 'botticelli',
    label: 'Botticelli',
    block:
        'early renaissance tempera painting by Sandro Botticelli, graceful linear contours, long flowing golden hair, pale porcelain skin, transparent fluttering drapery, flowers and orange grove, gentle wistful expression, delicate pastel palette',
    booru:
        'tempera (medium), traditional media, renaissance, long hair, wavy hair, blonde hair, pale skin, see-through, flowing dress, flower, orange tree, pastel colors, elegant, lineart, soft shading',
    artist: 'Sandro Botticelli',
    period: '1480s (Zrození Venuše, Primavera)',
  ),
  StylePreset(
    id: 'elgreco',
    label: 'El Greco',
    block:
        'mannerist painting by El Greco, dramatically elongated flame-like figure, upturned ecstatic eyes, cold flickering light, stormy grey sky, acid green crimson and silver, restless swirling drapery, spiritual intensity',
    booru:
        'oil painting (medium), traditional media, mannerism, elongated, thin, looking up, dramatic lighting, stormy sky, grey theme, green, red, flowing robe, dynamic, religious',
    artist: 'El Greco',
    period: 'Toledo 1580–1614',
  ),
  StylePreset(
    id: 'munch',
    label: 'Munch',
    block:
        'expressionist painting by Edvard Munch, anxious figure, wavy undulating brushstrokes flowing through sky and ground, blood orange sky over dark blue fjord, hollow skull-like face, thinly scrubbed paint, existential dread',
    booru:
        'expressionism, oil painting (medium), traditional media, wavy lines, orange sky, blue theme, fjord, skull-like face, scared, thin paint, painterly, dramatic',
    artist: 'Edvard Munch',
    period: '1892–1900 (Výkřik, Madona)',
  ),
  StylePreset(
    id: 'matisse-fauve',
    label: 'Matisse — fauvismus',
    block:
        'fauvist painting by Henri Matisse, wild unmixed colour, green stripe down the face, red and turquoise flat planes, loose broad brushstrokes, decorative patterned interior, joyful bold simplicity',
    booru:
        'fauvism, oil painting (medium), traditional media, vivid colors, green skin, red theme, flat color, bold brushstrokes, patterned background, simplified, colorful, painterly',
    artist: 'Henri Matisse',
    period: 'fauvismus 1905–1910',
  ),
  StylePreset(
    id: 'matisse-cutout',
    label: 'Matisse — výstřižky (Modrý akt)',
    block:
        'paper cut-out by Henri Matisse, figure as a single flat cobalt blue silhouette cut from gouache-painted paper, simplified curving limbs, white background, scissors-cut edges, leaf and star shapes, jazz-like playfulness',
    booru:
        'paper cutout, flat color, silhouette, blue theme, white background, simplified, minimalism, curves, leaf, star, collage, abstract, playful',
    artist: 'Henri Matisse',
    period: 'papírové výstřižky 1943–1954',
  ),
  StylePreset(
    id: 'gauguin',
    label: 'Gauguin — Tahiti',
    block:
        'Tahitian painting by Paul Gauguin, flat cloisonné colour areas with dark outlines, saturated warm ochre pink and violet, tropical foliage, calm monumental figure, matte chalky surface, symbolist stillness',
    booru:
        'post-impressionism, oil painting (medium), traditional media, flat color, thick outlines, warm colors, pink, purple, tropical, dark skin, calm, matte, symbolism',
    artist: 'Paul Gauguin',
    period: 'Tahiti 1891–1903',
  ),
  StylePreset(
    id: 'cezanne',
    label: 'Cézanne',
    block:
        'painting by Paul Cezanne, figure built from patches of parallel constructive brushstrokes, blue-green ochre and grey-violet palette, solid geometric volumes, slightly tilted perspective, calm weighty stillness',
    booru:
        'post-impressionism, oil painting (medium), traditional media, hatching, patchy, blue theme, green theme, geometric, sculptural, muted colors, still, painterly',
    artist: 'Paul Cézanne',
    period: '1890s (Hráči karet, Koupající se)',
  ),
  StylePreset(
    id: 'seurat',
    label: 'Seurat — pointilismus',
    block:
        'pointillist painting by Georges Seurat, entire image built from tiny dots of pure colour, stiff formal figures in profile, sunny riverside park, optical mixing, calm frozen geometry, soft shimmering surface',
    booru:
        'pointillism, oil painting (medium), traditional media, dots, stippling, profile, park, riverside, sunny, stiff, formal, shimmering, pastel colors',
    artist: 'Georges Seurat',
    period: 'pointilismus 1884–1891',
  ),
  StylePreset(
    id: 'hopper',
    label: 'Hopper',
    block:
        'painting by Edward Hopper, solitary figure in a quiet room or diner, hard raking morning sunlight, long geometric shadows, muted greens and ochres, large window, american realism, melancholy urban stillness',
    booru:
        'oil painting (medium), traditional media, realism, solo, indoors, window, sunlight, sharp shadows, muted colors, green theme, lonely, diner, quiet, americana',
    artist: 'Edward Hopper',
    period: '1927–1960',
  ),
  StylePreset(
    id: 'warhol',
    label: 'Warhol — sítotisk',
    block:
        'pop art silkscreen portrait by Andy Warhol, high-contrast photo reduced to flat blocks, misregistered neon colour fills, hot pink turquoise and yellow, repeated grid of the same face, halftone grain, flat glossy celebrity icon',
    booru:
        'pop art, silkscreen, high contrast, flat color, neon colors, pink, cyan, yellow, repeated, grid, halftone, misaligned, portrait, poster',
    artist: 'Andy Warhol',
    period: 'sítotisky 1962–1967 (Marilyn)',
  ),
  StylePreset(
    id: 'lichtenstein',
    label: 'Lichtenstein — komiksové rastry',
    block:
        'pop art painting by Roy Lichtenstein, enlarged comic strip panel, Ben-Day dot shading, thick black outlines, primary red yellow and blue, dramatic close-up face, speech bubble with bold text, flat printed look',
    booru:
        'pop art, comic, halftone, dots, thick outlines, primary colors, red, yellow, blue, flat color, close-up, speech bubble, text, retro, 1960s',
    artist: 'Roy Lichtenstein',
    period: 'pop art 1961–1965',
  ),
  StylePreset(
    id: 'haring',
    label: 'Haring',
    block:
        'painting by Keith Haring, figure as a thick black outline pictogram, radiant motion lines around the body, flat bright red yellow and blue, dancing pose, dense playful pattern, subway chalk graffiti energy',
    booru:
        'thick outlines, flat color, pictogram, simplified, motion lines, red, yellow, blue, dancing, pattern, graffiti, pop art, no face, bold',
    artist: 'Keith Haring',
    period: '1982–1989',
  ),
  StylePreset(
    id: 'bacon',
    label: 'Francis Bacon',
    block:
        'painting by Francis Bacon, smeared distorted figure with blurred twisting face, seated inside a thin drawn cage of lines, flat orange or violet ground, raw fleshy pinks, isolated on a bare stage, visceral unease',
    booru:
        'expressionism, oil painting (medium), traditional media, distorted, blurry face, smeared, twisted, sitting, cage, lines, orange background, flat background, flesh, disturbing',
    artist: 'Francis Bacon',
    period: '1949–1975',
  ),
  StylePreset(
    id: 'rivera',
    label: 'Rivera — mexický murál',
    block:
        'mural fresco by Diego Rivera, monumental rounded figure with simplified solid volumes, Mexican worker or calla lily seller, earthy terracotta ochre and green, flat matte surface, social realism, crowded composition',
    booru:
        'fresco, mural, traditional media, mexican, rounded, sculptural, simplified, calla lily, worker, earth tones, orange, green, flat shading, social realism, crowd',
    artist: 'Diego Rivera',
    period: 'mexické murály 1923–1935',
  ),
  StylePreset(
    id: 'chagall',
    label: 'Chagall',
    block:
        'dreamlike painting by Marc Chagall, floating lovers drifting over a village, upside-down cow and fiddler, glowing cobalt blue and crimson, soft translucent layers, folk fairy tale, weightless joy',
    booru:
        'surreal, oil painting (medium), traditional media, floating, flying, couple, village, cow, violin, blue theme, red, translucent, dreamy, folk art, whimsical',
    artist: 'Marc Chagall',
    period: '1911–1950',
  ),
  StylePreset(
    id: 'dali',
    label: 'Dalí — surrealismus',
    block:
        'surrealist painting by Salvador Dali, figure in a vast empty desert plain under a clear sky, melting soft forms propped on crutches, long shadows, ants and drawers, hyper-smooth academic rendering, uncanny dream logic',
    booru:
        'surreal, oil painting (medium), traditional media, desert, melting, crutch, long shadows, drawer, ant, clear sky, realistic, smooth shading, dream, empty background',
    artist: 'Salvador Dalí',
    period: 'surrealismus 1931–1945',
  ),
  StylePreset(
    id: 'magritte',
    label: 'Magritte',
    block:
        'surrealist painting by Rene Magritte, bowler hat and dark overcoat, face hidden behind a floating green apple, cloudy blue daytime sky, flat deadpan illustrative rendering, uncanny calm, clean smooth paint',
    booru:
        'surreal, oil painting (medium), traditional media, bowler hat, black coat, apple, covered face, blue sky, cloud, flat shading, clean, calm, deadpan',
    artist: 'René Magritte',
    period: '1926–1966',
  ),
  StylePreset(
    id: 'lempicka',
    label: 'Lempicka — art deco portrét',
    block:
        'art deco portrait by Tamara de Lempicka, glossy metallic sculpted figure, streamlined drapery in silver green and scarlet, sharp geometric shading, skyscraper backdrop, cool glamorous stare, polished tubular volumes',
    booru:
        'art deco, oil painting (medium), traditional media, metallic, glossy, streamlined, sculptural, geometric shading, green, red, skyscraper, glamorous, smooth shading, 1920s',
    artist: 'Tamara de Lempicka',
    period: 'art deco portréty 1925–1935',
  ),
  StylePreset(
    id: 'beardsley',
    label: 'Beardsley — perokresba',
    block:
        'pen and ink illustration by Aubrey Beardsley, stark black and white, large flat black areas against blank white, single sinuous ink line, peacock and rose ornament, decadent elegant figure, japanese asymmetry',
    booru:
        'ink (medium), lineart, monochrome, black and white, high contrast, flat black, thin lines, art nouveau, peacock, rose, elegant, decorative, asymmetrical',
    artist: 'Aubrey Beardsley',
    period: 'perokresby 1893–1898',
  ),
  StylePreset(
    id: 'lada',
    label: 'Lada — česká lidová ilustrace',
    block:
        'Czech folk illustration by Josef Lada, round-faced jolly figure with rosy cheeks, thick black outlines, flat cheerful colours, snowy village with pointed roofs, naive childlike proportions, gentle humour, gouache',
    booru:
        'illustration, naive art, thick outlines, flat color, round face, blush, chubby, village, snow, cottage, cheerful, childlike, gouache (medium), folk art',
    artist: 'Josef Lada',
    period: 'lidová ilustrace 1920–1957',
  ),
  StylePreset(
    id: 'josef-capek',
    label: 'Josef Čapek — naivní kubismus',
    block:
        'Czech painting by Josef Capek, blocky simplified figure like a wooden toy, rough thick outlines, chunky flat planes of brick red ochre and grey-blue, childlike naive geometry, coarse matte texture, tender humour',
    booru:
        'naive art, cubism, oil painting (medium), traditional media, blocky, simplified, thick outlines, flat color, red, ochre, grey-blue, wooden, rough, matte, childlike',
    artist: 'Josef Čapek',
    period: 'naivní kubismus 1913–1938',
  ),
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

/// Hledání v pickeru: [query] proti labelu a autorovi, bez ohledu na velikost
/// písmen a diakritiku — „zrzavy" najde Zrzavého, „cezanne" Cézanna.
bool styleMatchesQuery(StylePreset style, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  return _fold(style.label).contains(q) ||
      (style.artist != null && _fold(style.artist!).contains(q));
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
