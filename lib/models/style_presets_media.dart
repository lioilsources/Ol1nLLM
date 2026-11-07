part of 'style_preset.dart';

/// Média a techniky — z čeho je obraz, ne odkud pochází.
const _kMediumStyles = <StylePreset>[
  // Vlna 7 (2026-11): změřeno na 17 modelech, výběr uživatele (docs/plan-styles-wave7.md).
  StylePreset(
    kind: StyleKind.medium,
    id: 'oil-impasto',
    label: 'Olej — impasto',
    block:
        'impasto oil painting on canvas, thick ridges of paint, palette knife marks, heavy raised strokes, glossy wet oil sheen',
    booru:
        'oil painting (medium), traditional media, impasto, brush stroke, canvas texture, palette knife, shiny',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'oil-glazing',
    label: 'Olej — lazury (staří mistři)',
    block:
        'oil glazing on dark imprimatura panel, smooth invisible brushwork, translucent layered glazes, sfumato soft edges, fine craquelure varnish surface',
    booru:
        'oil painting (medium), traditional media, soft focus, muted colors, brown theme, realistic, crack',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'oil-alla-prima',
    label: 'Olej — alla prima',
    block:
        'alla prima oil painting on canvas, broad wet-on-wet strokes, colors blending on the surface, unfinished loose edges, bare canvas showing through',
    booru:
        'oil painting (medium), traditional media, brush stroke, canvas texture, blending, unfinished, sketch',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'palette-knife',
    label: 'Špachtle',
    block:
        'palette knife painting on canvas, flat scraped slabs of oil paint, no brush marks, broken planes with sharp ridged edges, thick buttery surface',
    booru:
        'oil painting (medium), traditional media, palette knife, impasto, canvas texture, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'acrylic-flat',
    label: 'Akryl — ploché plochy',
    block:
        'flat acrylic painting on board, even opaque brushwork, saturated colors with crisp hard edges, matte smooth surface without texture',
    booru:
        'acrylic paint (medium), painting (medium), traditional media, flat color, no lineart, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'acrylic-pour',
    label: 'Akryl — lití (fluid art)',
    block:
        'acrylic pour on canvas, poured fluid paint without brush, marbled swirls and cell patterns, metallic pigment veins, glossy resin-like surface',
    booru:
        'acrylic paint (medium), traditional media, swirl, liquid, abstract background, colorful, shiny, dripping',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'watercolor-wet',
    label: 'Akvarel — mokré do mokrého',
    block:
        'wet-on-wet watercolor on cold-press paper, soft loaded brush washes, bleeding edges and pigment blooms, white of the paper preserved, granulating pigment',
    booru:
        'watercolor (medium), traditional media, paper texture, blending, pastel colors, white background, no lineart',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'watercolor-dry',
    label: 'Akvarel — suchý štětec',
    block:
        'dry-brush watercolor on rough paper, scratchy broken strokes, grainy skipped pigment with layered washed shadows, tooth of the paper visible',
    booru:
        'watercolor (medium), traditional media, paper texture, brush stroke, muted colors, sketch',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'watercolor-ink-line',
    label: 'Akvarel s perokresbou',
    block:
        'watercolor and ink line on sketchbook paper, thin loose pen line, light transparent wash overrunning the outlines, white paper left open',
    booru:
        'watercolor (medium), ink (medium), traditional media, lineart, sketch, paper texture, pastel colors',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'gouache',
    label: 'Kvaš',
    block:
        'gouache painting on illustration board, flat opaque brushwork, matte even color with clean poster-like shapes, slightly chalky surface',
    booru:
        'gouache (medium), painting (medium), traditional media, flat color, muted colors, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'egg-tempera',
    label: 'Vaječná tempera',
    block:
        'egg tempera on gessoed wooden panel, fine hatched strokes from a small brush, thin opaque layers, matte dry luminous surface',
    booru:
        'painting (medium), traditional media, hatching (texture), crosshatching, muted colors, wood, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'casein',
    label: 'Kaseinová tempera',
    block:
        'casein painting on board, quick direct brush strokes, soft pastel-toned opaque color, velvety matte surface',
    booru:
        'painting (medium), traditional media, brush stroke, pastel colors, muted colors, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'encaustic',
    label: 'Enkaustika (vosk)',
    block:
        'encaustic painting on wooden panel, molten pigmented wax, scratched incised lines, depth of fused translucent layers, milky waxy sheen',
    booru:
        'painting (medium), traditional media, impasto, scratches, muted colors, wood, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'fresco-buon',
    label: 'Freska',
    block:
        'buon fresco on wet lime plaster, broad brushwork, matte chalky mineral pigments, visible giornata seams, cracked and flaking plaster surface',
    booru:
        'painting (medium), traditional media, wall, muted colors, crack, scratches, pastel colors',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'airbrush',
    label: 'Airbrush',
    block:
        'airbrush illustration on smooth board, no visible strokes, seamless gradients and fine spray falloff, polished chrome-like highlights, 1980s finish',
    booru:
        'airbrush (medium), traditional media, retro artstyle, shiny, reflection, gradient background, lens flare',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'spray-stencil',
    label: 'Sprej přes šablonu',
    block:
        'spray paint through stencil on concrete wall, hard cut edges, fine overspray halo, paint drips, rough surface showing through',
    booru:
        'graffiti, spray paint, high contrast, dripping, paint splatter, concrete, wall, limited palette',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'finger-paint',
    label: 'Malba prsty',
    block:
        'finger painting on paper, visible fingerprints and smeared daubs, no brush marks, saturated childlike poster paint, thick uneven smudges',
    booru:
        'painting (medium), traditional media, smudge, paint, colorful, paper texture, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'miniature-gouache',
    label: 'Miniatura na slonovině',
    block:
        'portrait miniature in watercolor on ivory, tiny stippled brush dots, smooth delicate color, glossy ivory support, oval format',
    booru:
        'painting (medium), traditional media, oval border, miniature, stippling (texture), realistic, border',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'graphite',
    label: 'Tužka',
    block:
        'graphite pencil drawing on white paper, tonal hatching, smudged soft shadows, silver-grey sheen, fine paper grain',
    booru:
        'graphite (medium), traditional media, monochrome, greyscale, sketch, hatching (texture), blending, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'graphite-hard',
    label: 'Tvrdá tužka — technická',
    block:
        'hard pencil technical drawing on white paper, thin even line, visible construction lines, no shading, clean precise edges',
    booru:
        'pencil, graphite (medium), traditional media, lineart, monochrome, sketch, white background, diagram',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'charcoal',
    label: 'Uhel',
    block:
        'charcoal drawing on textured paper, velvety black strokes, smudged tonal masses, kneaded eraser highlights, loose charcoal dust',
    booru:
        'charcoal (medium), traditional media, monochrome, greyscale, sketch, dust, paper texture, smudge',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'conte',
    label: 'Conté / křída na tónovaném papíru',
    block:
        'conte crayon drawing on grey toned paper, black and white chalk strokes, red-brown accents, hatched modelling, paper tone as midtone',
    booru:
        'chalk, traditional media, sketch, grey background, limited palette, hatching (texture), paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'silverpoint',
    label: 'Stříbrná tužka',
    block:
        'silverpoint drawing on warm prepared ground, fine pale silver-grey line, delicate parallel hatching, no erasure or corrections, tarnished subtle surface',
    booru:
        'pencil, traditional media, sketch, hatching (texture), sepia, brown background, lineart, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'ballpoint',
    label: 'Propiska',
    block:
        'ballpoint pen drawing on paper, blue ink, dense cross-hatching, built-up tone from fine strokes, glossy ink sheen in darks',
    booru:
        'ballpoint pen (medium), traditional media, crosshatching, hatching (texture), sketch, blue theme, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'fineliner',
    label: 'Fineliner — perokresba',
    block:
        'fineliner pen drawing on white paper, thin uniform black lines, stippled dots for tone, no washes, crisp clean edges',
    booru:
        'millipen (medium), ink (medium), traditional media, lineart, stippling (texture), monochrome, white background',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'nib-ink',
    label: 'Redispero a tuš',
    block:
        'dip nib pen and india ink on paper, swelling variable line width, dense hatching, ink splatters, hard wet black edges',
    booru:
        'nib pen (medium), ink (medium), traditional media, hatching (texture), crosshatching, ink splatter, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'brush-ink',
    label: 'Štětec a tuš (ne sumi-e)',
    block:
        'brush and black ink on paper, expressive tapered strokes, dry-brush streaks, solid spotted blacks, comic inking edges',
    booru:
        'brush (medium), ink (medium), traditional media, monochrome, high contrast, brush stroke, greyscale',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'marker',
    label: 'Lihové fixy (Copic)',
    block:
        'alcohol marker drawing on smooth paper, flat layered tones, visible overlapping stroke bands, streaky saturated color, white gel pen highlights',
    booru:
        'marker (medium), traditional media, lineart, colorful, blending, white background',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'crayon',
    label: 'Voskovky',
    block:
        'wax crayon drawing on paper, rough grainy strokes, uneven childlike scribbled fill, paper showing through, waxy sheen',
    booru:
        'crayon (medium), traditional media, paper texture, colorful, sketch, white background',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'soft-pastel',
    label: 'Suchý pastel',
    block:
        'soft pastel drawing on toned sanded paper, powdery strokes, finger-blended transitions, velvety chalky color, loose pigment dust',
    booru:
        'pastel (medium), traditional media, blending, pastel colors, paper texture, dust, powder',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'oil-pastel',
    label: 'Olejový pastel',
    block:
        'oil pastel drawing on paper, thick greasy strokes, sgraffito scratched lines, saturated smeared color, waxy glossy surface',
    booru:
        'pastel (medium), crayon (medium), traditional media, scratches, colorful, paper texture, smudge',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'chalkboard',
    label: 'Křída na tabuli',
    block:
        'chalk drawing on blackboard, white and pastel chalk strokes, dusty soft edges, smudged eraser haze, matte black surface',
    booru:
        'chalkboard, chalk, traditional media, dust, black background, sketch, smudge',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'scratchboard',
    label: 'Škrabaná technika',
    block:
        'scratchboard engraving on black clay board, fine white scratched lines, dense directional hatching, stark black ground, engraved sharp surface',
    booru:
        'traditional media, monochrome, black background, hatching (texture), scratches, high contrast, greyscale',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'calligraphy-chinese',
    label: 'Čínská kaligrafie (kchaj-šu)',
    block:
        'chinese regular script calligraphy on xuan paper, angular brush strokes in black ink, vertical columns, red seal stamp, absorbent paper grain',
    booru:
        'calligraphy, calligraphy brush (medium), ink (medium), chinese text, seal impression, traditional media, paper texture, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'calligraphy-cursive',
    label: 'Divoká kurzíva (cchao-šu)',
    block:
        'chinese wild cursive calligraphy on paper, continuous sweeping brush strokes, flying dry-brush streaks, ink spatter, rhythmic linked marks',
    booru:
        'calligraphy, calligraphy brush (medium), ink (medium), cursive, ink splatter, chinese text, traditional media, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'calligraphy-arabic',
    label: 'Arabská kaligrafie (thuluth)',
    block:
        'arabic thuluth calligraphy on burnished paper, elongated strokes from an angled reed pen, gold illuminated ornament, deep blue ink',
    booru:
        'calligraphy, arabic text, ink (medium), traditional media, gold, blue theme, parchment',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'blackletter',
    label: 'Gotická textura (blackletter)',
    block:
        'blackletter textura calligraphy on parchment, broken angular broad-nib strokes, dense black rhythm, red initial capital, slightly rough vellum surface',
    booru:
        'blackletter, calligraphy, ink (medium), traditional media, parchment, monochrome, letter',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'copperplate',
    label: 'Copperplate / anglická kurzíva',
    block:
        'copperplate script on cream paper, pointed nib, hairline upstrokes and swelling downstrokes, looping flourishes, crisp iron-gall ink',
    booru:
        'calligraphy, cursive, nib pen (medium), ink (medium), traditional media, letter, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'brush-lettering',
    label: 'Brush lettering',
    block:
        'brush lettering on paper, flexible brush pen, thick downstrokes and thin upstrokes, watercolor gradient inside strokes, dry streaked ends',
    booru:
        'calligraphy, brush (medium), watercolor (medium), traditional media, cursive, gradient background, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'hangul-calligraphy',
    label: 'Korejská kaligrafie',
    block:
        'korean hangul calligraphy on hanji paper, round circular brush strokes, black ink, soft feathered edges, fibrous mulberry paper surface',
    booru:
        'calligraphy, calligraphy brush (medium), ink (medium), korean text, traditional media, paper texture, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'graffiti-wildstyle',
    label: 'Graffiti wildstyle',
    block:
        'graffiti wildstyle on concrete wall, spray can lines, interlocking lettering with arrows, 3d block shadow, bold outline and fade fills',
    booru:
        'graffiti, spray paint, spray can, concrete, wall, colorful, thick outlines, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'linocut',
    label: 'Linoryt',
    block:
        'linocut print on paper, thick white gouged grooves, solid black ink areas, chattered carving marks, slightly uneven pressed ink',
    booru:
        'traditional media, monochrome, high contrast, lineart, carving, thick outlines, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'etching',
    label: 'Lept',
    block:
        'etching print on cotton paper, fine parallel bitten lines, tone from line density, plate mark border, warm black ink',
    booru:
        'traditional media, monochrome, hatching (texture), crosshatching, sepia, border, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'drypoint',
    label: 'Suchá jehla',
    block:
        'drypoint print on paper, needle-scratched lines, velvety soft burr, rich fuzzy blacks, plate tone haze',
    booru:
        'traditional media, monochrome, scratches, sketch, hatching (texture), sepia, paper texture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'lithograph',
    label: 'Litografie',
    block:
        'lithograph print on paper, greasy crayon strokes, grain of limestone, soft tonal areas, slightly mottled ink surface',
    booru:
        'traditional media, monochrome, sketch, film grain, chalk, paper texture, sepia',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'letterpress',
    label: 'Knihtisk',
    block:
        'letterpress print on thick cotton paper, debossed impression, single ink color, slightly uneven ink density, soft fibrous surface',
    booru:
        'traditional media, limited palette, monochrome, paper texture, scan, flat color',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'monotype',
    label: 'Monotyp',
    block:
        'monotype print on paper, single pressing from inked plate, wiped smeared areas, faint ghost image, soft mottled ink texture',
    booru:
        'traditional media, painting (medium), smudge, blending, muted colors, paper texture, unfinished',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'cyanotype',
    label: 'Kyanotypie',
    block:
        'cyanotype print on watercolor paper, prussian blue tone, white silhouetted shapes, brushed uneven emulsion edges, soft paper grain',
    booru:
        'traditional media, blue theme, monochrome, silhouette, blue background, paper texture, scan artifacts',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'gyotaku',
    label: 'Gyotaku (otisk ryby)',
    block:
        'gyotaku ink rubbing on rice paper, pressed direct impression, scale-like imprinted texture, unprinted blank eye, soft black ink and fibrous paper',
    booru:
        'ink (medium), traditional media, monochrome, ink wash painting, paper texture, stamp mark, greyscale',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'block-print-textile',
    label: 'Dřevěný razítkový tisk na látku',
    block:
        'hand block print on cotton cloth, repeated carved stamp pattern, uneven pressure and ink density, indigo dye, visible woven fabric',
    booru:
        'traditional media, fabric, blue theme, limited palette, stamp mark, polka dot, spot color',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'halftone-newsprint',
    label: 'Novinový rastr',
    block:
        'halftone newspaper print on yellowed newsprint, coarse CMYK dots, slight misregistration, ink show-through, cheap fibrous paper',
    booru:
        'halftone, newspaper, retro artstyle, halftone background, paper texture, sepia, scan artifacts',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'engraving-banknote',
    label: 'Rytina (bankovka)',
    block:
        'banknote intaglio engraving on security paper, guilloche rosette lines, fine cross-hatching, single-color ink, raised crisp linework',
    booru:
        'monochrome, hatching (texture), crosshatching, lineart, traditional media, green theme, border, spiral',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'embroidery',
    label: 'Výšivka',
    block:
        'hand embroidery on linen, dense satin stitches, visible thread sheen, directional stitching following forms, woven cloth showing',
    booru:
        'embroidery, thread, stitching, fabric, sewing, traditional media, shiny',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'cross-stitch',
    label: 'Křížková výšivka',
    block:
        'cross-stitch on aida cloth, tiny x-shaped stitches on a square grid, stepped pixel-like edges, cotton floss, visible cloth holes',
    booru: 'embroidery, thread, pixelated, pixel art, grid, fabric, stitching',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'tapestry-weave',
    label: 'Gobelín',
    block:
        'woven tapestry on loom, visible weft ribs, matte wool colors, stepped jagged shape edges, coarse textile surface',
    booru:
        'tapestry (medium), tapestry, wool, fabric, traditional media, muted colors, thread',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'quilt',
    label: 'Patchwork / quilt',
    block:
        'patchwork quilt, stitched pieces of printed fabric, visible quilting lines, seams between cloth patches, soft padded surface',
    booru: 'quilt, fabric, stitching, sewing, thread, polka dot, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'batik',
    label: 'Batika',
    block:
        'batik on cotton cloth, hot wax resist lines, crackled dye veins, indigo and brown dye, softly bleeding edges',
    booru:
        'batik, fabric, traditional media, blue theme, brown theme, crack, limited palette',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'tie-dye',
    label: 'Batika vázaná',
    block:
        'tie-dye on cotton fabric, bound and dyed folds, spiral radiating rings, bleeding rainbow dye edges, soft cloth surface',
    booru:
        'tie-dye, fabric, spiral, rainbow, rainbow gradient, colorful, swirl',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'felt',
    label: 'Plstění',
    block:
        'needle felted wool, soft fuzzy fibers, rounded puffy shapes, matte heathered wool color, tiny needle dimples',
    booru:
        'felt (medium), wool, fabric, traditional media, 3d, figure (medium), pastel colors',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'knitted',
    label: 'Pletené',
    block:
        'hand knitted wool, rows of stitch loops, cable knit pattern, chunky yarn, soft fuzzy textile surface',
    booru: 'knitting, yarn, wool, crochet, fabric, thread, 3d',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'lace',
    label: 'Krajka',
    block:
        'bobbin lace, fine white openwork threads, delicate looped mesh, pierced negative shapes, on dark background',
    booru:
        'lace, thread, black background, white theme, monochrome, fabric, negative space',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'beadwork-loom',
    label: 'Korálková výšivka',
    block:
        'loom beadwork, shiny glass seed beads in a tight grid, stepped pixel-like edges, reflective rounded surface, visible thread rows',
    booru: 'beads, thread, pixelated, grid, shiny, reflection, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'cardboard',
    label: 'Lepenka',
    block:
        'corrugated cardboard craft, cut ragged edges exposing flutes, brown kraft surface, layered sheets, packing tape joints',
    booru:
        'cardboard, papercraft (medium), brown theme, duct tape, paper, 3d, diorama',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'origami',
    label: 'Origami',
    block:
        'origami folded paper, crisp creases, sharp geometric facets, single sheet of matte washi',
    booru:
        'origami, paper, papercraft (medium), 3d, paper texture, paper crane',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'quilling',
    label: 'Quilling',
    block:
        'paper quilling, rolled coils of thin paper strips, standing on edge, spiral filled shapes, crisp shadowed relief',
    booru: 'papercraft (medium), paper, spiral, swirl, 3d, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'pop-up-book',
    label: 'Vystřelovací kniha',
    block:
        'pop-up book, cut paper flats standing in layered depth, visible fold tabs and creases, printed illustrated card surface',
    booru: 'pop-up book, papercraft (medium), paper, book, diorama, 3d',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'paper-sculpture-layered',
    label: 'Vrstvený papír (paper cut light box)',
    block:
        'layered cut paper light box, stacked silhouette sheets in depth, glowing backlight between layers, soft shadow gradients',
    booru:
        'paper cutout, papercraft (medium), silhouette, backlighting, glowing, diorama, paper',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'kirigami',
    label: 'Kirigami',
    block:
        'kirigami, cut and folded white paper, crisp slit edges, raised geometric planes, soft cast shadows',
    booru: 'kirigami, papercraft (medium), paper, white theme, 3d, shadow',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'sticker-collage',
    label: 'Samolepková koláž',
    block:
        'sticker collage, glossy die-cut stickers, thick white border around each shape, overlapping layers, slight peeling edges',
    booru: 'sticker (medium), sticker, collage, white outline, shiny, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'marble',
    label: 'Mramorová socha',
    block:
        'carved white marble sculpture, faint chisel marks in rough areas, smooth polished transitions, soft stone translucency',
    booru:
        'sculpture, statue, marble (stone), stone, white theme, monochrome, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'bronze',
    label: 'Bronz',
    block:
        'cast bronze sculpture, modelled tool marks, green-brown patina in recesses, polished highlights on raised edges, dark metal surface',
    booru: 'sculpture, statue, bronze, shiny, brown theme, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'terracotta',
    label: 'Terakota',
    block:
        'fired terracotta sculpture, hand-modelled clay marks, brick-red matte body, fine surface cracks',
    booru: 'sculpture, clay, pottery, orange theme, crack, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'wood-carving',
    label: 'Řezba ve dřevě',
    block:
        'hand wood carving, visible gouge marks, faceted cuts, wood grain rings, warm oiled timber surface',
    booru: 'carving, sculpture, wood, brown theme, statue, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'soapstone',
    label: 'Mastek / hladký kámen',
    block:
        'carved soapstone sculpture, rounded smooth simplified forms, faint file marks, grey-green waxy stone surface',
    booru: 'sculpture, stone, statue, green theme, grey theme, realistic',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'ice-sculpture',
    label: 'Ledová socha',
    block:
        'carved ice sculpture, chainsaw and chisel cuts, clear refracting ice, trapped bubbles, cool blue wet surface',
    booru:
        'ice sculpture, ice, frozen, transparent, blue theme, sculpture, reflection',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'sand-sculpture',
    label: 'Pískový reliéf',
    block:
        'sand sculpture relief, packed ochre grains, sharp carved edges, crumbling granular surface',
    booru:
        'sand sculpture, sand, sculpture, brown theme, realistic, orange theme',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'claymation',
    label: 'Plastelína (claymation)',
    block:
        'plasticine claymation, stop-motion puppet look, thumbprints in clay, matte saturated color, slightly lumpy hand-shaped surface',
    booru:
        'clay (medium), clay, figure (medium), 3d, colorful, photo (medium), depth of field',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'porcelain-figurine',
    label: 'Porcelánová figurka',
    block:
        'glazed porcelain figurine, hand-painted pastel enamel colors, gilded trim, smooth glassy glaze highlights',
    booru:
        'porcelain, figure (medium), shiny, pastel colors, gold trim, sculpture, reflection',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'blue-white-porcelain',
    label: 'Modrobílý porcelán',
    block:
        'blue and white porcelain, hand-painted cobalt underglaze, white body, soft pooled brushwork, fine crackle glaze',
    booru:
        'porcelain, pottery, blue theme, white theme, limited palette, shiny, crack',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'ceramic-raku',
    label: 'Raku keramika',
    block:
        'raku ceramic, crackled white glaze, smoke-blackened carbon lines, iridescent metallic copper flashes, rough fired surface',
    booru: 'pottery, crack, smoke, shiny, black theme, sculpture',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'mosaic-tesserae',
    label: 'Mozaika',
    block:
        'mosaic of stone and glass tesserae, small hand-cut cubes, dark grout lines, gold tesserae glints, uneven reflective surface',
    booru:
        'mosaic art, tiles, gold, stone, glass, traditional media, reflection',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'cloisonne',
    label: 'Email cloisonné',
    block:
        'cloisonne enamel, thin gold wire partitions, saturated vitreous color fields, polished glassy surface',
    booru:
        'gold, shiny, thick outlines, flat color, colorful, reflection, glass',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'glass-blown',
    label: 'Foukané sklo',
    block:
        'blown glass, molten-formed transparent body, colored swirling veins, trapped bubbles, sharp specular reflections',
    booru: 'glass, transparent, swirl, reflection, shiny, colorful, crystal',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'wax-figure',
    label: 'Vosková figura',
    block:
        'wax museum figure, translucent waxy skin surface, soft subsurface glow, inserted glass eyes, hand-painted tint',
    booru:
        'figure (medium), statue, realistic, photo (medium), shiny, soft focus',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'wire-sculpture',
    label: 'Drátěná socha',
    block:
        'bent wire sculpture, single thin metal line drawing in space, twisted joints, open contour, crisp cast shadow',
    booru: 'wire, sculpture, lineart, shadow, negative space, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'repousse-metal',
    label: 'Tepaný kov (repoussé)',
    block:
        'repousse metalwork, forms hammered up from thin sheet, small chasing punch marks, burnished gold and copper sheen',
    booru: 'gold, shiny, carving, sculpture, brown theme, reflection',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'daguerreotype',
    label: 'Daguerrotypie',
    block:
        'daguerreotype on mirrored silver plate, long exposure softness, silvery tonal sheen, tarnished edges, oval mat',
    booru:
        'photo (medium), monochrome, greyscale, oval border, vignetting, sepia, film grain',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'tintype',
    label: 'Ferotypie',
    block:
        'tintype wet collodion on dark metal plate, shallow plate focus, chemical streaks and blotches, dull grey-brown tones',
    booru:
        'photo (medium), monochrome, sepia, film grain, vignetting, scratches, dark',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'polaroid',
    label: 'Polaroid',
    block:
        'instant film photograph, white print border, faded washed-out color, soft on-camera flash, slight emulsion blur',
    booru:
        'photo (medium), white border, border, film grain, muted colors, blurry, photo inset',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'lomography',
    label: 'Lomo / cross process',
    block:
        'lomography cross-processed film photograph, heavy vignette, shifted saturated color, blown highlights, light leaks',
    booru:
        'photo (medium), vignetting, film grain, overexposure, colorful, chromatic aberration, high contrast',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'pinhole',
    label: 'Dírková komora',
    block:
        'pinhole camera photograph, soft edgeless focus, long exposure blur, strong corner vignette, muted film grain',
    booru:
        'photo (medium), vignetting, blurry, motion blur, film grain, soft focus, muted colors',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'infrared-film',
    label: 'Infračervený film',
    block:
        'infrared film photograph, near-white glowing greens, blackened blues, soft halation around highlights, coarse grain',
    booru:
        'photo (medium), monochrome, greyscale, film grain, bloom, high contrast, overexposure',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'double-exposure',
    label: 'Dvojexpozice',
    block:
        'double exposure photograph, two translucent overlapping images, second image filling a dark silhouette, soft film blending',
    booru:
        'double exposure, photo (medium), silhouette, transparent, film grain, monochrome background',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'photogram',
    label: 'Fotogram',
    block:
        'photogram on silver gelatin paper, cameraless contact print, white shadow silhouettes on black, soft graded edges',
    booru:
        'monochrome, greyscale, silhouette, black background, inverted colors, white theme, film grain',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'xray',
    label: 'Rentgen',
    block:
        'x-ray radiograph on film, blue-black negative, translucent layered densities, glowing internal structure, soft edges',
    booru:
        'x-ray film, negative, inverted colors, blue theme, black background, transparent, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'thermal',
    label: 'Termokamera',
    block:
        'thermal camera image, false color rainbow heat scale, blurred low-resolution blobs, glowing hot areas on cold blue-purple',
    booru:
        'rainbow gradient, inverted colors, blurry, glowing, purple theme, orange theme, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'low-poly',
    label: 'Low poly',
    block:
        'low poly 3d render, flat triangular facets, hard faceted shading, visible polygon edges',
    booru: 'low poly, 3d, flat color, no lineart, shadow, depth of field',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'vector-flat',
    label: 'Vektor — flat design',
    block:
        'flat vector illustration, clean geometric shapes, solid color fills, no gradients, no outlines',
    booru:
        'vector trace, flat color, no lineart, simple background, limited palette',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'cel-shaded',
    label: 'Cel shading',
    block:
        'cel shaded render, two-step hard shadows, flat paint fills, thick clean black outline',
    booru: 'flat color, thick outlines, black outline, 3d, lineart, colorful',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'ascii-art',
    label: 'ASCII art',
    block:
        'ascii art, monospaced text characters as tone, rows of glyphs, green phosphor on black terminal screen',
    booru:
        'ascii art, terminal, green theme, black background, monochrome, fake screenshot',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'blueprint',
    label: 'Blueprint',
    block:
        'blueprint on cyanotype paper, thin white technical lines, dimension marks, fine grid, deep blue ground',
    booru:
        'blueprint (medium), blue background, blue theme, grid, lineart, diagram, monochrome',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'neon-sign',
    label: 'Neonová reklama',
    block:
        'neon sign, bent glowing glass tubes, single continuous line, colored halo reflecting on wet dark wall',
    booru:
        'neon lights, glowing, black background, dark, reflection, lineart, wall',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'pyrography',
    label: 'Vypalování do dřeva',
    block:
        'pyrography on wood, burnt brown lines, hot-tip shaded gradients, scorched darks, visible wood grain',
    booru:
        'wood, burnt, brown theme, sepia, monochrome, lineart, hatching (texture)',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'marquetry',
    label: 'Intarzie',
    block:
        'wood marquetry, inlaid veneer pieces of different timbers, knife-cut seams, smooth polished lacquer-like surface',
    booru: 'wood, brown theme, flat color, shiny, limited palette, tiles',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'stained-concrete',
    label: 'Beton',
    block:
        'cast concrete, rough grey surface, board-formed imprint lines, air holes and stained seepage',
    booru: 'concrete, grey theme, monochrome, wall, crack, scratches',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'rust-patina',
    label: 'Rez a patina',
    block:
        'rusted metal, flaking orange rust, blue-green verdigris patina, pitted corroded surface',
    booru: 'rust, orange theme, aqua theme, scratches, crack, abstract',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'gingerbread',
    label: 'Perník',
    block:
        'baked gingerbread, brown spiced cookie surface, piped white royal icing lines, sugar decoration, crumbly edges',
    booru: 'gingerbread house, cookie, icing, brown theme, lineart',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'pressed-flowers',
    label: 'Lisované květiny',
    block:
        'pressed flower art on paper, dried translucent petals, flattened glued shapes, faded natural colors, herbarium sheet',
    booru:
        'dried flower, traditional media, collage, paper texture, muted colors, pastel colors',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'sand-painting',
    label: 'Malba pískem',
    block:
        'colored sand painting, poured granular lines, visible mineral grains, flat geometric color fields, matte dry surface',
    booru:
        'sand, traditional media, flat color, limited palette, abstract, brown theme',
  ),
  StylePreset(
    kind: StyleKind.medium,
    id: 'tattoo-flash',
    label: 'Tattoo flash (old school)',
    block:
        'old school tattoo flash on yellowed paper, thick black outline, limited red green yellow palette, whip shading dots, aged sheet',
    booru:
        'thick outlines, black outline, limited palette, flat color, yellow background, traditional media, paper texture',
  ),
];
