import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/gen_node.dart';
import '../providers/image_studio_provider.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Studio'),
        actions: [
          if (state.nodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'New image',
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(imageStudioProvider.notifier).startOver(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (state.path.length > 1) _Breadcrumb(state: state),
          Expanded(
            child: current == null
                ? const _EmptyHint()
                : _NodeGrid(node: current, selectedId: state.selectedImageId),
          ),
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
              'Describe an image to generate four variants.\n'
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

class _Breadcrumb extends ConsumerWidget {
  const _Breadcrumb({required this.state});

  final ImageStudioState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(imageStudioProvider.notifier);
    final path = state.path;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: path.length,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right,
              size: 16, color: AppTheme.textSecondary),
        ),
        itemBuilder: (context, i) {
          final node = path[i];
          final isCurrent = node.id == state.currentNodeId;
          final label = node.prompt.isEmpty
              ? (node.isRoot ? 'prompt' : 'edit')
              : node.prompt;
          return ActionChip(
            avatar: Icon(
              node.isRoot ? Icons.auto_awesome : Icons.brush_outlined,
              size: 14,
              color: isCurrent ? Colors.white : AppTheme.textSecondary,
            ),
            label: Text(
              label.length > 22 ? '${label.substring(0, 22)}…' : label,
              style: TextStyle(
                color: isCurrent ? Colors.white : AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            backgroundColor:
                isCurrent ? AppTheme.accent : AppTheme.surface,
            side: BorderSide.none,
            onPressed: isCurrent ? null : () => notifier.navigateTo(node.id),
          );
        },
      ),
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
              const Icon(Icons.error_outline,
                  size: 40, color: AppTheme.textSecondary),
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
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              ),
            ],
          ),
        ),
      );
    }

    final generating = node.status == GenStatus.generating;
    final tiles = generating ? kVariantCount : node.images.length;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: tiles,
      itemBuilder: (context, i) {
        if (generating) return const _PlaceholderTile();
        final img = node.images[i];
        return _ImageTile(
          image: img,
          selected: img.id == selectedId,
          onSelect: () =>
              ref.read(imageStudioProvider.notifier).selectImage(img.id),
          onExpand: () => _showFullscreen(context, img.b64),
        );
      },
    );
  }

  void _showFullscreen(BuildContext context, String b64) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          child: Center(
            child: Image.memory(base64Decode(b64), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.selected,
    required this.onSelect,
    required this.onExpand,
  });

  final GenImage image;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onExpand;

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
              child: Image.memory(base64Decode(image.b64), fit: BoxFit.cover),
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

class _StudioInputBar extends ConsumerStatefulWidget {
  const _StudioInputBar({required this.state});

  final ImageStudioState state;

  @override
  ConsumerState<_StudioInputBar> createState() => _StudioInputBarState();
}

class _StudioInputBarState extends ConsumerState<_StudioInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.state.isBusy) return;
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
    final canSend = !isBusy && _controller.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Scrollbar(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !isBusy,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: isBusy ? null : (_) => _send(),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: _hint,
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
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
              child: isBusy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: canSend ? Colors.white : AppTheme.textSecondary,
                        size: 20,
                      ),
                      onPressed: canSend ? _send : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
