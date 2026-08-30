import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../core/constants/theme.dart';
import '../models/gen_node.dart';
import '../models/image_model.dart';
import '../models/pose_template.dart';
import '../models/style_preset.dart';
import '../models/video_scene.dart';
import '../providers/image_studio_provider.dart';
import '../widgets/image_session_drawer.dart';
import 'mask_editor_screen.dart';
import 'model_viewer_screen.dart';
import 'video_player_screen.dart' show VideoPlayerScreen, saveVideo;

/// Copy [text] to the clipboard and confirm with a brief snackbar. No-op for
/// empty text. Used by long-press handlers on error messages and prompts.
void _copyToClipboard(BuildContext context, String text, String what) {
  if (text.trim().isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what zkopírován do schránky'), duration: const Duration(seconds: 2)),
  );
}

/// Iterative image studio: generate 4 candidates from a prompt, pick one,
/// describe a change, and get 4 refinements of it — repeat to converge.
/// Drop focus from wherever it is. Used by every interaction that is clearly
/// not typing (opening a sheet, picking a tile, walking the tree): on a phone
/// the keyboard hides most of the grid, and a tap on a child widget never
/// reaches the screen-level tap-to-dismiss handler.
void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

class ImageStudioScreen extends ConsumerWidget {
  const ImageStudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(imageStudioProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        final errText = next.error!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errText),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Kopírovat',
              textColor: Colors.white,
              onPressed: () => Clipboard.setData(ClipboardData(text: errText)),
            ),
          ),
        );
        ref.read(imageStudioProvider.notifier).clearError();
      }
      if (next.info != null && next.info != prev?.info) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.info!),
            duration: const Duration(seconds: 4),
          ),
        );
        ref.read(imageStudioProvider.notifier).clearInfo();
      }
    });

    final state = ref.watch(imageStudioProvider);
    final current = state.current;

    final notifier = ref.read(imageStudioProvider.notifier);

    // Progress banner: prefer the node the user is looking at; if it isn't
    // generating, fall back to the first other in-flight node so background
    // work (parallel generations) is still visible. othersGenerating tells the
    // banner how many more are running so it can show "+N na pozadí".
    final generating =
        state.nodes.where((n) => n.status == GenStatus.generating).toList();
    final bannerNode = current?.status == GenStatus.generating
        ? current
        : (generating.isNotEmpty ? generating.first : null);

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
          if (state.exportingSessionId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: state.exportProgress,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Export do FINETUNE gallery',
              onPressed: !state.isBusy &&
                      state.activeSessionId != null &&
                      state.nodes.any((n) =>
                          n.status == GenStatus.ready && n.images.isNotEmpty)
                  ? () => notifier.exportSession(state.activeSessionId!)
                  : null,
            ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'New session',
            onPressed: state.isBusy ? null : notifier.newSession,
          ),
        ],
      ),
      // Tap anywhere outside the prompt field to drop focus and dismiss the
      // keyboard — small devices (iPhone mini) have no other way to reclaim
      // the space it eats, and there is no hardware/keyboard "done" control
      // for a plain (non-scrollable) body.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            if (state.nodes.isNotEmpty) _TreeNavigator(state: state),
            Expanded(
              child: current == null
                  ? const _EmptyHint()
                  : _NodeGrid(node: current, selectedId: state.selectedImageId),
            ),
            if (bannerNode != null)
              _ProgressBanner(
                key: ValueKey(bannerNode.id),
                node: bannerNode,
                othersGenerating:
                    generating.where((n) => n.id != bannerNode.id).length,
              ),
            _StudioInputBar(state: state),
          ],
        ),
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
///
/// Identifies which node it's reporting on (truncated prompt) and how many
/// other nodes generate in parallel. For NIM backends, which report no per-step
/// progress (`node.progress == null`), it appends a live elapsed timer so the
/// "Generování…" state visibly ticks instead of looking stuck.
class _ProgressBanner extends StatefulWidget {
  const _ProgressBanner({
    super.key,
    required this.node,
    this.othersGenerating = 0,
  });

  final GenNode node;
  final int othersGenerating;

  @override
  State<_ProgressBanner> createState() => _ProgressBannerState();
}

class _ProgressBannerState extends State<_ProgressBanner> {
  final DateTime _start = DateTime.now();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Only an indeterminate (NIM) run needs the ticking elapsed clock.
    if (widget.node.progress == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed = DateTime.now().difference(_start));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _shortPrompt(String prompt) {
    final p = prompt.trim();
    if (p.isEmpty) return '(úprava obrázku)';
    return p.length > 40 ? '${p.substring(0, 40)}…' : p;
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    // Base label comes from the provider (Ve frontě / Stahování / Generování…).
    // For the indeterminate "Generování…" case, append the live elapsed time.
    var label = node.progressLabel ?? 'Generování…';
    if (node.progress == null && label.startsWith('Generování')) {
      label = 'Generování… (${_fmt(_elapsed)})';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: AppTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _shortPrompt(node.prompt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (widget.othersGenerating > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '+${widget.othersGenerating} na pozadí',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
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
      // Newest child first (left). Children arrive in creation order, so
      // laying them out left→right pushed the freshest branch to the far
      // right — off-screen on a phone, since the viewer starts at the canvas
      // origin. Reversed, the round you just made is the one you can see.
      for (final k in kids.reversed) {
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
        node.isVideo
            ? Icons.movie_outlined
            : node.is3D
                ? Icons.view_in_ar
                : node.isRoot
                    ? Icons.auto_awesome
                    : Icons.brush_outlined,
        size: 20,
        color: (node.is3D || node.isVideo) && node.status == GenStatus.ready
            ? AppTheme.accent
            : AppTheme.textSecondary,
      );
    }

    final circle = Container(
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
    );

    final badged = node.maskFileName != null || node.isRepose;
    return GestureDetector(
      onTap: onTap,
      child: !badged
          ? circle
          : Stack(
              clipBehavior: Clip.none,
              children: [
                circle,
                // Inpaint badge: tap previews the mask over the node's image.
                // Repose badge: marks the round; its reference already shows
                // in the parent circle (displayImageId = sourceImageId).
                Positioned(
                  top: -3,
                  right: -3,
                  child: GestureDetector(
                    onTap: node.isRepose
                        ? onTap
                        : () => _showMaskPreview(context, node),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceAlt,
                      ),
                      child: Icon(
                        node.isRepose
                            ? Icons.directions_walk
                            : Icons.auto_fix_high,
                        size: 10,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// The node's first image with its inpaint mask blended on top — shows what
  /// area that round repainted.
  void _showMaskPreview(BuildContext context, GenNode node) {
    final maskFile = node.maskFileName == null
        ? null
        : File('${GenImage.baseDir}/${node.maskFileName}');
    if (maskFile == null || !maskFile.existsSync()) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (node.images.isNotEmpty)
                  Image.file(
                    File(node.images.first.filePath),
                    fit: BoxFit.contain,
                  ),
                // The mask is white-on-black; modulate tints its white area
                // accent and keeps black black, so at 0.7 opacity the
                // repainted region glows while the rest dims.
                Image.file(
                  maskFile,
                  fit: BoxFit.contain,
                  color: AppTheme.accent.withValues(alpha: 0.55),
                  colorBlendMode: BlendMode.modulate,
                  opacity: const AlwaysStoppedAnimation(0.7),
                ),
              ],
            ),
          ),
        ),
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
                        onTap: () {
                          _dismissKeyboard();
                          notifier.navigateTo(ln.node.id);
                        },
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
              // Long-press copies the full error text (handy for reporting).
              GestureDetector(
                onLongPress: () => _copyToClipboard(
                  context,
                  node.error ?? 'Generation failed',
                  'Chyba',
                ),
                child: Text(
                  node.error ?? 'Generation failed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
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
    // progress banner below the grid). 3D rounds also get a manual escape
    // hatch: their job survives app suspension, but the stream that was
    // watching it does not always — without a button the node would just
    // spin forever with no way to pull the (finished) result down.
    if (node.status == GenStatus.generating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: node.progress,
                strokeWidth: 2.5,
                color: AppTheme.accent,
              ),
            ),
            if (node.is3D || node.isVideo) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () =>
                    ref.read(imageStudioProvider.notifier).retry(node.id),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Zkusit stáhnout výsledek'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (node.isVideo && node.status == GenStatus.ready) {
      final path = node.videoFileName == null
          ? null
          : '${GenImage.baseDir}/${node.videoFileName}';
      return path == null
          ? const Center(
              child: Text(
                'Video soubor chybí',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : _VideoNodeView(key: ValueKey(node.id), path: path, title: node.prompt);
    }

    if (node.is3D && node.status == GenStatus.ready) {
      final glb = node.glbFileName == null
          ? null
          : '${GenImage.baseDir}/${node.glbFileName}';
      final stl = node.stlFileName == null
          ? null
          : '${GenImage.baseDir}/${node.stlFileName}';
      // LayoutBuilder + a scroll view with a min-height constraint: centers
      // when there's room, but on a squeezed viewport (keyboard open on a
      // small phone) it scrolls instead of overflowing — an overflowing
      // Center() paints its excess outside this box, where it silently ends
      // up hidden behind whatever is painted after it (the model chips row /
      // prompt bar), so the button becomes present but unreachable instead
      // of just off-screen.
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.view_in_ar, size: 56, color: AppTheme.accent),
                  const SizedBox(height: 12),
                  const Text(
                    '3D model je hotový',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style:
                        FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                    onPressed: glb == null || stl == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ModelViewerScreen(
                                  glbPath: glb,
                                  stlPath: stl,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.threed_rotation, size: 18),
                    label: const Text('Otevřít a otáčet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final canRepose = ref.watch(
      imageStudioProvider.select(
        (s) => s.availableModels.any((m) => m.supportsPose),
      ),
    );
    // No scene catalog ⇒ the video server is down; hide rather than dead.
    final canAnimate = ref.watch(
      imageStudioProvider.select((s) => s.availableScenes.isNotEmpty),
    );
    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          onSelect: () {
            _dismissKeyboard();
            ref.read(imageStudioProvider.notifier).selectImage(img.id);
          },
          onExpand: () {
            _dismissKeyboard();
            _showFullscreen(context, img);
          },
          onSave: () => _saveImage(context, img),
          onInpaint: () => _startInpaint(context, ref, img),
          on3D: () => _start3D(context, ref, img),
          onAnimate: canAnimate
              ? () => _startAnimate(context, ref, img)
              : null,
          // Repose needs an SDXL model (depth ControlNet); without one on the
          // server the affordance is hidden rather than dead.
          onRepose: canRepose
              ? () {
                  _dismissKeyboard();
                  ref.read(imageStudioProvider.notifier).startRepose(img.id);
                }
              : null,
          // Long-press copies the prompt that produced this node's images,
          // so it can be reused.
          onLongPress: () => _copyToClipboard(context, node.prompt, 'Prompt'),
        );
      },
    );
  }

  /// 3D entry: confirm the long-running round, then hand the image to the
  /// server-side Trellis2 pipeline. Selection contract mirrors refine/inpaint.
  Future<void> _start3D(
    BuildContext context,
    WidgetRef ref,
    GenImage img,
  ) async {
    _dismissKeyboard();
    final notifier = ref.read(imageStudioProvider.notifier);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Vytvořit 3D model?',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 17),
        ),
        content: const Text(
          'Generování na serveru trvá 4–7 minut. Appku můžeš mezitím '
          'zavřít — po návratu se výsledek dotáhne sám.\n\n'
          'Výstup: otočitelný 3D náhled + STL pro Prusa Slicer (100 mm).',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vytvořit'),
          ),
        ],
      ),
    );
    if (go != true) return;
    notifier.selectImage(img.id);
    await notifier.make3D();
  }

  /// Animate entry („Rozhýbat"): pick a server-defined scene, then hand the
  /// image to the video job server. The render is minutes long and survives
  /// app suspension — same contract as 3D.
  Future<void> _startAnimate(
    BuildContext context,
    WidgetRef ref,
    GenImage img,
  ) async {
    _dismissKeyboard();
    final notifier = ref.read(imageStudioProvider.notifier);
    final scenes = ref.read(imageStudioProvider).availableScenes;
    final scene = await showModalBottomSheet<VideoScene>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Rozhýbat obrázek',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Vyber scénu. Render na serveru trvá minuty — appku můžeš '
                'zavřít, po návratu se video dotáhne samo.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in scenes)
                    ListTile(
                      leading: const Icon(Icons.movie_outlined, color: AppTheme.accent),
                      title: Text(
                        s.label,
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                      subtitle: Text(
                        '${s.desc}\n~${s.seconds.round()} s · ${s.beats} beatů · ~${s.minutesEst} min',
                        style: const TextStyle(color: AppTheme.textSecondary, height: 1.3),
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.of(context).pop(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (scene == null) return;
    notifier.selectImage(img.id);
    await notifier.animate(scene.id);
  }

  /// Inpaint entry: open the mask editor; the inpaint model (FLUX Fill vs
  /// the SDXL family) is chosen inside its prompt sheet, so there is no
  /// pre-flight switching dialog. The tile's image becomes the selection —
  /// same contract as refine, which also works on the selected image.
  Future<void> _startInpaint(
    BuildContext context,
    WidgetRef ref,
    GenImage img,
  ) async {
    _dismissKeyboard();
    final notifier = ref.read(imageStudioProvider.notifier);
    final state = ref.read(imageStudioProvider);
    final candidates =
        state.availableModels.where((m) => m.inpaint).toList();
    if (candidates.isEmpty) return;
    // Pre-select the session's model when it can inpaint; FLUX Fill (the
    // dedicated inpaint model) otherwise.
    final initial = state.model.inpaint
        ? state.model.id
        : candidates
            .firstWhere((m) => m.id == 'flux-fill',
                orElse: () => candidates.first)
            .id;
    notifier.selectImage(img.id);
    final result = await Navigator.of(context).push<MaskEditorResult>(
      MaterialPageRoute(
        builder: (context) => MaskEditorScreen(
          imageBytes: img.bytes,
          models: candidates,
          initialModelId: initial,
          availableLoras: state.availableLoras,
          initialLora: state.selectedLora,
          initialLoraStrength: state.loraStrength,
        ),
      ),
    );
    if (result == null) return;
    // The chosen model becomes the active one BEFORE the round runs, so the
    // provider guard, node metadata and retry all see it consistently.
    if (result.modelId != ref.read(imageStudioProvider).modelId) {
      notifier.setModel(result.modelId);
    }
    // The sheet's LoRA choice wins for this round — setModel may have
    // reconciled the session LoRA, so apply after it.
    notifier.setLora(result.loraName);
    notifier.setLoraStrength(result.loraStrength);
    await notifier.inpaint(
      result.prompt,
      result.maskPng,
      refPng: result.refPng,
      refIsFace: result.refIsFace,
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
    required this.onInpaint,
    required this.on3D,
    this.onAnimate,
    this.onRepose,
    this.onLongPress,
  });

  final GenImage image;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onExpand;
  final VoidCallback onSave;
  final VoidCallback onInpaint;
  final VoidCallback on3D;

  /// „Zachovej pózu“ — a new character on this image's pose (internally
  /// still `repose`). Null hides the button.
  final VoidCallback? onRepose;

  /// „Rozhýbat“ — animate this image into a clip. Null (no scene catalog)
  /// hides the button.
  final VoidCallback? onAnimate;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      onLongPress: onLongPress,
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
          // Top-right: the bottom row is full (a 5th slot at right: 148
          // overflows the 2-column tile on 375 pt phones), and "derive a new
          // image from this one" reads fine apart from the file actions.
          // Animate sits left of repose (or takes its place when repose is
          // hidden) — both are "make something new from this image".
          if (onAnimate != null)
            Positioned(
              top: 4,
              right: onRepose != null ? 40 : 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAnimate,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.movie_outlined, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          if (onRepose != null)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRepose,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.directions_walk,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 112,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: on3D,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.view_in_ar, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 76,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onInpaint,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.auto_fix_high, size: 18, color: Colors.white),
                ),
              ),
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

/// Compact read-out of the LoRA strength for the chip: a divergent bar drawn
/// from the zero mark, so a negative strength (an inverted LoRA) reads as a
/// bar growing the other way instead of a merely shorter one. Same colour
/// rule as [_LoraStrengthSlider], which the chip still opens on tap.
class _LoraStrengthBar extends StatelessWidget {
  const _LoraStrengthBar({required this.value});

  final double value;

  /// Fixed track width: the chip sits in a horizontally scrollable row, so
  /// its constraints are unbounded — a LayoutBuilder here would resolve to
  /// an infinite width and blow up the layout.
  static const _trackWidth = 56.0;

  /// Position of [v] on the kMin..kMax track, 0..1.
  static double _t(double v) =>
      (v.clamp(kMinLoraStrength, kMaxLoraStrength) - kMinLoraStrength) /
      (kMaxLoraStrength - kMinLoraStrength);

  @override
  Widget build(BuildContext context) {
    final zero = _t(0);
    final now = _t(value);
    final left = (now < zero ? now : zero) * _trackWidth;
    final width = ((now - zero).abs() * _trackWidth).clamp(1.0, _trackWidth);
    return SizedBox(
      width: _trackWidth,
      height: 3,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Positioned(
            left: left,
            width: width,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: value < 0 ? Colors.orangeAccent : AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Zero mark: without it a bar filled from the left edge would read
          // as "no strength" rather than "strongly negative".
          Positioned(
            left: zero * _trackWidth,
            width: 1,
            top: 0,
            bottom: 0,
            child: const ColoredBox(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

/// Strength control for the selected LoRA, shared by the input-bar picker and
/// the inpaint prompt sheet. Negative values are deliberate: slider-style
/// LoRAs are trained as a direction and invert below zero.
class _LoraStrengthSlider extends StatelessWidget {
  const _LoraStrengthSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Síla LoRA',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: value < 0 ? Colors.orangeAccent : AppTheme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (value != kDefaultLoraStrength) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => onChanged(kDefaultLoraStrength),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.restart_alt,
                        size: 16, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          Slider(
            value: value.clamp(kMinLoraStrength, kMaxLoraStrength),
            min: kMinLoraStrength,
            max: kMaxLoraStrength,
            divisions: 50,
            activeColor: value < 0 ? Colors.orangeAccent : AppTheme.accent,
            onChanged: onChanged,
          ),
          Text(
            value < 0
                ? 'Záporná hodnota otáčí efekt LoRA (u sliderů zamýšlené).'
                : 'Výchozí 0,90. Slabé LoRA zesílíš nad 1, jemné pojistky ztlumíš pod 0,5.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LoraChip extends StatelessWidget {
  const _LoraChip({
    required this.loras,
    required this.family,
    required this.selected,
    required this.onChanged,
    required this.strength,
    required this.onStrengthChanged,
  });

  final List<String> loras;

  /// Active model's lineage — decides how each entry is labelled (the list
  /// itself is already filtered and ordered by [lorasForFamily]).
  final LoraFamily family;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final double strength;
  final ValueChanged<double> onStrengthChanged;

  static String _loraSectionTitle(LoraFit fit, LoraFamily model) =>
      switch (fit) {
        LoraFit.native => 'Pro ${loraFamilyLabel(model)} — doporučené',
        LoraFit.weak => 'Jiná rodina SDXL — slabší nebo jiný efekt',
        LoraFit.unknown => 'Neznámý původ — efekt neověřený',
        LoraFit.incompatible => '',
      };

  String _display(String name) {
    final s = name.replaceAll('.safetensors', '');
    // Shorter than the sheet's full name: the chip also carries the strength
    // read-out, and the chips row competes for width on small phones.
    return s.length > 16 ? '${s.substring(0, 16)}…' : s;
  }

  void _pick(BuildContext context) {
    _dismissKeyboard();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
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
                  final fit = fitOfLora(lora, family);
                  // The list is ordered by fit, so a change of fit starts a
                  // new section — the header says why the rest is different.
                  final newSection =
                      i == 0 || fitOfLora(loras[i - 1], family) != fit;
                  final tile = ListTile(
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
                    subtitle: Text(
                      loraFamilyLabel(familyOfLora(lora)),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () {
                      onChanged(lora);
                      Navigator.of(context).pop();
                    },
                  );
                  if (!newSection) return tile;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                        child: Text(
                          _loraSectionTitle(fit, family),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      tile,
                    ],
                  );
                },
              ),
            ),
            if (selected != null) ...[
              const Divider(height: 1, color: Colors.white12),
              _LoraStrengthSlider(
                value: strength,
                onChanged: (v) {
                  setSheetState(() {});
                  onStrengthChanged(v);
                },
              ),
            ],
          ],
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                if (selected != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    strength.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          strength < 0 ? Colors.orangeAccent : AppTheme.accent,
                    ),
                  ),
                ],
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
            if (selected != null) ...[
              const SizedBox(height: 3),
              _LoraStrengthBar(value: strength),
            ],
          ],
        ),
      ),
    );
  }
}

class _PoseChip extends StatelessWidget {
  const _PoseChip({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  void _pick(BuildContext context) {
    _dismissKeyboard();
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text(
                'Vybrat pózu',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Aplikuje se na generování i úpravy (při úpravě s vyšším denoise).',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                'Žádná póza',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                onChanged(null);
                Navigator.of(context).pop();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2 / 3,
                children: [
                  for (final pose in kPoseTemplates)
                    GestureDetector(
                      onTap: () {
                        onChanged(pose.id);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: pose.id == selected
                                ? AppTheme.accent
                                : Colors.white24,
                            width: pose.id == selected ? 2 : 0.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.asset(pose.asset, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = poseById(selected)?.label;
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: label != null
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: label != null ? AppTheme.accent : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.accessibility_new,
              size: 14,
              color: label != null ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label ?? 'Póza',
              style: TextStyle(
                fontSize: 12,
                color:
                    label != null ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more,
              size: 14,
              color: label != null ? AppTheme.accent : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.modelId,
    required this.models,
    required this.needsTxt2Img,
    required this.needsImg2Img,
    this.needsPose = false,
    required this.onChanged,
  });

  final String modelId;

  /// Models installed on the server (see [ImageStudioState.availableModels]).
  final List<ImageModelSpec> models;

  /// True when the next send would be a fresh text→image generation.
  final bool needsTxt2Img;

  /// True when the next send would refine the selected image (img2img).
  final bool needsImg2Img;

  /// True when the next send is a repose (depth ControlNet → SDXL only).
  final bool needsPose;
  final ValueChanged<String> onChanged;

  bool _isUsable(ImageModelSpec spec) =>
      !(needsTxt2Img && !spec.txt2img) &&
      !(needsImg2Img && !spec.img2img) &&
      !(needsPose && !spec.supportsPose);

  void _pick(BuildContext context) {
    _dismissKeyboard();
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
                'Vybrat model',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: models.length,
                itemBuilder: (_, i) {
                  final spec = models[i];
                  final isSel = spec.id == modelId;
                  // Inpaint-only models (flux-fill) can't be driven from the
                  // input bar at all — the ✨ flow switches to them itself, so
                  // manual selection would only lead to a dead end.
                  final inpaintOnly =
                      spec.inpaint && !spec.txt2img && !spec.img2img;
                  final usable = !inpaintOnly && _isUsable(spec);
                  final hint = inpaintOnly
                      ? 'inpaint — spustíš ikonou ✨ na obrázku'
                      : usable
                          ? spec.capabilityLabel
                          : needsPose
                              ? '${spec.capabilityLabel} — „zachovej pózu“ umí jen SDXL'
                              : spec.img2img
                                  ? '${spec.capabilityLabel} — vyžaduje obrázek'
                                  : '${spec.capabilityLabel} — jen nové generování';
                  final note = spec.styleNote;
                  return Opacity(
                    opacity: usable ? 1.0 : 0.38,
                    child: ListTile(
                      isThreeLine: note != null,
                      enabled: usable,
                      leading: Icon(spec.icon, color: spec.color, size: 22),
                      title: Text(
                        spec.label,
                        style: TextStyle(
                          color:
                              isSel ? AppTheme.accent : AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hint,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          // What the model does with an art-style prompt —
                          // the thing you can't read off the capability list.
                          if (note != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                note,
                                style: TextStyle(
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.75),
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        isSel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color:
                            isSel ? AppTheme.accent : AppTheme.textSecondary,
                        size: 20,
                      ),
                      onTap: () {
                        onChanged(spec.id);
                        Navigator.of(context).pop();
                      },
                    ),
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
    final spec = imageModelById(modelId);
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: spec.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: spec.color, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: 14, color: spec.color),
            const SizedBox(width: 5),
            Text(
              spec.label,
              style: TextStyle(fontSize: 12, color: spec.color),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, size: 14, color: spec.color),
          ],
        ),
      ),
    );
  }
}

/// Input-bar banner for repose mode: the reference thumbnail, what's about
/// to happen, and a way out. Mirrors the selected-state look of the chips.
class _ReposePill extends StatelessWidget {
  const _ReposePill({required this.reference, required this.onCancel});

  final GenImage reference;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent, width: 1),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(reference.filePath),
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              cacheWidth: 56,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.directions_walk, size: 14, color: AppTheme.accent),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Zachovej pózu — popiš novou postavu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onCancel,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Art style appended to every prompt in the session.
class _StyleChip extends StatelessWidget {
  const _StyleChip({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  void _pick(BuildContext context) {
    _dismissKeyboard();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
                child: Text(
                  'Výtvarný styl',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Připojí se za tvůj prompt. Nejlíp funguje při zachování pózy; '
                  'v úpravě zvyš sílu na „silná".',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  selected == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color:
                      selected == null ? AppTheme.accent : AppTheme.textSecondary,
                  size: 20,
                ),
                title: const Text('Bez stylu',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  onChanged(null);
                  Navigator.of(ctx).pop();
                },
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: kStylePresets.length,
                  itemBuilder: (_, i) {
                    final st = kStylePresets[i];
                    final isSel = st.id == selected;
                    return ListTile(
                      leading: Icon(
                        isSel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color:
                            isSel ? AppTheme.accent : AppTheme.textSecondary,
                        size: 20,
                      ),
                      title: Text(
                        st.label,
                        style: TextStyle(
                          color:
                              isSel ? AppTheme.accent : AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        st.block,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        onChanged(st.id);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = styleById(selected);
    return _ChipShell(
      active: style != null,
      icon: Icons.palette_outlined,
      label: style?.label ?? 'Styl',
      onTap: () => _pick(context),
    );
  }
}

/// How hard an img2img round repaints — the difference between a retouch and
/// a restyle.
class _EditStrengthChip extends StatelessWidget {
  const _EditStrengthChip({
    required this.denoise,
    required this.presetDenoise,
    required this.onChanged,
  });

  /// Null = the model preset's own value.
  final double? denoise;
  final double presetDenoise;
  final ValueChanged<double?> onChanged;

  String get _label => switch (denoise) {
        null => 'Úprava: běžná',
        kGentleEditDenoise => 'Úprava: jemná',
        kStyleEditDenoise => 'Úprava: silná',
        _ => 'Úprava: ${denoise!.toStringAsFixed(2)}',
      };

  void _pick(BuildContext context) {
    _dismissKeyboard();
    final options = <(String, String, double?)>[
      ('Jemná', 'drží zdroj, mění detaily (${kGentleEditDenoise.toStringAsFixed(2)})',
          kGentleEditDenoise),
      ('Běžná', 'výchozí pro model (${presetDenoise.toStringAsFixed(2)})', null),
      ('Silná', 'projde i výtvarný styl, pózu drží ControlNet '
          '(${kStyleEditDenoise.toStringAsFixed(2)})', kStyleEditDenoise),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Síla úpravy',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (title, sub, value) in options)
              ListTile(
                leading: Icon(
                  value == denoise
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: value == denoise
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  size: 20,
                ),
                title: Text(title,
                    style: TextStyle(
                      color: value == denoise
                          ? AppTheme.accent
                          : AppTheme.textPrimary,
                    )),
                subtitle: Text(sub,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  onChanged(value);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _ChipShell(
        active: denoise != null,
        icon: Icons.tune,
        label: _label,
        onTap: () => _pick(context),
      );
}

/// Shared chip look: accent-tinted when a non-default value is active.
class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppTheme.accent : AppTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppTheme.accent : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: fg),
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, size: 14, color: fg),
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
  bool get _isReposeMode => widget.state.reposeSourceImageId != null;
  bool get _hasRoot => widget.state.nodes.isNotEmpty;

  String get _hint {
    if (!_hasRoot) return 'Describe an image… (ALL CAPS = negative prompt)';
    if (_isReposeMode) return 'Popiš novou postavu v této póze…';
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
    _dismissKeyboard();
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

    // Predictable mismatch (e.g. FLUX Schnell can't refine) → snackbar instead
    // of a doomed error node; the backends' GenFailed stays as the last net.
    final spec = widget.state.model;
    if (_isReposeMode) {
      if (!spec.supportsPose) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('„Zachovej pózu“ funguje jen na SDXL modelech — vyber jiný.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      _controller.clear();
      await notifier.repose(text);
      return;
    }
    // Inpaint-only model active (after an ✨ round): the input bar can't
    // drive it — point at the flow instead of a generic "pick another model".
    if (spec.inpaint && !spec.txt2img && !spec.img2img) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${spec.label} funguje přes ✨ na obrázku — zamaluj oblast '
            'a popiš, co v ní má být. Pro běžné generování vyber jiný model.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    final wantsTxt2Img = !_hasRoot;
    final wantsImg2Img = _hasRoot && _isRefineMode;
    if ((wantsTxt2Img && !spec.txt2img) || (wantsImg2Img && !spec.img2img)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wantsTxt2Img
                ? '${spec.label} umí jen upravovat obrázky — vyber jiný model.'
                : '${spec.label} neumí img2img — vyber jiný model.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    _dismissKeyboard();
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

    final spec = widget.state.model;
    final loras = widget.state.filteredLoras;
    final selectedLora = widget.state.selectedLora;

    // The current node's own prompt shown as context (the text→image prompt
    // for a root, or the edit instruction that produced this refinement).
    final currentNode = widget.state.current;
    final nodePrompt = (currentNode?.prompt.isNotEmpty ?? false)
        ? currentNode!.prompt
        : null;
    final reposeRef = widget.state.imageById(widget.state.reposeSourceImageId);

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
            // Horizontally scrollable: model + LoRA (with its strength
            // read-out) + pose overflow a 375 pt phone otherwise.
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ModelChip(
                      modelId: spec.id,
                      models: widget.state.availableModels,
                      needsTxt2Img: !_hasRoot,
                      needsImg2Img: _isRefineMode,
                      needsPose: _isReposeMode,
                      onChanged: (id) =>
                          ref.read(imageStudioProvider.notifier).setModel(id),
                    ),
                    const SizedBox(width: 8),
                    _StyleChip(
                      selected: widget.state.selectedStyleId,
                      onChanged: (v) =>
                          ref.read(imageStudioProvider.notifier).setStyle(v),
                    ),
                    // Only meaningful for a ComfyUI img2img round: the NIM
                    // backends have no denoise and inpaint always runs at 1.0.
                    if (_isRefineMode &&
                        !_isReposeMode &&
                        spec.kind == ImageBackendKind.comfyUi &&
                        spec.preset?.ckptName != null) ...[
                      const SizedBox(width: 8),
                      _EditStrengthChip(
                        denoise: widget.state.editDenoise,
                        presetDenoise: spec.preset!.img2imgDenoise,
                        onChanged: (v) => ref
                            .read(imageStudioProvider.notifier)
                            .setEditDenoise(v),
                      ),
                    ],
                    // Repose takes its pose from the reference — a template
                    // would be ignored, so don't offer one.
                    if (spec.supportsPose && !_isReposeMode) ...[
                      const SizedBox(width: 8),
                      _PoseChip(
                        selected: widget.state.selectedPoseId,
                        onChanged: (v) =>
                            ref.read(imageStudioProvider.notifier).setPose(v),
                      ),
                    ],
                    // Last on purpose: rarely used, and the row scrolls — the
                    // chips you reach for every round stay within thumb reach.
                    if (loras.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _LoraChip(
                        loras: loras,
                        family: spec.loraFamily,
                        selected: selectedLora,
                        onChanged: (v) =>
                            ref.read(imageStudioProvider.notifier).setLora(v),
                        strength: widget.state.loraStrength,
                        onStrengthChanged: (v) => ref
                            .read(imageStudioProvider.notifier)
                            .setLoraStrength(v),
                      ),
                    ],
                  ],

                ),
              ),
            ),
            if (reposeRef != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ReposePill(
                  reference: reposeRef,
                  onCancel: () =>
                      ref.read(imageStudioProvider.notifier).cancelRepose(),
                ),
              )
            else if (nodePrompt != null)
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


/// Inline looping player for a ready video node, with save/share/fullscreen.
/// Stateful so the controller lives with the node view; keyed by node id in
/// the caller so switching nodes rebuilds it.
class _VideoNodeView extends StatefulWidget {
  const _VideoNodeView({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<_VideoNodeView> createState() => _VideoNodeViewState();
}

class _VideoNodeViewState extends State<_VideoNodeView> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final ready = _controller.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ready
                ? GestureDetector(
                    onTap: () => setState(() {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    }),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  )
                : const CircularProgressIndicator(color: AppTheme.accent),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => saveVideo(context, widget.path),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Uložit'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
              TextButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(files: [XFile(widget.path, mimeType: 'video/mp4')]),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Sdílet'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        VideoPlayerScreen(path: widget.path, title: widget.title),
                  ),
                ),
                icon: const Icon(Icons.fullscreen, size: 18),
                label: const Text('Celá obrazovka'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
