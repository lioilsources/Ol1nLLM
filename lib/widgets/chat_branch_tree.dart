import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/theme.dart';
import '../core/utils/keyword.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';

/// A compact branch map for the active conversation. Each node is a *turn*
/// (a user message + its reply) labelled with the most relevant word of the
/// prompt. The active root→leaf path is highlighted; tapping a node switches
/// the conversation to that branch so the next message forks from there.
class ChatBranchTree extends ConsumerWidget {
  const ChatBranchTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(chatProvider).active;
    if (conv == null) return const SizedBox.shrink();

    final users = conv.messages
        .where((m) => m.role == MessageRole.user)
        .toList();
    // Nothing worth visualising until there are at least two turns.
    if (users.length < 2) return const SizedBox.shrink();

    final layout = _TurnLayout.compute(conv);
    if (layout.nodes.length < 2) return const SizedBox.shrink();

    final threadUserIds = conv.thread
        .where((m) => m.role == MessageRole.user)
        .map((m) => m.id)
        .toSet();
    final currentUserId = conv.thread
        .where((m) => m.role == MessageRole.user)
        .map((m) => m.id)
        .lastOrNull;

    return Container(
      height: 132,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.5,
        maxScale: 2.0,
        boundaryMargin: const EdgeInsets.all(24),
        child: SizedBox(
          width: layout.canvasSize.width,
          height: layout.canvasSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TurnLinePainter(layout.nodes, threadUserIds),
                ),
              ),
              for (final ln in layout.nodes)
                Positioned(
                  left: ln.position.dx - _TurnLayout.kNodeW / 2,
                  top: ln.position.dy - _TurnLayout.kNodeH / 2,
                  child: _TurnChip(
                    label: keywordOf(ln.message.content),
                    hasImage:
                        conv.replyOf(ln.message.id)?.images.isNotEmpty ?? false,
                    onPath: threadUserIds.contains(ln.message.id),
                    isCurrent: ln.message.id == currentUserId,
                    onTap: () => ref
                        .read(chatProvider.notifier)
                        .selectBranch(ln.message.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Layout ──────────────────────────────────────────────────────────────────

class _TurnNode {
  final Message message;

  /// Id of the parent *turn* (user message), or null for a root turn.
  final String? parentUserId;
  final Offset position;
  _TurnNode(this.message, this.parentUserId, this.position);
}

class _TurnLayout {
  static const double kNodeW = 88.0;
  static const double kNodeH = 30.0;
  static const double kUnitWidth = 100.0;
  static const double kLevelStride = 50.0;

  final List<_TurnNode> nodes;
  final Size canvasSize;
  const _TurnLayout(this.nodes, this.canvasSize);

  static _TurnLayout compute(Conversation conv) {
    final byId = {for (final m in conv.messages) m.id: m};
    final users = conv.messages
        .where((m) => m.role == MessageRole.user)
        .toList();
    if (users.isEmpty) return const _TurnLayout([], Size.zero);

    // Nearest ancestor that is a user message = the turn's tree-parent.
    String? userParent(Message u) {
      var pid = u.parentId;
      while (pid != null) {
        final m = byId[pid];
        if (m == null) return null;
        if (m.role == MessageRole.user) return m.id;
        pid = m.parentId;
      }
      return null;
    }

    final childrenMap = <String?, List<Message>>{};
    for (final u in users) {
      childrenMap.putIfAbsent(userParent(u), () => []).add(u);
    }
    for (final list in childrenMap.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final roots = childrenMap[null] ?? const [];
    if (roots.isEmpty) return const _TurnLayout([], Size.zero);

    final subtreeWidths = <String, int>{};
    int calcWidth(Message n) {
      final kids = childrenMap[n.id] ?? const [];
      if (kids.isEmpty) return subtreeWidths[n.id] = 1;
      final w = kids.fold(0, (acc, k) => acc + calcWidth(k));
      return subtreeWidths[n.id] = w;
    }

    for (final r in roots) {
      calcWidth(r);
    }
    final totalUnits = roots.fold(0, (acc, r) => acc + subtreeWidths[r.id]!);

    final result = <_TurnNode>[];
    double maxY = 0;
    void assign(Message n, String? parentUserId, double leftX, int level) {
      final w = subtreeWidths[n.id]! * kUnitWidth;
      final y = kNodeH / 2 + level * kLevelStride;
      if (y > maxY) maxY = y;
      result.add(_TurnNode(n, parentUserId, Offset(leftX + w / 2, y)));
      var cursor = leftX;
      for (final k in childrenMap[n.id] ?? const <Message>[]) {
        assign(k, n.id, cursor, level + 1);
        cursor += subtreeWidths[k.id]! * kUnitWidth;
      }
    }

    var cursor = 0.0;
    for (final r in roots) {
      assign(r, null, cursor, 0);
      cursor += subtreeWidths[r.id]! * kUnitWidth;
    }

    return _TurnLayout(
      result,
      Size(totalUnits * kUnitWidth, maxY + kNodeH / 2 + 12),
    );
  }
}

class _TurnLinePainter extends CustomPainter {
  _TurnLinePainter(this.nodes, this.onPath)
    : _posById = {for (final n in nodes) n.message.id: n.position};

  final List<_TurnNode> nodes;
  final Set<String> onPath;
  final Map<String, Offset> _posById;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in nodes) {
      final parentPos =
          n.parentUserId == null ? null : _posById[n.parentUserId];
      if (parentPos == null) continue;
      final lit = onPath.contains(n.message.id);
      final paint = Paint()
        ..color = lit ? AppTheme.accent.withValues(alpha: 0.8) : Colors.white24
        ..strokeWidth = lit ? 2 : 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(parentPos.dx, parentPos.dy + _TurnLayout.kNodeH / 2),
        Offset(n.position.dx, n.position.dy - _TurnLayout.kNodeH / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TurnLinePainter old) =>
      old.nodes != nodes || old.onPath != onPath;
}

class _TurnChip extends StatelessWidget {
  const _TurnChip({
    required this.label,
    required this.hasImage,
    required this.onPath,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool hasImage;
  final bool onPath;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _TurnLayout.kNodeW,
        height: _TurnLayout.kNodeH,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? AppTheme.accent
              : onPath
                  ? AppTheme.accent.withValues(alpha: 0.14)
                  : AppTheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isCurrent
                ? AppTheme.accent
                : onPath
                    ? AppTheme.accent.withValues(alpha: 0.6)
                    : Colors.white24,
            width: isCurrent ? 2 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasImage ? Icons.image_outlined : Icons.chat_bubble_outline,
              size: 12,
              color: isCurrent ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isCurrent ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
