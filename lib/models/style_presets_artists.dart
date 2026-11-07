part of 'style_preset.dart';

/// Styly podle konkrétních umělců; u autorů s víc epochami `autor-období`.
const _kArtistStyles = <StylePreset>[
  StylePreset(
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
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
    kind: StyleKind.artist,
    id: 'josef-capek',
    label: 'Josef Čapek — naivní kubismus',
    block:
        'Czech painting by Josef Capek, blocky simplified figure like a wooden toy, rough thick outlines, chunky flat planes of brick red ochre and grey-blue, childlike naive geometry, coarse matte texture, tender humour',
    booru:
        'naive art, cubism, oil painting (medium), traditional media, blocky, simplified, thick outlines, flat color, red, ochre, grey-blue, wooden, rough, matte, childlike',
    artist: 'Josef Čapek',
    period: 'naivní kubismus 1913–1938',
  ),
  // Vlna 7 (2026-11): změřeno na 17 modelech, výběr uživatele (docs/plan-styles-wave7.md).
  StylePreset(
    kind: StyleKind.artist,
    id: 'durer-engraving',
    label: 'Dürer — mědiryty',
    block:
        'copper engraving by Albrecht Dürer, black ink on cream paper, dense cross-hatching, swelling burin lines, sharp contour, fine parallel modelling, northern renaissance precision, crisp printed plate surface',
    booru:
        'greyscale, monochrome, traditional media, hatching (texture), crosshatching, renaissance, engraving (medium), fine art parody',
    artist: 'Albrecht Dürer',
    period: 'mědirytiny 1500–1520',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'bosch',
    label: 'Bosch — panoramatická alegorie',
    block:
        'oil panel painting by Hieronymus Bosch, high panoramic viewpoint, swarming tiny figures across the surface, pale pink and sea-green palette, thin translucent paint, fantastical hybrid forms, crackled oak panel',
    booru:
        'oil painting (medium), traditional media, surreal, renaissance, wide shot, from above, pink theme, green theme, fine art parody',
    artist: 'Hieronymus Bosch',
    period: '1490–1510',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'bruegel',
    label: 'Bruegel — vesnice z nadhledu',
    block:
        'oil panel painting by Pieter Bruegel the Elder, elevated distant viewpoint, small stocky figures, muted earthy browns with cold grey-green, flat clear daylight, deep receding landscape, thin dry paint on oak panel',
    booru:
        'oil painting (medium), traditional media, renaissance, from above, wide shot, muted colors, brown theme, landscape, fine art parody',
    artist: 'Pieter Bruegel st.',
    period: '1559–1569',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'van-eyck',
    label: 'Van Eyck — lazurový olej',
    block:
        'early netherlandish oil painting by Jan van Eyck, luminous transparent glazes, microscopic detail, jewel-like crimson and deep green, crisp textile folds, cool even light, enamel-smooth panel surface',
    booru:
        'oil painting (medium), traditional media, renaissance, realistic, red theme, green theme, dark background, fine art parody',
    artist: 'Jan van Eyck',
    period: '1430s',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'titian',
    label: 'Tizian — benátský kolorit',
    block:
        'venetian oil painting by Titian, warm glowing colour, deep reds and golden flesh tones, loose broken late brushwork, soft dissolving contours, layered glazes, rough visible canvas weave',
    booru:
        'oil painting (medium), traditional media, renaissance, red theme, orange theme, canvas texture, fine art parody',
    artist: 'Tizian',
    period: 'benátský kolorit 1540–1570',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'caravaggio',
    label: 'Caravaggio — modely ze tmy',
    block:
        'tenebrist oil painting by Caravaggio, single hard raking light from upper left, figures emerging from pure black, ordinary unidealised models, sharp shadow edge, earthy red and ochre, dark smooth canvas',
    booru:
        'oil painting (medium), traditional media, chiaroscuro, black background, dark, realistic, red theme, fine art parody',
    artist: 'Caravaggio',
    period: 'tenebrismus 1600–1610',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'velazquez',
    label: 'Velázquez — stříbřitá paleta',
    block:
        'court portrait painting by Diego Velázquez, silvery grey palette, restrained blacks and rose, loose shorthand brushstrokes that resolve at a distance, airy neutral background, thin fluid oil paint on canvas',
    booru:
        'oil painting (medium), traditional media, grey theme, muted colors, grey background, portrait, fine art parody',
    artist: 'Diego Velázquez',
    period: '1630–1660',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'rubens',
    label: 'Rubens — vířivá kompozice',
    block:
        'flemish baroque oil painting by Peter Paul Rubens, rosy luminous flesh with pearly blue half-tones, swirling diagonal composition, full fleshy forms, warm reds, fluid sweeping brushwork, thin glowing paint',
    booru:
        'oil painting (medium), traditional media, dynamic pose, plump, red theme, orange theme, fine art parody',
    artist: 'Peter Paul Rubens',
    period: '1610–1640',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'fragonard',
    label: 'Fragonard — hravý štětec',
    block:
        'rococo oil painting by Jean-Honoré Fragonard, feathery playful brushwork, pastel pink, peach and sea-green, frothy foliage light, soft powdery atmosphere, swift flickering touches on canvas',
    booru:
        'oil painting (medium), traditional media, pastel colors, pink theme, soft focus, fine art parody',
    artist: 'Jean-Honoré Fragonard',
    period: 'rokoko 1760–1770',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'david-neoclassical',
    label: 'David — neoklasicismus',
    block:
        'neoclassical oil painting by Jacques-Louis David, invisible smooth brushwork, sculptural marble-like bodies, frieze-like shallow stage, hard clear outlines, stern red and white accents, plain dark background, polished canvas',
    booru:
        'oil painting (medium), traditional media, realistic, muscular, red theme, dark background, fine art parody',
    artist: 'Jacques-Louis David',
    period: 'neoklasicismus 1784–1800',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'ingres',
    label: 'Ingres — porcelánová pleť',
    block:
        'neoclassical oil portrait by Jean-Auguste-Dominique Ingres, porcelain smooth skin, elongated sinuous contours, pure unbroken line, cool pale tones, crisp silk surfaces, enamel-like invisible brushwork',
    booru:
        'oil painting (medium), traditional media, realistic, long neck, pale skin, fine art parody',
    artist: 'J.-A.-D. Ingres',
    period: '1808–1856',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'friedrich',
    label: 'Friedrich — mlžná krajina',
    block:
        'german romantic oil painting by Caspar David Friedrich, vast hazy depth, cold grey-blue and violet dusk tones, silhouetted forms against pale sky, still symmetrical composition, thin smooth paint',
    booru:
        'oil painting (medium), traditional media, landscape, fog, silhouette, blue theme, from behind, scenery, fine art parody',
    artist: 'Caspar David Friedrich',
    period: 'romantismus 1818–1830',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'turner',
    label: 'Turner — rozpuštěné světlo',
    block:
        'late oil painting by J. M. W. Turner, forms dissolved into blazing light, swirling vortex of yellow and white, scumbled translucent veils, barely any contour, rough scraped impasto surface',
    booru:
        'oil painting (medium), traditional media, abstract, yellow theme, white theme, light rays, blurry, impasto, fine art parody',
    artist: 'J. M. W. Turner',
    period: 'pozdní 1835–1845',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'blake',
    label: 'Blake — barevné tisky',
    block:
        'colour-printed relief etching by William Blake, elongated muscular figures, flamelike rhythmic outlines, mottled pigment, hand-tinted watercolour washes in ochre and blue, reticulated printed paper surface',
    booru:
        'traditional media, watercolor (medium), print (medium), muscular, yellow theme, blue theme, fine art parody',
    artist: 'William Blake',
    period: '1795–1820',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'hokusai',
    label: 'Hokusai — manga skici',
    block:
        'woodblock sketchbook page by Katsushika Hokusai, nimble calligraphic brush line, black outline with pale grey and soft pink tone, comic candid gesture, sparse empty ground, warm washi paper',
    booru:
        'ukiyo-e, traditional media, sketch, limited palette, pink theme, grey theme, paper texture, simple background, fine art parody',
    artist: 'Kacušika Hokusai',
    period: 'Hokusai manga 1814–1834',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'hiroshige',
    label: 'Hirošige — bokashi',
    block:
        'ukiyo-e woodblock landscape print by Utagawa Hiroshige, bokashi gradient from deep indigo into pale sky, flat colour shapes, thin dark outline, slanting fine line rhythm, soft washi paper grain',
    booru:
        'ukiyo-e, traditional media, gradient background, blue theme, landscape, flat color, paper texture, fine art parody',
    artist: 'Utagawa Hirošige',
    period: '1833–1858',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'yoshitoshi',
    label: 'Jošitoši — poslední ukiyo-e',
    block:
        'meiji woodblock print by Tsukioka Yoshitoshi, dramatic twisting pose, nervous elegant line, restrained muted palette with sudden red accent, sparse gradient ground, fine woodgrain printed on paper',
    booru:
        'ukiyo-e, traditional media, dynamic pose, muted colors, red theme, spot color, gradient background, fine art parody',
    artist: 'Cukioka Jošitoši',
    period: '1880s',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'kuniyoshi',
    label: 'Kunijoši — hrdinské listy',
    block:
        'ukiyo-e warrior print by Utagawa Kuniyoshi, explosive packed composition filling the sheet, bold swirling black line, dense interlocking patterns, saturated red and indigo, heavy muscular action, woodblock ink texture',
    booru:
        'ukiyo-e, traditional media, dynamic pose, muscular, red theme, blue theme, thick lineart, fine art parody',
    artist: 'Utagawa Kunijoši',
    period: '1827–1850',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'manet',
    label: 'Manet — černá jako barva',
    block:
        'oil painting by Édouard Manet, flat frontal light, black used as a full colour, abrupt shift between light and dark, pale simplified flesh, broad summary brushwork, creamy paint on canvas',
    booru:
        'oil painting (medium), traditional media, impressionism, black theme, flat color, pale skin, fine art parody',
    artist: 'Édouard Manet',
    period: '1863–1882',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'renoir',
    label: 'Renoir — skvrny světla',
    block:
        'impressionist oil painting by Pierre-Auguste Renoir, dappled sunlight patches, soft feathery brushstrokes, warm rosy flesh, shimmering blue shadows, blurred contours, creamy vibrating paint surface',
    booru:
        'oil painting (medium), traditional media, impressionism, dappled sunlight, soft focus, pink theme, blue theme, fine art parody',
    artist: 'Pierre-Auguste Renoir',
    period: '1874–1882',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'cassatt',
    label: 'Cassattová — pastel a japonský výřez',
    block:
        'pastel by Mary Cassatt, asymmetric japanese-print cropping, high tilted viewpoint, soft hatched chalk strokes, tender pink and pale green, flat patterned areas, velvety toned paper surface',
    booru:
        'pastel (medium), traditional media, impressionism, cropped, from above, pink theme, green theme, paper texture, fine art parody',
    artist: 'Mary Cassatt',
    period: '1880–1900',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'whistler',
    label: 'Whistler — nokturno',
    block:
        'nocturne by James McNeill Whistler, tonal harmony of blue and silver, thin liquid paint washed across canvas, vague dissolved shapes in fog, near monochrome, sparse flecks of gold, smooth veiled surface',
    booru:
        'oil painting (medium), traditional media, blue theme, grey theme, monochrome, fog, night, fine art parody',
    artist: 'James McNeill Whistler',
    period: 'nokturna 1870s',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'sargent',
    label: 'Sargent — bravurní tah',
    block:
        'portrait painting by John Singer Sargent, long bravura wet brushstrokes, glinting white satin highlights, dark tonal background, elegant loose edges, confident impasto accents on smooth canvas',
    booru:
        'oil painting (medium), traditional media, portrait, realistic, impressionism, dark background, satin, fine art parody',
    artist: 'John Singer Sargent',
    period: '1884–1900',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'sorolla',
    label: 'Sorolla — středomořské slunce',
    block:
        'oil painting by Joaquín Sorolla, blazing mediterranean sunlight, luminous whites with violet shadows, broad fluid wet strokes, sparkling reflections, intense warm-cool contrast, thick loose paint',
    booru:
        'oil painting (medium), traditional media, impressionism, sunlight, white theme, purple theme, impasto, fine art parody',
    artist: 'Joaquín Sorolla',
    period: '1900–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'zorn',
    label: 'Zorn — čtyřbarevná paleta',
    block:
        'oil painting by Anders Zorn, limited palette of ochre, vermilion, ivory black and white, ruddy warm flesh, broad decisive slashing strokes, shimmering rippling light, creamy impasto on canvas',
    booru:
        'oil painting (medium), traditional media, limited palette, impressionism, red theme, brown theme, impasto, fine art parody',
    artist: 'Anders Zorn',
    period: '1890–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'repin',
    label: 'Repin — ruský realismus',
    block:
        'russian realist oil painting by Ilya Repin, psychological character study, weathered faces, sombre browns and grey daylight, solid vigorous brushwork, open-air naturalism, thick earthy canvas surface',
    booru:
        'oil painting (medium), traditional media, realistic, brown theme, muted colors, portrait, fine art parody',
    artist: 'Ilja Repin',
    period: '1870–1890',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'bilibin',
    label: 'Bilibin — ruské pohádky',
    block:
        'russian fairytale illustration by Ivan Bilibin, thick black contour lines, flat watercolour fills, decorative ornamental border, folk embroidery patterns, muted ochre and teal, printed book page surface',
    booru:
        'ink (medium), watercolor (medium), traditional media, art nouveau, border, ornate border, flat color, thick lineart, fine art parody',
    artist: 'Ivan Bilibin',
    period: 'pohádkové ilustrace 1899–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'vrubel',
    label: 'Vrubel — krystalické fasety',
    block:
        'symbolist oil painting by Mikhail Vrubel, crystalline faceted brush planes, mosaic of shattered strokes, deep violet and dusky blue with gleaming pearl, heavy palette-knife impasto',
    booru:
        'oil painting (medium), traditional media, impasto, purple theme, blue theme, art nouveau, dark, fine art parody',
    artist: 'Michail Vrubel',
    period: '1890–1902',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'kirchner',
    label: 'Kirchner — Die Brücke',
    block:
        'german expressionist oil painting by Ernst Ludwig Kirchner, sharp jagged angles, acid pink and poison green, elongated masklike faces, slashing hatched brushstrokes, raw unblended paint',
    booru:
        'oil painting (medium), traditional media, colorful, pink theme, green theme, thick lineart, fine art parody',
    artist: 'Ernst Ludwig Kirchner',
    period: 'Die Brücke 1908–1914',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'marc',
    label: 'Marc — barevné prizmy',
    block:
        'expressionist painting by Franz Marc, prismatic intersecting colour planes, saturated cobalt blue, crimson and yellow, curved rhythmic contours, crystalline fractured space, flat bright oil paint',
    booru:
        'oil painting (medium), traditional media, colorful, abstract, blue theme, yellow theme, fine art parody',
    artist: 'Franz Marc',
    period: '1911–1914',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'klee',
    label: 'Klee — mřížky barev',
    block:
        'painting by Paul Klee, grid of soft glowing colour squares, childlike thin wandering line, hieroglyphic signs, muted warm watercolour washes, dry chalky textured ground',
    booru:
        'watercolor (medium), traditional media, abstract, grid, minimalism, muted colors, paper texture, fine art parody',
    artist: 'Paul Klee',
    period: '1920–1930',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'leger',
    label: 'Léger — trubkové postavy',
    block:
        'painting by Fernand Léger, tubular machine-like figures, thick black outline, flat red, yellow and blue, stark white ground, offset colour bands, smooth poster-flat paint',
    booru:
        'oil painting (medium), traditional media, cubism, thick lineart, limited palette, flat color, fine art parody',
    artist: 'Fernand Léger',
    period: '1920–1950',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'de-chirico',
    label: 'De Chirico — metafyzické náměstí',
    block:
        'metaphysical painting by Giorgio de Chirico, deep empty perspective, long raking shadows, arcades, featureless mannequin forms, dark green-blue sky, hot ochre ground, flat dry paint',
    booru:
        'oil painting (medium), traditional media, surreal, long shadow, perspective, faceless, orange theme, green sky, fine art parody',
    artist: 'Giorgio de Chirico',
    period: 'metafyzická malba 1912–1918',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'miro',
    label: 'Miró — biomorfní znaky',
    block:
        'painting by Joan Miró, floating biomorphic shapes, thin black wire lines, spots of pure red, blue and yellow, scattered star signs, open washed ground, childlike flatness',
    booru:
        'oil painting (medium), traditional media, abstract, surreal, limited palette, flat color, simple background, fine art parody',
    artist: 'Joan Miró',
    period: '1925–1950',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'rousseau',
    label: 'Rousseau — naivní džungle',
    block:
        'naive oil painting by Henri Rousseau, oversized flat layered leaves, dozens of graded greens, stiff frontal figures, crisp hard-edged shapes, dense airless space, smooth enamel paint',
    booru:
        'oil painting (medium), traditional media, green theme, leaf, flat color, foliage, fine art parody',
    artist: 'Henri Rousseau',
    period: '1891–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'ensor',
    label: 'Ensor — masky',
    block:
        'expressionist painting by James Ensor, grotesque masklike faces, acid reds, greens and whites, crowded shallow space, scratchy nervous line, crusted raw impasto',
    booru:
        'oil painting (medium), traditional media, colorful, red theme, green theme, impasto, crowd, fine art parody',
    artist: 'James Ensor',
    period: '1888–1896',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'hammershoi',
    label: 'Hammershøi — šedé ticho',
    block:
        'oil painting by Vilhelm Hammershøi, near monochrome pearl greys, soft cool window light, empty stillness, reduced geometric composition, blurred quiet edges, muted thin dry brushwork',
    booru:
        'oil painting (medium), traditional media, grey theme, monochrome, muted colors, soft focus, sunlight, fine art parody',
    artist: 'Vilhelm Hammershøi',
    period: '1898–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'larsson',
    label: 'Larsson — švédský domov',
    block:
        'watercolour illustration by Carl Larsson, firm flowing ink outline, clear light washes, swedish red and pale green, airy white ground, flat decorative patterning, fresh sunlit paper',
    booru:
        'watercolor (medium), ink (medium), traditional media, art nouveau, red theme, green theme, flat color, fine art parody',
    artist: 'Carl Larsson',
    period: '1895–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'wyspianski',
    label: 'Wyspiański — pastelová secese',
    block:
        'polish art nouveau pastel by Stanisław Wyspiański, sensitive sweeping contour, bare toned paper left unworked, soft blue and ochre chalk strokes, decorative outline, delicate dry powdery texture',
    booru:
        'pastel (medium), traditional media, art nouveau, sketch, blue theme, paper texture, unfinished, fine art parody',
    artist: 'Stanisław Wyspiański',
    period: 'pastely 1895–1907',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'malczewski',
    label: 'Malczewski — polský symbolismus',
    block:
        'polish symbolist oil painting by Jacek Malczewski, hard sharp academic drawing, dry bright daylight, grassy ochre and cold blue, flat theatrical staging, enigmatic stillness, thin precise paint',
    booru:
        'oil painting (medium), traditional media, realistic, surreal, blue theme, yellow theme, fine art parody',
    artist: 'Jacek Malczewski',
    period: '1890–1920',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'beksinski',
    label: 'Beksiński — dystopie',
    block:
        'dystopian oil painting by Zdzisław Beksiński, rust brown and bone ochre haze, crumbling eroded forms, skeletal decay, dry luminous dust, meticulous fine brushwork on hardboard',
    booru:
        'oil painting (medium), traditional media, surreal, brown theme, orange theme, horror (theme), dust, ruins, fine art parody',
    artist: 'Zdzisław Beksiński',
    period: '1970–1985',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'wyeth',
    label: 'Wyeth — tempera',
    block:
        'egg tempera painting by Andrew Wyeth, thousands of fine dry hatched strokes, faded straw and umber, cold pale light, sparse austere composition, chalky matte panel surface',
    booru:
        'painting (medium), traditional media, realistic, muted colors, brown theme, hatching (texture), fine art parody',
    artist: 'Andrew Wyeth',
    period: 'tempera 1948–1970',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'grant-wood',
    label: 'Grant Wood — regionalismus',
    block:
        'american regionalist oil painting by Grant Wood, smooth rounded sculpted forms, hard precise detail, flemish-style polish, soft green and ochre, decorative patterned stippling, enamel-smooth panel surface',
    booru:
        'oil painting (medium), traditional media, realistic, green theme, muted colors, fine art parody',
    artist: 'Grant Wood',
    period: 'regionalismus 1930s',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'jacob-lawrence',
    label: 'Lawrence — ploché tempery',
    block:
        'painting by Jacob Lawrence, casein tempera on hardboard, flat matte colour shapes, angular faceted figures, saturated red, yellow and blue with black, rhythmic repeated forms',
    booru:
        'painting (medium), traditional media, flat color, cubism, limited palette, fine art parody',
    artist: 'Jacob Lawrence',
    period: '1940–1960',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'bearden',
    label: 'Bearden — koláž',
    block:
        'photomontage collage by Romare Bearden, cut magazine photographs and coloured paper, fragmented mismatched faces, abrupt scale shifts, flat torn shapes, visible glue seams',
    booru:
        'collage, traditional media, photo inset, colorful, flat color, torn paper, fine art parody',
    artist: 'Romare Bearden',
    period: 'koláže 1964–1975',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'kehinde-wiley',
    label: 'Wiley — florální pozadí',
    block:
        'portrait painting by Kehinde Wiley, photorealistic frontal figure, saturated ornamental baroque floral wallpaper behind, tendrils growing over the body, glossy oil, crisp high-contrast skin',
    booru:
        'oil painting (medium), portrait, realistic, floral background, patterned background, saturated, fine art parody',
    artist: 'Kehinde Wiley',
    period: '2005–2020',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'kusama',
    label: 'Kusama — puntíky',
    block:
        'painting by Yayoi Kusama, obsessive polka dots covering every surface, repeating infinity net loops, stark yellow and black, hypnotic all-over pattern, flat glossy acrylic',
    booru:
        'polka dot, acrylic paint (medium), traditional media, patterned background, yellow theme, black theme, abstract, fine art parody',
    artist: 'Yayoi Kusama',
    period: '1960–2020',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'murakami',
    label: 'Murakami — superflat',
    block:
        'superflat painting by Takashi Murakami, seamless flat colour, repeating grinning flower pattern, candy rainbow palette, thick clean outline, glossy lacquered surface',
    booru:
        'flat color, flower, patterned background, rainbow, colorful, thick lineart, pop art, fine art parody',
    artist: 'Takashi Murakami',
    period: 'superflat 2000–2015',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'moebius',
    label: 'Moebius — jemná linka',
    block:
        'french comic art by Moebius, fine even pen line, delicate stippling and hatching, soft pastel flat colour, spacious clean composition, airy luminous light, smooth printed paper',
    booru:
        'comic, lineart, pastel colors, flat color, hatching (texture), stippling (texture), science fiction, fine art parody',
    artist: 'Moebius (Jean Giraud)',
    period: '1975–1990',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'frazetta',
    label: 'Frazetta — olejová fantasy',
    block:
        'fantasy oil painting by Frank Frazetta, explosive muscular anatomy, dynamic twisting action, warm umber darkness, glowing flesh against black, loose rapid brushwork, rough canvas',
    booru:
        'oil painting (medium), traditional media, fantasy, muscular, dynamic pose, dark background, brown theme, fine art parody',
    artist: 'Frank Frazetta',
    period: '1965–1980',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'giger',
    label: 'Giger — biomechanika',
    block:
        'biomechanical airbrush painting by H. R. Giger, monochrome grey ink, fused organic and machine forms, ribbed tubular surfaces, smooth sprayed gradients, stencilled edges',
    booru:
        'airbrush (medium), monochrome, greyscale, biomechanical, cyborg, horror (theme), fine art parody',
    artist: 'H. R. Giger',
    period: '1975–1985',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'rackham',
    label: 'Rackham — sépiové pohádky',
    block:
        'edwardian book illustration by Arthur Rackham, sinuous sepia pen line, muted transparent watercolour washes, gnarled knotty contours, dusty brown and grey-green, aged paper',
    booru:
        'ink (medium), watercolor (medium), traditional media, sepia, brown theme, muted colors, paper texture, fine art parody',
    artist: 'Arthur Rackham',
    period: '1905–1920',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'dore',
    label: 'Doré — xylografie',
    block:
        'wood engraving after Gustave Doré, dense parallel hatching, dramatic theatrical light against deep black, sweeping vast depth, black ink on white book paper',
    booru:
        'greyscale, monochrome, traditional media, hatching (texture), crosshatching, high contrast, fine art parody',
    artist: 'Gustave Doré',
    period: '1860–1870',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'sorayama',
    label: 'Sorayama — chrom',
    block:
        'airbrush illustration by Hajime Sorayama, liquid mirror chrome surfaces, razor sharp specular reflections, smooth sprayed gradients, soft studio glow, flawless polished finish',
    booru:
        'airbrush (medium), reflective surface, reflection, shiny, gradient background, fine art parody',
    artist: 'Hajime Sorayama',
    period: '1978–1990',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'burian',
    label: 'Burian — teplý realismus',
    block:
        'illustration by Zdeněk Burian, warm naturalistic realism, broad confident brushwork, rich amber and earth tones, soft atmospheric depth, matte painted book plate surface',
    booru:
        'oil painting (medium), gouache (medium), traditional media, realistic, brown theme, orange theme, fine art parody',
    artist: 'Zdeněk Burian',
    period: '1930–1970',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'born',
    label: 'Born — karikatura',
    block:
        'czech caricature illustration by Adolf Born, tall elongated figures, long noses, scratchy nervous pen line, soft pastel watercolour washes, witty flat staging, grainy paper',
    booru:
        'ink (medium), watercolor (medium), traditional media, long nose, pastel colors, paper texture, fine art parody',
    artist: 'Adolf Born',
    period: '1970–2000',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'trnka',
    label: 'Trnka — loutkové pohádky',
    block:
        'czech fairytale illustration by Jiří Trnka, soft rounded puppet-like figures, tender simple faces, muted warm tempera, gentle folk colour, dreamy blurred background, matte textured paper',
    booru:
        'painting (medium), traditional media, doll, muted colors, soft focus, paper texture, fine art parody',
    artist: 'Jiří Trnka',
    period: '1940–1965',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'ales',
    label: 'Aleš — národní kresba',
    block:
        'czech pen drawing by Mikoláš Aleš, hard firm contour, lunette-like decorative composition, simple sparse hatching, flat folk ornament, restrained ochre tint, sgraffito-like cream surface',
    booru:
        'ink (medium), traditional media, lineart, sepia, ornate border, limited palette, fine art parody',
    artist: 'Mikoláš Aleš',
    period: '1880–1900',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'toyen',
    label: 'Toyen — surrealismus',
    block:
        'czech surrealist painting by Toyen, smoky diffused grey and sand tones, sprayed veiled forms, ghostly dissolving outlines, empty open space, smooth matte canvas surface',
    booru:
        'oil painting (medium), traditional media, surreal, grey theme, muted colors, blurry, fine art parody',
    artist: 'Toyen',
    period: '1930–1950',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'kupka-early',
    label: 'Kupka — spektrum',
    block:
        'symbolist painting by František Kupka, figure modelled in vertical planes of colour, spectral rainbow shifts, thin rhythmic drawn contour, glowing violet and orange, smooth dreamlike paint',
    booru:
        'oil painting (medium), traditional media, abstract, colorful, purple theme, orange theme, fine art parody',
    artist: 'František Kupka',
    period: 'před abstrakcí 1900–1910',
  ),
  StylePreset(
    kind: StyleKind.artist,
    id: 'preisler',
    label: 'Preisler — secesní symbolismus',
    block:
        'czech art nouveau symbolist oil painting by Jan Preisler, muted blue-green and dusky turquoise, soft decorative contours, flattened dreamy space, melancholy stillness, thin matte brushwork',
    booru:
        'oil painting (medium), traditional media, art nouveau, aqua theme, green theme, muted colors, fine art parody',
    artist: 'Jan Preisler',
    period: '1900–1910',
  ),
];
