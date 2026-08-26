import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme.dart';
import '../models/message.dart';
import 'source_list.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  /// Seconds spent waiting for the first token. The library backend can spend
  /// minutes on retrieval + prefill before anything arrives, and a bare
  /// blinking cursor for that long reads as a frozen app.
  Timer? _waitTimer;
  int _waitSeconds = 0;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _syncWaitTimer();
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWaitTimer();
  }

  bool get _isWaiting =>
      widget.isStreaming &&
      widget.message.content.isEmpty &&
      widget.message.images.isEmpty;

  void _syncWaitTimer() {
    if (_isWaiting) {
      _waitTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _waitSeconds++),
      );
    } else if (_waitTimer != null) {
      _waitTimer!.cancel();
      _waitTimer = null;
      _waitSeconds = 0;
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.userBubble : AppTheme.aiBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: Colors.white10, width: 0.5),
        ),
        child: _buildContent(context, isUser),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    final msg = widget.message;
    final hasImages = msg.images.isNotEmpty;
    final hasText = msg.content.isNotEmpty;

    // Typing indicator: streaming, no content, no images yet
    if (widget.isStreaming && !hasText && !hasImages) {
      return _buildTypingIndicator();
    }

    // Progress status text while job is running (streaming + text but no images)
    if (widget.isStreaming && hasText && !hasImages) {
      return _buildStatusText(msg.content);
    }

    // Images (with optional caption)
    if (hasImages) {
      return Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...msg.images.map(_buildImage),
          if (hasText) ...[
            const SizedBox(height: 8),
            isUser ? _buildPlainText() : _buildAssistantBody(context),
          ],
        ],
      );
    }

    // User input with an attached image (base64 in images list shown above)
    return isUser ? _buildPlainText() : _buildAssistantBody(context);
  }

  /// Assistant answer plus, for library (RAG) replies, the citations it was
  /// built from. Held back while streaming — they only arrive with the final
  /// event, so rendering mid-stream would make the section pop in at the end.
  Widget _buildAssistantBody(BuildContext context) {
    final sources = widget.message.sources;
    if (sources.isEmpty || widget.isStreaming) return _buildMarkdown(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMarkdown(context),
        SourceList(sources: sources),
      ],
    );
  }

  Widget _buildImage(String base64) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(base64),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 14,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildPlainText() {
    return SelectableText(
      widget.message.content,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 15,
        height: 1.5,
      ),
    );
  }

  Widget _buildMarkdown(BuildContext context) {
    return AnimatedBuilder(
      animation: _cursorController,
      builder: (context, _) {
        final showCursor = widget.isStreaming;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MarkdownBody(
              data: widget.message.content,
              selectable: true,
              styleSheet: AppTheme.markdownStyle(context),
              onTapLink: (text, href, title) async {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            if (showCursor)
              Opacity(
                opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                child: const Text(
                  '▌',
                  style: TextStyle(color: AppTheme.accent, fontSize: 15),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedBuilder(
      animation: _cursorController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.3 + _cursorController.value * 0.7,
              child: const Text(
                '▌',
                style: TextStyle(color: AppTheme.accent, fontSize: 15),
              ),
            ),
            // Only once the wait is long enough to look like a hang — a fast
            // reply should not flash a counter.
            if (_waitSeconds >= 3) ...[
              const SizedBox(width: 8),
              Text(
                'hledám… $_waitSeconds s',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
