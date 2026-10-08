import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/constants/theme.dart';
import '../models/image_model.dart';
import '../models/style_preset.dart';
import '../stylemap/model.dart';
import '../stylemap/service.dart';
import '../stylemap/stylemap.dart';

/// Style maps: pick a set, then slide a finger across its pictures.
///
/// With [pick] the screen is a picker — „Použít" pops with a [StyleMapPick]
/// (the picture's prompt fragment and/or style preset). Without it the
/// fragment goes to the clipboard, so the screen is useful on its own.
class StyleMapScreen extends StatefulWidget {
  const StyleMapScreen({super.key, this.pick = false});

  final bool pick;

  @override
  State<StyleMapScreen> createState() => _StyleMapScreenState();
}

class _StyleMapScreenState extends State<StyleMapScreen> {
  final _service = StyleMapService();

  List<StyleMapEntry>? _index;
  StyleMapPack? _pack;
  ui.Image? _atlas;
  StyleMapImage? _selected;

  /// Whether the open set mixes models — then the label has to name them.
  bool _manyModels = false;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  @override
  void dispose() {
    _atlas?.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await body();
    } on StyleMapException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'mapa se nenačetla: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadIndex() => _run(() async {
    final index = await _service.fetchIndex();
    if (!mounted) return;
    setState(() => _index = index);
    // A single set needs no list in front of it.
    if (index.length == 1) await _open(index.first.id);
  });

  Future<void> _open(String id) => _run(() async {
    final pack = await _service.fetchPack(id);
    final atlas = await _service.fetchAtlas(pack);
    if (!mounted) {
      atlas.dispose();
      return;
    }
    setState(() {
      _pack = pack;
      _atlas = atlas;
      _selected = null;
      _manyModels = pack.images.map((im) => im.modelId).toSet().length > 1;
    });
  });

  void _close() {
    final atlas = _atlas;
    setState(() {
      _pack = null;
      _atlas = null;
      _selected = null;
    });
    atlas?.dispose();
  }

  void _use() {
    final im = _selected;
    if (im == null) return;
    final pick = StyleMapPick.of(im);
    if (pick.isEmpty) return;
    if (widget.pick) {
      Navigator.of(context).pop(pick);
      return;
    }
    final text = pick.tag.isNotEmpty ? pick.tag : _label(im);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Zkopírováno: $text')));
  }

  /// The pack carries registry ids; here they get the names the rest of the
  /// app shows. An id the registry no longer has stays as it is.
  String _label(StyleMapImage im) {
    final style = styleById(im.styleId)?.label ?? im.styleId;
    final model = _manyModels
        ? kImageModels.where((m) => m.id == im.modelId).firstOrNull?.label ??
              im.modelId
        : null;
    if (style == null && model == null) return im.label;
    // Without a style the pack's label is the tag, or its word for the
    // baseline; with one, only a tag is worth keeping from it.
    final lead = style == null || im.tag.isNotEmpty
        ? im.label.split(' · ').first
        : null;
    return [lead, style, model].nonNulls.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    final atlas = _atlas;
    final open = pack != null && atlas != null;
    final selected = _selected;
    final canUse =
        open && selected != null && !StyleMapPick.of(selected).isEmpty;
    return PopScope(
      // Back from a map returns to the list, when there is a list to return to.
      canPop: !open || (_index?.length ?? 0) <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(open ? pack.title : 'Mapy stylů'),
          actions: [
            if (open)
              TextButton(
                onPressed: canUse ? _use : null,
                child: Text(widget.pick ? 'Použít' : 'Kopírovat'),
              ),
          ],
        ),
        body: SafeArea(
          child: open
              ? StyleMap(
                  key: ValueKey(pack.id),
                  pack: pack,
                  atlas: atlas,
                  headers: _service.headers,
                  thumbUrl: (im) => _service.thumbUrl(pack, im),
                  labelOf: _label,
                  onChanged: (im) => setState(() => _selected = im),
                )
              : _list(),
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadIndex, child: const Text('Znovu')),
            ],
          ),
        ),
      );
    }
    final index = _index ?? const <StyleMapEntry>[];
    if (index.isEmpty) {
      return const Center(
        child: Text(
          'Na serveru zatím žádná mapa není.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: index.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Colors.white12),
      itemBuilder: (_, i) {
        final e = index[i];
        return ListTile(
          title: Text(
            e.title,
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          subtitle: Text(
            '${e.count} obrázků',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppTheme.textSecondary,
          ),
          onTap: () => _open(e.id),
        );
      },
    );
  }
}
