import 'dart:convert';
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
            isUser ? _buildPlainText() : _buildMarkdown(context),
          ],
        ],
      );
    }

    // User input with an attached image (base64 in images list shown above)
    return isUser ? _buildPlainText() : _buildMarkdown(context);
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
        return Opacity(
          opacity: 0.3 + _cursorController.value * 0.7,
          child: const Text(
            '▌',
            style: TextStyle(color: AppTheme.accent, fontSize: 15),
          ),
        );
      },
    );
  }
}
