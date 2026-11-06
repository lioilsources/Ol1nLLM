import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;

import '../models/style_preset.dart' show foldDiacritics;

/// One picture of a style map: where it sits on the grid and what it stands
/// for. [tag] is the prompt fragment the picker hands back (an artist tag, a
/// character) — empty for the set's baseline picture.
class StyleMapImage {
  const StyleMapImage({
    required this.index,
    required this.id,
    required this.label,
    required this.tag,
    this.styleId,
    this.modelId,
    required this.col,
    required this.row,
    required this.cluster,
    required this.route,
    required this.features,
    this.tags = const {},
    this.words = const [],
  });

  final int index;
  final String id;
  final String label;
  final String tag;

  /// Registry ids the picture was made with (`kStylePresets`, `kImageModels`),
  /// when the set's source knew them. A pick with a [styleId] sets the style
  /// instead of pasting text.
  final String? styleId;
  final String? modelId;
  final int col;
  final int row;
  final int cluster;

  /// Position on the 1D route through the set (scrub / autoplay): the
  /// pipeline's `tour` — the order with the softest cuts between pictures —
  /// or, in a pack built without it, the Hilbert curve over the grid.
  final int route;

  /// Normalised 0–1, aligned with [StyleMapPack.axes].
  final List<double> features;

  /// Facet key → value id ([StyleMapPack.facets]): the model, the medium, and
  /// what a VLM said about the picture where the set has been tagged.
  final Map<String, String> tags;

  /// The VLM's free keywords — searched, never shown as chips.
  final List<String> words;

  factory StyleMapImage.fromJson(Map<String, dynamic> j) {
    final cell = j['cell'] as List;
    return StyleMapImage(
      index: j['i'] as int,
      id: j['id'] as String,
      label: j['label'] as String? ?? '',
      tag: j['tag'] as String? ?? '',
      styleId: j['style'] as String?,
      modelId: j['model'] as String?,
      col: cell[0] as int,
      row: cell[1] as int,
      cluster: j['cluster'] as int? ?? 0,
      route: j['tour'] as int? ?? j['hilbert'] as int? ?? 0,
      features: [
        for (final v in j['f'] as List? ?? const []) (v as num).toDouble(),
      ],
      tags: {
        for (final e
            in (j['tags'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: e.value as String,
      },
      words: [for (final w in j['words'] as List? ?? const []) w as String],
    );
  }
}

class StyleMapAxis {
  const StyleMapAxis(this.key, this.label);
  final String key;
  final String label;
}

class StyleMapCluster {
  const StyleMapCluster({
    required this.id,
    required this.label,
    required this.size,
    required this.color,
  });
  final int id;
  final String label;
  final int size;
  final Color color;
}

/// Something the pictures of a set can be filtered by, with the values the
/// set actually has.
class StyleMapFacet {
  const StyleMapFacet(this.key, this.label, this.values);
  final String key;
  final String label;
  final List<StyleMapFacetValue> values;
}

class StyleMapFacetValue {
  const StyleMapFacetValue(this.id, this.label, this.count);
  final String id;
  final String label;
  final int count;
}

/// A search text and, per facet, the values that pass. A picture has to
/// satisfy every facet that has a choice (any one of its values) and contain
/// every word of the text.
class StyleMapFilter {
  const StyleMapFilter({this.query = '', this.values = const {}});

  final String query;
  final Map<String, Set<String>> values;

  bool get isEmpty =>
      query.trim().isEmpty && values.values.every((v) => v.isEmpty);

  StyleMapFilter toggled(String key, String id) {
    final next = {...?values[key]};
    if (!next.remove(id)) next.add(id);
    return StyleMapFilter(query: query, values: {...values, key: next});
  }

  StyleMapFilter withQuery(String q) =>
      StyleMapFilter(query: q, values: values);

  /// [textOf] is everything about a picture worth searching that the pack
  /// does not carry itself — the names the caller gives its registry ids.
  bool matches(
    StyleMapImage im,
    StyleMapPack pack, {
    String Function(StyleMapImage)? textOf,
  }) {
    for (final e in values.entries) {
      if (e.value.isNotEmpty && !e.value.contains(im.tags[e.key])) return false;
    }
    final words = foldDiacritics(
      query.trim(),
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = foldDiacritics(
      [
        im.label,
        im.tag,
        ?im.styleId,
        ?im.modelId,
        ...im.words,
        for (final f in pack.facets)
          for (final v in f.values)
            if (im.tags[f.key] == v.id) v.label,
        ?textOf?.call(im),
      ].join(' '),
    );
    return words.every(hay.contains);
  }
}

/// A slice of the wheel: the pictures of one cluster, or of one hue.
class StyleMapSector {
  const StyleMapSector({
    required this.label,
    required this.color,
    required this.images,
    required this.start,
    required this.sweep,
  });

  final String label;
  final Color color;

  /// In playing order, so sliding across the sector's grid is smooth too.
  final List<StyleMapImage> images;

  /// Where the slice sits on the ring, in turns: 0 is the top, clockwise.
  final double start;
  final double sweep;

  bool holds(double turn) => turn >= start && turn < start + sweep;
}

/// The grid a sector's pictures are laid out on inside the wheel: as close
/// to a square as cells of the pack's shape allow.
class StyleMapSectorGrid {
  StyleMapSectorGrid(this.count, double cellAspect)
    : cols = math.max(1, math.sqrt(count / cellAspect).ceil());

  final int count;
  final int cols;
  int get rows => (count / cols).ceil();

  /// The picture under a point of the grid ([u], [v] in 0–1), or null on the
  /// unfilled end of the last row.
  int? at(double u, double v) {
    final col = (u * cols).floor().clamp(0, cols - 1);
    final row = (v * rows).floor().clamp(0, rows - 1);
    final k = row * cols + col;
    return k < count ? k : null;
  }
}

/// What picking a picture means to the caller: a prompt fragment, a style
/// preset, or both — plus the model the picture was made on.
class StyleMapPick {
  const StyleMapPick({required this.tag, this.styleId, this.modelId});

  StyleMapPick.of(StyleMapImage im)
    : tag = im.tag,
      styleId = im.styleId,
      modelId = im.modelId;

  final String tag;
  final String? styleId;
  final String? modelId;

  /// The set's baseline picture carries nothing to apply.
  bool get isEmpty => tag.isEmpty && styleId == null;
}

/// A style map as the pipeline in `tools/stylemap` wrote it (`map.json`): a
/// grid with one picture per cell, laid out so that neighbours look alike.
///
/// The pack knows nothing about where its pictures are served from — paths are
/// relative and the service resolves them — so the same manifest works from a
/// LAN dev server and from the gallery.
class StyleMapPack {
  StyleMapPack({
    required this.id,
    required this.title,
    required this.cols,
    required this.rows,
    required this.cellSize,
    required this.atlasPath,
    required this.thumbPattern,
    required this.images,
    required this.axes,
    required this.clusters,
    this.facets = const [],
  }) : _grid = _index(images, cols, rows);

  final String id;
  final String title;
  final int cols;
  final int rows;

  /// Pixel size of one cell in the atlas.
  final Size cellSize;
  final String atlasPath;

  /// Relative path of a preview, `{i}` standing for [StyleMapImage.index].
  final String thumbPattern;
  final List<StyleMapImage> images;
  final List<StyleMapAxis> axes;
  final List<StyleMapCluster> clusters;
  final List<StyleMapFacet> facets;

  /// cell → image index, -1 for a cell the set did not fill.
  final List<int> _grid;

  /// Width / height of the whole mosaic.
  double get aspect => (cols * cellSize.width) / (rows * cellSize.height);

  static List<int> _index(List<StyleMapImage> images, int cols, int rows) {
    final grid = List<int>.filled(cols * rows, -1);
    for (var k = 0; k < images.length; k++) {
      final im = images[k];
      final inside =
          im.col >= 0 && im.col < cols && im.row >= 0 && im.row < rows;
      if (inside) grid[im.row * cols + im.col] = k;
    }
    return grid;
  }

  /// The same map with only the pictures that pass [test]: their cells stay
  /// where they were and the others become holes, so the mosaic, the route,
  /// the pad and the wheel all narrow down without knowing a filter exists.
  StyleMapPack where(bool Function(StyleMapImage) test) => StyleMapPack(
    id: id,
    title: title,
    cols: cols,
    rows: rows,
    cellSize: cellSize,
    atlasPath: atlasPath,
    thumbPattern: thumbPattern,
    images: [
      for (final im in images)
        if (test(im)) im,
    ],
    axes: axes,
    clusters: clusters,
    facets: facets,
  );

  /// The picture closest to a cell — where the selection lands when a filter
  /// takes its picture away.
  StyleMapImage nearestTo(int col, int row) => images.reduce((a, b) {
    int d(StyleMapImage m) =>
        (m.col - col) * (m.col - col) + (m.row - row) * (m.row - row);
    return d(a) <= d(b) ? a : b;
  });

  StyleMapImage? at(int col, int row) {
    if (col < 0 || col >= cols || row < 0 || row >= rows) return null;
    final k = _grid[row * cols + col];
    return k < 0 ? null : images[k];
  }

  /// The picture under a point of the mosaic, [u] and [v] in 0–1.
  ///
  /// Outside the mosaic the point is clamped to its edge, so a finger that
  /// slides off keeps the last row or column instead of losing the selection.
  /// An empty cell answers null — the caller keeps what it had.
  StyleMapImage? atUnit(double u, double v) => at(
    (u * cols).floor().clamp(0, cols - 1),
    (v * rows).floor().clamp(0, rows - 1),
  );

  /// The pictures in the cells sharing an edge with [im]'s.
  Iterable<StyleMapImage> neighbours(StyleMapImage im) sync* {
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final n = at(im.col + dc, im.row + dr);
      if (n != null) yield n;
    }
  }

  /// The pictures in playing order ([StyleMapImage.route]).
  late final List<StyleMapImage> route = [...images]
    ..sort((a, b) => a.route.compareTo(b.route));

  late final Map<int, int> _routePosition = {
    for (var k = 0; k < route.length; k++) route[k].index: k,
  };

  /// Where [im] sits in [route]. Not [StyleMapImage.route] itself: a pack
  /// with pictures taken out has gaps in those numbers.
  int routePosition(StyleMapImage im) => _routePosition[im.index] ?? 0;

  /// The picture [steps] further along [route], wrapping at both ends.
  StyleMapImage routeFrom(StyleMapImage im, int steps) =>
      route[(routePosition(im) + steps) % route.length];

  /// Index of an axis in [axes] (and in [StyleMapImage.features]), -1 when the
  /// pack does not have it.
  int axis(String key) => axes.indexWhere((a) => a.key == key);

  /// Where [im] sits on a pad spanned by two axes, in 0–1 with the high end
  /// of [y] at the top.
  Offset padPoint(StyleMapImage im, int x, int y) =>
      Offset(im.features[x], 1 - im.features[y]);

  /// The picture nearest a point of the pad. The pad has no cells — two
  /// pictures can sit on the same spot and whole corners can be empty — so
  /// the finger always gets the closest one.
  StyleMapImage nearestOnPad(int x, int y, Offset at) {
    var best = images.first;
    var bestD = double.infinity;
    for (final im in images) {
      final d = (padPoint(im, x, y) - at).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = im;
      }
    }
    return best;
  }

  /// One sector per cluster, as wide as the cluster is large.
  late final List<StyleMapSector> clusterSectors = _sectors([
    for (final c in clusters)
      (
        c.label,
        c.color,
        [
          for (final im in route)
            if (im.cluster == c.id) im,
        ],
      ),
  ]);

  static const _hueNames = [
    'červená', 'oranžová', 'žlutá', 'žlutozelená', 'zelená', 'smaragdová', //
    'tyrkysová', 'azurová', 'modrá', 'fialová', 'purpurová', 'růžová',
  ];

  /// One sector per dominant hue, round the colour wheel, and a grey one for
  /// the pictures that have no dominant hue at all. Empty without the hue
  /// axes.
  late final List<StyleMapSector> hueSectors = () {
    final hue = axis('hue'), conc = axis('hue_conc'), sat = axis('sat');
    if (hue < 0 || conc < 0 || sat < 0) return const <StyleMapSector>[];
    final n = _hueNames.length;
    final bins = [for (var k = 0; k <= n; k++) <StyleMapImage>[]];
    for (final im in route) {
      final f = im.features;
      final plain = f[conc] < 0.15 || f[sat] < 0.08;
      bins[plain ? n : (f[hue] * n).round() % n].add(im);
    }
    return _sectors([
      for (var k = 0; k < n; k++)
        (
          _hueNames[k],
          HSVColor.fromAHSV(1, 360 * k / n, 0.7, 0.9).toColor(),
          bins[k],
        ),
      ('bez převládající barvy', const Color(0xFF8A8A8A), bins[n]),
    ]);
  }();

  /// Slices as wide as they are full, but never too thin to touch.
  static List<StyleMapSector> _sectors(
    List<(String, Color, List<StyleMapImage>)> groups,
  ) {
    final full = [
      for (final g in groups)
        if (g.$3.isNotEmpty) g,
    ];
    final total = full.fold<int>(0, (n, g) => n + g.$3.length);
    final widths = [for (final g in full) math.max(g.$3.length / total, 0.04)];
    final sum = widths.fold<double>(0, (a, b) => a + b);
    final out = <StyleMapSector>[];
    var start = 0.0;
    for (var k = 0; k < full.length; k++) {
      final sweep = widths[k] / sum;
      out.add(
        StyleMapSector(
          label: full[k].$1,
          color: full[k].$2,
          images: full[k].$3,
          start: start,
          sweep: sweep,
        ),
      );
      start += sweep;
    }
    return out;
  }

  /// Where [im]'s cell sits in the atlas, in atlas pixels.
  Rect atlasRect(StyleMapImage im) => Rect.fromLTWH(
    im.col * cellSize.width,
    im.row * cellSize.height,
    cellSize.width,
    cellSize.height,
  );

  String thumbPath(StyleMapImage im) =>
      thumbPattern.replaceAll('{i}', '${im.index}');

  factory StyleMapPack.fromJson(Map<String, dynamic> j) {
    final grid = j['grid'] as List;
    final cell = j['cell'] as List;
    return StyleMapPack(
      id: j['id'] as String,
      title: j['title'] as String? ?? j['id'] as String,
      cols: grid[0] as int,
      rows: grid[1] as int,
      cellSize: Size((cell[0] as num).toDouble(), (cell[1] as num).toDouble()),
      atlasPath: j['atlas'] as String,
      thumbPattern: j['thumbs'] as String,
      images: [
        for (final im in j['images'] as List)
          StyleMapImage.fromJson(im as Map<String, dynamic>),
      ],
      axes: [
        for (final a in j['axes'] as List? ?? const [])
          StyleMapAxis(a['key'] as String, a['label'] as String),
      ],
      clusters: [
        for (final c in j['clusters'] as List? ?? const [])
          StyleMapCluster(
            id: c['id'] as int,
            label: c['label'] as String? ?? '',
            size: c['size'] as int? ?? 0,
            color: _hex(c['color'] as String?),
          ),
      ],
      facets: [
        for (final f in j['facets'] as List? ?? const [])
          StyleMapFacet(f['key'] as String, f['label'] as String, [
            for (final v in f['values'] as List)
              StyleMapFacetValue(
                v['id'] as String,
                v['label'] as String? ?? v['id'] as String,
                v['n'] as int? ?? 0,
              ),
          ]),
      ],
    );
  }

  static Color _hex(String? s) {
    final v = int.tryParse((s ?? '').replaceFirst('#', ''), radix: 16);
    return v == null ? const Color(0xFF888888) : Color(0xFF000000 | v);
  }
}

/// One line of the server's `index.json` — enough to list a pack without
/// downloading its manifest.
class StyleMapEntry {
  const StyleMapEntry({
    required this.id,
    required this.title,
    required this.count,
    required this.atlasPath,
  });
  final String id;
  final String title;
  final int count;
  final String atlasPath;

  factory StyleMapEntry.fromJson(Map<String, dynamic> j) => StyleMapEntry(
    id: j['id'] as String,
    title: j['title'] as String? ?? j['id'] as String,
    count: j['n'] as int? ?? 0,
    atlasPath: j['atlas'] as String? ?? '',
  );
}

/// How the mosaic sits in its viewport: fitted whole at [zoom] 1, then scaled
/// and panned. Pure geometry, kept apart from the widget so the finger → cell
/// mapping can be tested without pumping gestures.
class StyleMapView {
  const StyleMapView({
    required this.viewport,
    required this.aspect,
    this.zoom = 1,
    this.origin,
  });

  final Size viewport;

  /// Width / height of the mosaic.
  final double aspect;
  final double zoom;

  /// Top-left of the mosaic in viewport coordinates; null = centred.
  final Offset? origin;

  static const maxZoom = 12.0;

  /// The mosaic at zoom 1: as large as fits the viewport whole.
  Size get _fit => viewport.width / viewport.height > aspect
      ? Size(viewport.height * aspect, viewport.height)
      : Size(viewport.width, viewport.width / aspect);

  Size get size => _fit * zoom;

  Rect get rect => _clamp(origin ?? Offset.zero) & size;

  /// Centred on an axis the mosaic does not fill, otherwise never showing
  /// past its edge.
  Offset _clamp(Offset o) {
    double axis(double pos, double extent, double room) =>
        extent <= room ? (room - extent) / 2 : pos.clamp(room - extent, 0.0);
    return Offset(
      axis(o.dx, size.width, viewport.width),
      axis(o.dy, size.height, viewport.height),
    );
  }

  /// A viewport point as 0–1 coordinates of the mosaic.
  Offset toUnit(Offset p) {
    final r = rect;
    return Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height);
  }

  /// Zoomed to [next] so that the mosaic point that was under [anchor] comes
  /// to rest under [focal] (the same point for a pinch in place; different
  /// ones when the two fingers also drag).
  StyleMapView zoomedAbout(Offset anchor, Offset focal, double next) {
    final z = next.clamp(1.0, maxZoom);
    final u = toUnit(anchor);
    final s = _fit * z;
    return StyleMapView(
      viewport: viewport,
      aspect: aspect,
      zoom: z,
      origin: Offset(focal.dx - u.dx * s.width, focal.dy - u.dy * s.height),
    );
  }

  StyleMapView resized(Size next) => next == viewport
      ? this
      : StyleMapView(
          viewport: next,
          aspect: aspect,
          zoom: zoom,
          origin: origin,
        );
}
