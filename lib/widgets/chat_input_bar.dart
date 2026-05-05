import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../providers/chat_provider.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key});

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  static const _continuationPrompt = 'Pokračuj';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    _focusNode.requestFocus();
    await ref.read(chatProvider.notifier).sendMessage(text);
  }

  void _prefillContinuation() {
    if (_controller.text.trim().isNotEmpty) return;
    _controller.value = TextEditingValue(
      text: _continuationPrompt,
      selection:
          const TextSelection.collapsed(offset: _continuationPrompt.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      chatProvider.select((s) => s.pendingContinuation),
      (prev, next) {
        if (next && prev != true) _prefillContinuation();
      },
    );

    final isStreaming = ref.watch(chatProvider).isStreaming;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceAlt,
        border: Border(top: BorderSide(color: Colors.white12)),
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
                enabled: !isStreaming,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Message llm-lab…',
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
                onSubmitted: isStreaming ? null : (_) => _send(),
              ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              isStreaming: isStreaming,
              onSend: _send,
              onStop: () => ref.read(chatProvider.notifier).cancelStream(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _ActionButton({
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          isStreaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          color: Colors.white,
          size: 20,
        ),
        onPressed: isStreaming ? onStop : onSend,
      ),
    );
  }
}
