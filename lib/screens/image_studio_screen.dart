import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/theme.dart';
import '../models/gen_node.dart';
import '../providers/image_studio_provider.dart';
import '../services/comfyui_service.dart' show ComfyWorkflow;
import '../services/flux_kontext_nim_service.dart' show kBackendFluxKontextNim;
import '../services/image_backend.dart' show kBackendComfyUI, kBackendFluxNim;
import '../widgets/image_session_drawer.dart';

/// Iterative image studio: generate 4 candidates from a prompt, pick one,
/// describe a change, and get 4 refinements of it — repeat to converge.
class ImageStudioScreen extends ConsumerWidget {
  const ImageStudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(imageStudioProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
          ),
        );
        ref.read(imageStudioProvider.notifier).clearError();
      }
    });

    final state = ref.watch(imageStudioProvider);
    final current = state.current;

    final notifier = ref.read(imageStudioProvider.notifier);

    return Scaffold(
      drawer: const ImageSessionDrawer(),
      appBar: AppBar(
        title: const Text('Image Studio'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Session history',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          if (state.isBusy)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Zrušit generování',
              onPressed: notifier.cancel,
            ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'New session',
            onPressed: state.isBusy ? null : notifier.newSession,
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.nodes.isNotEmpty) _TreeNavigator(state: state),
          Expanded(
            child: current == null
                ? const _EmptyHint()
                : _NodeGrid(node: current, selectedId: state.selectedImageId),
          ),
          if (current?.status == GenStatus.generating)
            _ProgressBanner(node: current!),
          _StudioInputBar(state: state),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text(
              'Describe an image to generate four variants,\n'
              'or tap the camera to start from a photo.\n'
              'Tap one, describe a change, and refine it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin progress strip shown under the grid while a round is generating.
class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.node});

  final GenNode node;

  @override
  Widget build(BuildContext context) {
    final label = node.progressLabel ?? 'Generování…';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: AppTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: node.progress,
              minHeight: 4,
              backgroundColor: AppTheme.surface,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tree navigator ─────────────────────────────────────────────────────────

class _LayoutNode {
  final GenNode node;
  final Offset position;
  _LayoutNode(this.node, this.position);
}

class _TreeLayout {
  static const double kNodeSize    = 48.0;
  static const double kLevelStride = 60.0;
  static const double kUnitWidth   = 64.0;

  static ({List<_LayoutNode> nodes, Size canvasSize}) compute(
    List<GenNode> all, {
    double minWidth = 0,
  }) {
    if (all.isEmpty) return (nodes: [], canvasSize: Size.zero);

    final childrenMap = <String, List<GenNode>>{};
    GenNode? root;
    for (final n in all) {
      childrenMap.putIfAbsent(n.id, () => []);
      if (n.parentId == null) {
        root = n;
      } else {
        childrenMap.putIfAbsent(n.parentId!, () => []).add(n);
      }
    }
    if (root == null) return (nodes: [], canvasSize: Size.zero);

    final subtreeWidths = <String, int>{};
    void calcWidth(GenNode n) {
      final kids = childrenMap[n.id] ?? [];
      if (kids.isEmpty) {
        subtreeWidths[n.id] = 1;
      } else {
        for (final k in kids) {
          calcWidth(k);
        }
        subtreeWidths[n.id] = kids.fold(0, (acc, k) => acc + subtreeWidths[k.id]!);
      }
    }
    calcWidth(root);

    final rawWidth = subtreeWidths[root.id]! * kUnitWidth;
    final canvasWidth = rawWidth < minWidth ? minWidth : rawWidth;
    final xOffset = (canvasWidth - rawWidth) / 2;

    final result = <_LayoutNode>[];
    void assignPos(GenNode n, double leftX, int level) {
      final w = subtreeWidths[n.id]! * kUnitWidth;
      result.add(_LayoutNode(n, Offset(leftX + w / 2, kNodeSize / 2 + level * kLevelStride)));
      final kids = childrenMap[n.id] ?? [];
      double cursor = leftX;
      for (final k in kids) {
        assignPos(k, cursor, level + 1);
        cursor += subtreeWidths[k.id]! * kUnitWidth;
      }
    }
    assignPos(root, xOffset, 0);

    double maxY = 0;
    for (final ln in result) {
      if (ln.position.dy > maxY) maxY = ln.position.dy;
    }

    return (
      nodes: result,
      canvasSize: Size(canvasWidth, maxY + kNodeSize / 2 + 8),
    );
  }
}

class _TreeLinePainter extends CustomPainter {
  _TreeLinePainter(this.nodes)
      : _posById = {for (final ln in nodes) ln.node.id: ln.position};

  final List<_LayoutNode> nodes;
  final Map<String, Offset> _posById;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final ln in nodes) {
      final pid = ln.node.parentId;
      if (pid == null) continue;
      final parentPos = _posById[pid];
      if (parentPos == null) continue;
      canvas.drawLine(
        Offset(parentPos.dx, parentPos.dy + _TreeLayout.kNodeSize / 2),
        Offset(ln.position.dx, ln.position.dy - _TreeLayout.kNodeSize / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TreeLinePainter old) => old.nodes != nodes;
}

class _TreeNodeWidget extends StatelessWidget {
  const _TreeNodeWidget({
    required this.layoutNode,
    required this.isCurrent,
    required this.isParent,
    required this.onTap,
    this.displayImageId,
  });

  final _LayoutNode layoutNode;
  final bool isCurrent;
  final bool isParent;
  final VoidCallback onTap;
  final String? displayImageId;

  @override
  Widget build(BuildContext context) {
    final node = layoutNode.node;
    const size = _TreeLayout.kNodeSize;

    Widget inner;
    if (node.status == GenStatus.generating) {
      inner = const Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textSecondary),
      );
    } else if (node.status == GenStatus.error) {
      inner = const Icon(Icons.error_outline, size: 22, color: Colors.redAccent);
    } else if (node.images.isNotEmpty) {
      final displayImg = displayImageId != null
          ? node.images.firstWhere(
              (img) => img.id == displayImageId,
              orElse: () => node.images.first,
            )
          : node.images.first;
      inner = ClipOval(
        child: Image.file(
          File(displayImg.filePath),
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: 48,
          cacheHeight: 48,
        ),
      );
    } else {
      inner = Icon(
        node.isRoot ? Icons.auto_awesome : Icons.brush_outlined,
        size: 20,
        color: AppTheme.textSecondary,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCurrent
              ? AppTheme.accent
              : isParent
                  ? AppTheme.accent.withValues(alpha: 0.12)
                  : AppTheme.surface,
          border: Border.all(
            color: isCurrent
                ? AppTheme.accent
                : isParent
                    ? AppTheme.accent.withValues(alpha: 0.6)
                    : Colors.white24,
            width: isCurrent ? 2.5 : isParent ? 1.5 : 0.5,
          ),
          boxShadow: isCurrent
              ? [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.4), blurRadius: 8)]
              : null,
        ),
        child: Center(child: inner),
      ),
    );
  }
}

class _TreeNavigator extends ConsumerWidget {
  const _TreeNavigator({required this.state});

  final ImageStudioState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(imageStudioProvider.notifier);

    // Find the parent of the currently displayed node so we can highlight it
    // and — only when a child is the current node — show that child's source
    // image on the parent's thumbnail (so the parent reflects what was refined,
    // not its own first variant).
    GenNode? currentNode;
    for (final n in state.nodes) {
      if (n.id == state.currentNodeId) {
        currentNode = n;
        break;
      }
    }
    final parentId = currentNode?.parentId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _TreeLayout.compute(
          state.nodes,
          minWidth: constraints.maxWidth,
        );
        final layoutNodes = layout.nodes;
        final canvasSize = layout.canvasSize;

        if (layoutNodes.length == 1) {
          return SizedBox(
            height: 80,
            child: Center(
              child: _TreeNodeWidget(
                layoutNode: layoutNodes.first,
                isCurrent: true,
                isParent: false,
                onTap: () {},
              ),
            ),
          );
        }

        return SizedBox(
          height: 150,
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.5,
            maxScale: 2.0,
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreeLinePainter(layoutNodes),
                      size: canvasSize,
                    ),
                  ),
                  for (final ln in layoutNodes)
                    Positioned(
                      left: ln.position.dx - _TreeLayout.kNodeSize / 2,
                      top: ln.position.dy - _TreeLayout.kNodeSize / 2,
                      child: _TreeNodeWidget(
                        layoutNode: ln,
                        isCurrent: ln.node.id == state.currentNodeId,
                        isParent: ln.node.id == parentId,
                        displayImageId: ln.node.id == parentId
                            ? currentNode?.sourceImageId
                            : null,
                        onTap: () => notifier.navigateTo(ln.node.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NodeGrid extends ConsumerWidget {
  const _NodeGrid({required this.node, required this.selectedId});

  final GenNode node;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (node.status == GenStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                node.error ?? 'Generation failed',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(imageStudioProvider.notifier).retry(node.id),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              ),
            ],
          ),
        ),
      );
    }

    // One spinner per generating node (the per-step label lives in the
    // progress banner below the grid).
    if (node.status == GenStatus.generating) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            value: node.progress,
            strokeWidth: 2.5,
            color: AppTheme.accent,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: node.images.length == 1 ? 1 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: node.images.length,
      itemBuilder: (context, i) {
        final img = node.images[i];
        return _ImageTile(
          image: img,
          selected: img.id == selectedId,
          onSelect: () =>
              ref.read(imageStudioProvider.notifier).selectImage(img.id),
          onExpand: () => _showFullscreen(context, img),
          onSave: () => _saveImage(context, img),
        );
      },
    );
  }

  void _showFullscreen(BuildContext context, GenImage image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          child: Center(
            child: Image.file(File(image.filePath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _saveImage(BuildContext context, GenImage image) async {
    try {
      await Gal.putImageBytes(image.bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on GalException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.type == GalExceptionType.accessDenied
                  ? 'Gallery permission denied'
                  : 'Failed to save: ${e.type.message}',
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.selected,
    required this.onSelect,
    required this.onExpand,
    required this.onSave,
  });

  final GenImage image;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onExpand;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppTheme.accent : Colors.white12,
                width: selected ? 2.5 : 0.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(image.filePath), fit: BoxFit.cover),
            ),
          ),
          if (selected)
            const Positioned(
              top: 6,
              left: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.accent,
                child: Icon(Icons.check, size: 16, color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 40,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSave,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.download_outlined, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onExpand,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.fullscreen, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoraChip extends StatelessWidget {
  const _LoraChip({
    required this.loras,
    required this.selected,
    required this.onChanged,
  });

  final List<String> loras;
  final String? selected;
  final ValueChanged<String?> onChanged;

  String _display(String name) {
    final s = name.replaceAll('.safetensors', '');
    return s.length > 22 ? '${s.substring(0, 22)}…' : s;
  }

  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Vybrat LoRA',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                selected == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected == null
                    ? AppTheme.accent
                    : AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Žádná LoRA',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                onChanged(null);
                Navigator.of(context).pop();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: loras.length,
                itemBuilder: (_, i) {
                  final lora = loras[i];
                  final isSel = lora == selected;
                  return ListTile(
                    leading: Icon(
                      isSel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSel ? AppTheme.accent : AppTheme.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      lora.replaceAll('.safetensors', ''),
                      style: TextStyle(
                        color: isSel ? AppTheme.accent : AppTheme.textPrimary,
                      ),
                    ),
                    onTap: () {
                      onChanged(lora);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected != null
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected != null ? AppTheme.accent : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.style_outlined,
              size: 14,
              color: selected != null
                  ? AppTheme.accent
                  : AppTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              selected != null ? _display(selected!) : 'LoRA',
              style: TextStyle(
                fontSize: 12,
                color: selected != null
                    ? AppTheme.accent
                    : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more,
              size: 14,
              color: selected != null
                  ? AppTheme.accent
                  : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendChip extends StatelessWidget {
  const _BackendChip({required this.backendId, required this.onChanged});

  final String backendId;
  final ValueChanged<String> onChanged;

  static const _cycle = [
    kBackendComfyUI,
    kBackendFluxNim,
    kBackendFluxKontextNim,
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _cycle.indexOf(backendId);
    final next = _cycle[(idx + 1) % _cycle.length];

    final (Color color, IconData icon, String label) = switch (backendId) {
      kBackendFluxNim => (AppTheme.accent, Icons.bolt, 'FLUX Schnell'),
      kBackendFluxKontextNim => (Colors.orange, Icons.auto_fix_high, 'FLUX Kontext'),
      _ => (AppTheme.textSecondary, Icons.hub_outlined, 'ComfyUI'),
    };
    final isActive = backendId != kBackendComfyUI;

    return GestureDetector(
      onTap: () => onChanged(next),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? color : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowChip extends StatelessWidget {
  const _WorkflowChip({
    required this.current,
    required this.onChanged,
  });

  final ComfyWorkflow current;
  final ValueChanged<ComfyWorkflow> onChanged;

  @override
  Widget build(BuildContext context) {
    final isPony = current == ComfyWorkflow.pony;
    return GestureDetector(
      onTap: () => onChanged(isPony ? ComfyWorkflow.flux : ComfyWorkflow.pony),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isPony
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPony ? AppTheme.accent : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high_outlined,
              size: 14,
              color: isPony ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              isPony ? 'Pony' : 'Flux',
              style: TextStyle(
                fontSize: 12,
                color: isPony ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioInputBar extends ConsumerStatefulWidget {
  const _StudioInputBar({required this.state});

  final ImageStudioState state;

  @override
  ConsumerState<_StudioInputBar> createState() => _StudioInputBarState();
}

class _StudioInputBarState extends ConsumerState<_StudioInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isRefineMode => widget.state.selectedImageId != null;
  bool get _hasRoot => widget.state.nodes.isNotEmpty;

  String get _hint {
    if (!_hasRoot) return 'Describe an image to generate…';
    if (_isRefineMode) return 'Describe the change to the selected image…';
    return 'Pick an image to refine, or tap ＋ for a new one';
  }

  /// Let the user start a fresh image from a camera photo (or gallery pick).
  /// The chosen photo becomes a ready root that the next message refines.
  Future<void> _startFromPhoto() async {
    if (widget.state.isBusy) return;
    final source = await _chooseSource();
    if (source == null) return;
    Uint8List bytes;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nepodařilo se načíst fotku: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    await ref.read(imageStudioProvider.notifier).startFromImage(bytes);
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.textPrimary),
              title: const Text('Vyfotit',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.textPrimary),
              title: const Text('Vybrat z galerie',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final notifier = ref.read(imageStudioProvider.notifier);

    if (!_hasRoot) {
      _controller.clear();
      await notifier.generate(text);
    } else if (_isRefineMode) {
      _controller.clear();
      await notifier.refine(text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap an image first, or ＋ to start a new one.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = widget.state.isBusy;
    final canSend = _controller.text.trim().isNotEmpty;

    final loras = widget.state.availableLoras;
    final selectedLora = widget.state.selectedLora;
    final workflow = widget.state.workflow;
    final backendId = widget.state.backendId;
    final isNim =
        backendId == kBackendFluxNim || backendId == kBackendFluxKontextNim;

    // The current node's own prompt shown as context (the text→image prompt
    // for a root, or the edit instruction that produced this refinement).
    final currentNode = widget.state.current;
    final nodePrompt = (currentNode?.prompt.isNotEmpty ?? false)
        ? currentNode!.prompt
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _BackendChip(
                    backendId: backendId,
                    onChanged: (id) =>
                        ref.read(imageStudioProvider.notifier).setBackend(id),
                  ),
                  if (!isNim) ...[
                    const SizedBox(width: 8),
                    _WorkflowChip(
                      current: workflow,
                      onChanged: (wf) =>
                          ref.read(imageStudioProvider.notifier).setWorkflow(wf),
                    ),
                    if (loras.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _LoraChip(
                        loras: loras,
                        selected: selectedLora,
                        onChanged: (v) =>
                            ref.read(imageStudioProvider.notifier).setLora(v),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (nodePrompt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subdirectory_arrow_right,
                      size: 13,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        nodePrompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!_hasRoot) ...[
                  IconButton(
                    icon: const Icon(Icons.photo_camera_outlined),
                    color: AppTheme.textSecondary,
                    tooltip: 'Začít z fotky',
                    onPressed: isBusy ? null : _startFromPhoto,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: Scrollbar(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: _hint,
                          hintStyle: const TextStyle(
                            color: AppTheme.textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppTheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: canSend ? AppTheme.accent : AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: canSend
                                ? Colors.white
                                : AppTheme.textSecondary,
                            size: 20,
                          ),
                          onPressed: canSend ? _send : null,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
