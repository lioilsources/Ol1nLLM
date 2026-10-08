import 'dart:ui';

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

  /// Position on the 1D route through the grid (scrub / autoplay).
  final int route;

  /// Normalised 0–1, aligned with [StyleMapPack.axes].
  final List<double> features;

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
      route: j['hilbert'] as int? ?? 0,
      features: [
        for (final v in j['f'] as List? ?? const []) (v as num).toDouble(),
      ],
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
