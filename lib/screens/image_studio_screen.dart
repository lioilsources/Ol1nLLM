import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/gen_node.dart';
import '../providers/image_studio_provider.dart';
import '../services/image_backend.dart' show kBackendComfyUI;

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
      appBar: AppBar(
        title: const Text('Image Studio'),
        actions: [
          _BackendMenu(state: state),
          if (state.isBusy)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Zrušit generování',
              onPressed: notifier.cancel,
            ),
          if (state.nodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'New image',
              onPressed: state.isBusy ? null : notifier.startOver,
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

/// AppBar picker to switch between the diffusers and ComfyUI backends.
class _BackendMenu extends ConsumerWidget {
  const _BackendMenu({required this.state});

  final ImageStudioState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(imageStudioProvider.notifier);
    final backends = notifier.backends;
    final current = backends.firstWhere((b) => b.id == state.backendId,
        orElse: () => backends.first);

    return PopupMenuButton<String>(
      enabled: !state.isBusy,
      tooltip: 'Backend pro generování',
      onSelected: notifier.setBackend,
      itemBuilder: (context) => [
        for (final b in backends)
          PopupMenuItem<String>(
            value: b.id,
            child: Row(
              children: [
                Icon(
                  b.id == state.backendId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: b.id == state.backendId
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(b.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              current.label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: AppTheme.textSecondary),
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
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
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
        separatorBuilder: (_, _) => const Padding(
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
        if (generating) return _PlaceholderTile(progress: node.progress);
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
  const _PlaceholderTile({this.progress});

  /// 0..1 determinate progress, or null for an indeterminate spinner.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: progress,
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
                color: selected == null ? AppTheme.accent : AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text('Žádná LoRA',
                  style: TextStyle(color: AppTheme.textPrimary)),
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
          color: selected != null ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected != null ? AppTheme.accent : Colors.white24,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined,
                size: 14,
                color: selected != null ? AppTheme.accent : AppTheme.textSecondary),
            const SizedBox(width: 5),
            Text(
              selected != null ? _display(selected!) : 'LoRA',
              style: TextStyle(
                fontSize: 12,
                color: selected != null ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more,
                size: 14,
                color: selected != null ? AppTheme.accent : AppTheme.textSecondary),
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

    final isComfy = widget.state.backendId == kBackendComfyUI;
    final loras = widget.state.availableLoras;
    final selectedLora = widget.state.selectedLora;

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
            if (isComfy && loras.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LoraChip(
                  loras: loras,
                  selected: selectedLora,
                  onChanged: (v) =>
                      ref.read(imageStudioProvider.notifier).setLora(v),
                ),
              ),
            Row(
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
          ],
        ),
      ),
    );
  }
}
