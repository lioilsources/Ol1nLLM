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
];
