import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/theme.dart';
import '../models/figure_clip.dart';

/// Fullscreen viewer of a dancing figure: the GLB plays one of its dances,
/// the chips below switch between them.
///
/// Every dance is a named glTF animation inside the one GLB (named by clip id,
/// see [FigureService]), so switching is just `animation-name`. The model is
/// handed over as a data URI like in [ModelViewerScreen]; it is encoded once
/// and the viewer is rebuilt per dance (keyed by the clip) — changing the
/// attribute on a live `<model-viewer>` would need its WebView controller,
/// which model_viewer_plus only exposes through a direct webview dependency.
class FigureViewerScreen extends StatefulWidget {
  const FigureViewerScreen({
    super.key,
    required this.glbPath,
    required this.clipIds,
    required this.catalog,
    required this.serverName,
    this.figureId,
  });

  final String glbPath;
  final List<String> clipIds;

  /// Dance names for the chips; a clip the catalog no longer knows still
  /// shows under a readable form of its id.
  final List<FigureClip> catalog;

  /// The `name` this figure was created with — `'Ol1nLLM ${nodeId.substring(0, 8)}'`
  /// in [ImageStudioProvider._createFigure] — shown as a subtitle so it can be
  /// matched against the UGCFactory character list, which has no other way
  /// back to a specific node (the app never surfaced either id before).
  final String serverName;

  /// The server-assigned character id (`node.figureId`), if known — a
  /// different string from [serverName]/the node id, needed for direct API
  /// calls (retry, `/characters/{id}`). Long-press the subtitle to copy it.
  final String? figureId;

  @override
  State<FigureViewerScreen> createState() => _FigureViewerScreenState();
}

class _FigureViewerScreenState extends State<FigureViewerScreen> {
  late final Future<String> _src = _dataUri();
  late String? _clip = widget.clipIds.firstOrNull;

  Future<String> _dataUri() async {
    final bytes = await File(widget.glbPath).readAsBytes();
    return 'data:model/gltf-binary;base64,${base64Encode(bytes)}';
  }

  void _copyId(BuildContext context) {
    final text = widget.figureId ?? widget.serverName;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.figureId != null
              ? 'ID figurky zkopírováno do schránky'
              : 'Název zkopírován do schránky',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Tančící figurka'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: GestureDetector(
            onLongPress: () => _copyId(context),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                widget.serverName,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sdílet GLB (Blender, 3D prohlížeče)',
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(widget.glbPath, mimeType: 'model/gltf-binary')],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: _src,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Figurku se nepodařilo načíst: ${snap.error}',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    );
                  }
                  return ModelViewer(
                    key: ValueKey(_clip),
                    src: snap.data!,
                    backgroundColor: AppTheme.background,
                    cameraControls: true,
                    autoPlay: true,
                    animationName: _clip,
                    disableZoom: false,
                    alt: 'Tančící figurka',
                  );
                },
              ),
            ),
            if (widget.clipIds.length > 1)
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: widget.clipIds.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final id = widget.clipIds[i];
                    return ChoiceChip(
                      label: Text(figureClipLabel(id, widget.catalog)),
                      selected: id == _clip,
                      selectedColor: AppTheme.accent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _clip = id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
