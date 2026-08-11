import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/theme.dart';
import '../models/image_model.dart';

/// Result of a finished mask-editing session: the mask PNG (source resolution,
/// white = repaint, black = keep — the contract of the inpaint workflows), the
/// user's prompt for the masked region, an optional reference image whose
/// appearance should guide the repaint, and the inpaint model chosen in the
/// prompt sheet.
typedef MaskEditorResult = ({
  Uint8List maskPng,
  String prompt,
  Uint8List? refPng,
  bool refIsFace,
  String modelId,
});

/// Fullscreen mask painting over a source image.
///
/// Strokes are stored in *image* coordinates (pixels of the source PNG), so
/// the exported mask is resolution-exact no matter how the preview is scaled.
/// The on-screen overlay renders the same strokes transformed into the fitted
/// display rect. Eraser strokes remove earlier paint both on screen
/// (BlendMode.clear inside a saveLayer) and in the export (black over white —
/// same order-preserving semantics).
///
/// Pops with a [MaskEditorResult], or null when the user backs out.
class MaskEditorScreen extends StatefulWidget {
  const MaskEditorScreen({
    super.key,
    required this.imageBytes,
    required this.models,
    required this.initialModelId,
  });

  final Uint8List imageBytes;

  /// Inpaint-capable models offered in the prompt sheet. The chosen one is
  /// returned in [MaskEditorResult.modelId] — the model decision belongs
  /// here, at the point of use, not in the global picker (where inpaint-only
  /// models are disabled).
  final List<ImageModelSpec> models;

  /// Pre-selected entry of [models] (the session's model when it can
  /// inpaint, otherwise the caller's fallback).
  final String initialModelId;

  @override
  State<MaskEditorScreen> createState() => _MaskEditorScreenState();
}

class _Stroke {
  _Stroke({required this.width, required this.erase}) : points = [];
  final List<Offset> points; // image-space px
  final double width; // image-space px
  final bool erase;
}

class _MaskEditorScreenState extends State<MaskEditorScreen> {
  ui.Image? _image;
  final List<_Stroke> _strokes = [];
  bool _erasing = false;

  /// Brush diameter in *display* logical px — feels constant to the finger;
  /// converted to image px at stroke start using the current fit scale.
  double _brushDisplayPx = 36;

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(widget.imageBytes, (img) {
      if (mounted) setState(() => _image = img);
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// BoxFit.contain rect of the image inside [constraints].
  Rect _fitRect(BoxConstraints constraints) {
    final img = _image!;
    final scale = (constraints.maxWidth / img.width)
        .clamp(0.0, constraints.maxHeight / img.height)
        .toDouble();
    final w = img.width * scale, h = img.height * scale;
    return Rect.fromLTWH(
      (constraints.maxWidth - w) / 2,
      (constraints.maxHeight - h) / 2,
      w,
      h,
    );
  }

  Offset _toImageSpace(Offset local, Rect fit) => Offset(
        ((local.dx - fit.left) / fit.width * _image!.width)
            .clamp(0, _image!.width.toDouble()),
        ((local.dy - fit.top) / fit.height * _image!.height)
            .clamp(0, _image!.height.toDouble()),
      );

  void _startStroke(Offset local, Rect fit) {
    final scale = fit.width / _image!.width;
    setState(() {
      _strokes.add(
        _Stroke(width: _brushDisplayPx / scale, erase: _erasing)
          ..points.add(_toImageSpace(local, fit)),
      );
    });
  }

  void _extendStroke(Offset local, Rect fit) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(_toImageSpace(local, fit)));
  }

  bool get _hasMask => _strokes.any((s) => !s.erase);

  /// Render the mask at source resolution: black canvas, white strokes,
  /// eraser strokes painted black in order.
  Future<Uint8List> _exportMask() async {
    final img = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    for (final s in _strokes) {
      _paintStroke(
        canvas,
        s,
        Paint()
          ..color = s.erase ? const Color(0xFF000000) : const Color(0xFFFFFFFF)
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    final pic = recorder.endRecording();
    final rendered = await pic.toImage(img.width, img.height);
    pic.dispose();
    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      rendered.dispose();
    }
  }

  static void _paintStroke(Canvas canvas, _Stroke s, Paint paint) {
    if (s.points.length == 1) {
      // A tap: strokePath of a single point draws nothing — use a dot.
      canvas.drawCircle(
        s.points.first,
        paint.strokeWidth / 2,
        Paint()
          ..color = paint.color
          ..blendMode = paint.blendMode,
      );
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  Future<void> _confirm() async {
    final result = await showModalBottomSheet<
        ({String prompt, Uint8List? refPng, bool refIsFace, String modelId})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (context) => _PromptSheet(
        models: widget.models,
        initialModelId: widget.initialModelId,
      ),
    );
    if (result == null || result.prompt.trim().isEmpty || !mounted) return;
    final mask = await _exportMask();
    if (!mounted) return;
    Navigator.of(context).pop((
      maskPng: mask,
      prompt: result.prompt.trim(),
      refPng: result.refPng,
      refIsFace: result.refIsFace,
      modelId: result.modelId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Inpaint — zamaluj oblast'),
        actions: [
          IconButton(
            tooltip: 'Zpět o tah',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Smazat masku',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.clear()),
            icon: const Icon(Icons.layers_clear_outlined),
          ),
        ],
      ),
      body: _image == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            )
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fit = _fitRect(constraints);
                      return GestureDetector(
                        onPanStart: (d) => _startStroke(d.localPosition, fit),
                        onPanUpdate: (d) => _extendStroke(d.localPosition, fit),
                        onTapDown: (d) => _startStroke(d.localPosition, fit),
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: _MaskOverlayPainter(
                            image: _image!,
                            strokes: _strokes,
                            fit: fit,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _Toolbar(
                  erasing: _erasing,
                  brushDisplayPx: _brushDisplayPx,
                  canConfirm: _hasMask,
                  onMode: (erase) => setState(() => _erasing = erase),
                  onBrushSize: (v) => setState(() => _brushDisplayPx = v),
                  onConfirm: _confirm,
                ),
              ],
            ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.erasing,
    required this.brushDisplayPx,
    required this.canConfirm,
    required this.onMode,
    required this.onBrushSize,
    required this.onConfirm,
  });

  final bool erasing;
  final double brushDisplayPx;
  final bool canConfirm;
  final ValueChanged<bool> onMode;
  final ValueChanged<double> onBrushSize;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.brush, size: 18),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.cleaning_services_outlined, size: 18),
              ),
            ],
            selected: {erasing},
            onSelectionChanged: (s) => onMode(s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTheme.accent,
              selectedForegroundColor: Colors.white,
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
          Expanded(
            child: Slider(
              value: brushDisplayPx,
              min: 8,
              max: 96,
              activeColor: AppTheme.accent,
              onChanged: onBrushSize,
            ),
          ),
          FilledButton.icon(
            onPressed: canConfirm ? onConfirm : null,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Pokračovat'),
          ),
        ],
      ),
    );
  }
}

class _MaskOverlayPainter extends CustomPainter {
  _MaskOverlayPainter({
    required this.image,
    required this.strokes,
    required this.fit,
  });

  final ui.Image image;
  final List<_Stroke> strokes;
  final Rect fit;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      fit,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // The stroke layer: red overlay where the mask is; eraser strokes punch
    // holes (BlendMode.clear), which is why the layer is isolated.
    canvas.saveLayer(fit, Paint());
    canvas.translate(fit.left, fit.top);
    final scale = fit.width / image.width;
    canvas.scale(scale);
    for (final s in strokes) {
      final paint = Paint()
        ..color = const Color(0xB3FF3B30)
        ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _MaskEditorScreenState._paintStroke(canvas, s, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaskOverlayPainter old) =>
      old.strokes != strokes ||
      old.fit != fit ||
      old.image != image ||
      // Same-list mutation (points appended during a drag) must repaint too.
      _pointCount(old.strokes) != _pointCount(strokes);

  static int _pointCount(List<_Stroke> s) =>
      s.fold(0, (a, b) => a + b.points.length);
}

/// Prompt entry for the masked region: inpaint-model choice chips, an
/// optional reference image (appearance donor), and the prompt itself.
/// Pops with `(prompt, refPng, modelId)`, or null.
class _PromptSheet extends StatefulWidget {
  const _PromptSheet({
    required this.models,
    required this.initialModelId,
  });

  final List<ImageModelSpec> models;
  final String initialModelId;

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  final _controller = TextEditingController();
  bool _hasText = false;
  Uint8List? _refPng;

  /// Face-identity mode: the reference is a face whose identity must carry
  /// over (PuLID). Only offered when [_model.inpaintFace].
  bool _refIsFace = false;
  late String _modelId = widget.initialModelId;

  ImageModelSpec get _model =>
      widget.models.firstWhere((m) => m.id == _modelId,
          orElse: () => widget.models.first);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// First face-capable model in the sheet, or null when none exists.
  ImageModelSpec? get _faceCapable {
    for (final m in widget.models) {
      if (m.inpaintFace) return m;
    }
    return null;
  }

  /// Toggle face mode; when the selected model can't do it, switch to one
  /// that can (FLUX Fill) and enable the mode in the same tap.
  void _tapFaceToggle() {
    if (_model.inpaintFace) {
      setState(() => _refIsFace = !_refIsFace);
      return;
    }
    final target = _faceCapable;
    if (target == null) return;
    setState(() {
      _modelId = target.id;
      _refIsFace = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Přepnuto na ${target.label} — přenese se identita tváře.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickReference() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _refPng = bytes);
    } catch (_) {
      // Picker failures (permissions, cancelled intents) just leave the
      // reference unset — the text-only path still works.
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop((
      prompt: text,
      refPng: _refPng,
      refIsFace: _refPng != null && _refIsFace && _model.inpaintFace,
      modelId: _model.id,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Co má být v zamalované oblasti?',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          // Which model repaints — chosen here, at the point of use.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in widget.models) ...[
                  ChoiceChip(
                    avatar: Icon(
                      m.icon,
                      size: 16,
                      color: m.id == _modelId ? Colors.white : m.color,
                    ),
                    label: Text(m.label),
                    selected: m.id == _modelId,
                    selectedColor: AppTheme.accent,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: m.id == _modelId
                          ? Colors.white
                          : AppTheme.textPrimary,
                    ),
                    backgroundColor: AppTheme.surfaceAlt,
                    onSelected: (_) => setState(() {
                      _modelId = m.id;
                      // A model without reference support drops a picked ref;
                      // one without a face path drops the face mode.
                      if (!m.inpaintRef) _refPng = null;
                      if (!m.inpaintFace) _refIsFace = false;
                    }),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          if (_model.inpaintRef) ...[
            const SizedBox(height: 10),
            // Reference picker: thumbnail with a remove ×, or an add-button.
            _refPng == null
                ? OutlinedButton.icon(
                    onPressed: _pickReference,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: const Text('Přidat referenci (vzhled výplně)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  )
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _refPng!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _refIsFace
                              ? 'Přenese se IDENTITA obličeje z reference'
                              : 'Maska převezme vzhled z reference',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // Always visible so the feature is discoverable. On a
                      // model without a face path the tap switches to one
                      // that has it (instead of the icon silently not
                      // existing); without any face-capable model it hides.
                      if (_faceCapable != null)
                        IconButton(
                          tooltip:
                              'Reference je obličej — zachovat identitu',
                          onPressed: _tapFaceToggle,
                          icon: Icon(
                            _model.inpaintFace
                                ? Icons.face_retouching_natural
                                : Icons.face_retouching_off,
                            size: 22,
                            color: _refIsFace && _model.inpaintFace
                                ? AppTheme.accent
                                : _model.inpaintFace
                                    ? AppTheme.textSecondary
                                    : AppTheme.textSecondary
                                        .withValues(alpha: 0.45),
                          ),
                        ),
                      IconButton(
                        onPressed: () => setState(
                            () { _refPng = null; _refIsFace = false; }),
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'např. „yellow rubber duck" — VELKÁ PÍSMENA = negativ',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _hasText ? _submit : null,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Inpaint'),
            ),
          ),
        ],
      ),
    );
  }
}
