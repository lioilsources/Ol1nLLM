import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/theme.dart';

/// Fullscreen 360° viewer for a generated 3D model.
///
/// Renders the GLB via `<model-viewer>` (model_viewer_plus). The file is
/// handed over as a base64 data URI — the underlying WebView cannot reach the
/// app's documents directory by file:// path on iOS, and a ~5 MB GLB inlines
/// fine. Single-material grey is expected: the pipeline exports geometry only.
///
/// The STL (the actual print artifact) is shared out via the platform share
/// sheet — AirDrop/Files → open in Prusa Slicer.
class ModelViewerScreen extends StatelessWidget {
  const ModelViewerScreen({
    super.key,
    required this.glbPath,
    required this.stlPath,
  });

  final String glbPath;
  final String stlPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('3D model'),
        actions: [
          IconButton(
            tooltip: 'Sdílet STL (Prusa Slicer)',
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: [XFile(stlPath, mimeType: 'model/stl')]),
            ),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _dataUri(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'GLB se nepodařilo načíst: ${snap.error}',
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
            src: snap.data!,
            backgroundColor: AppTheme.background,
            cameraControls: true,
            autoRotate: true,
            autoRotateDelay: 1500,
            disableZoom: false,
            alt: '3D model',
          );
        },
      ),
    );
  }

  Future<String> _dataUri() async {
    final bytes = await File(glbPath).readAsBytes();
    return 'data:model/gltf-binary;base64,${base64Encode(bytes)}';
  }
}
