import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme.dart';
import '../models/message.dart';

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

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
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
          border: isUser
              ? null
              : Border.all(color: Colors.white10, width: 0.5),
        ),
        child: widget.isStreaming && widget.message.content.isEmpty
            ? _buildTypingIndicator()
            : isUser
                ? _buildPlainText()
                : _buildMarkdown(context),
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
                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        return Opacity(
          opacity: 0.3 + _cursorController.value * 0.7,
          child: const Text(
            '▌',
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: 15,
            ),
          ),
        );
      },
    );
  }
}
