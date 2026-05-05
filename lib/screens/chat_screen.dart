import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../models/persona.dart';
import '../providers/chat_provider.dart';
import '../services/persona_service.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/persona_picker.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(chatProvider, (prev, next) {
      final prevCount = prev?.active?.messages.length ?? 0;
      final nextCount = next.active?.messages.length ?? 0;
      if (nextCount > prevCount || next.isStreaming) {
        _scrollToBottom();
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 10),
          ),
        );
        ref.read(chatProvider.notifier).clearError();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final messages = state.active?.messages ?? [];
    final personaId = state.active?.personaId;
    final personasAsync = ref.watch(personaListProvider);
    final activePersona = personasAsync.maybeWhen(
      data: (list) => _findPersona(list, personaId),
      orElse: () => null,
    );
    final title = _appBarTitle(state.active?.title, activePersona);
    final showPicker = state.active == null ||
        (messages.isEmpty && personaId == null);

    return Scaffold(
      drawer: const ConversationDrawer(),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (activePersona != null) ...[
              Text(activePersona.emoji,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (state.conversations.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: 'New chat',
              onPressed: () => ref.read(chatProvider.notifier).newConversation(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: showPicker
                ? const PersonaPicker()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isLast = index == messages.length - 1;
                      final isStreamingThisMsg = state.isStreaming &&
                          isLast &&
                          message.role == MessageRole.assistant;
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        isStreaming: isStreamingThisMsg,
                      );
                    },
                  ),
          ),
          if (!showPicker) const ChatInputBar(),
        ],
      ),
    );
  }

  static Persona? _findPersona(List<Persona> list, String? id) {
    if (id == null) return null;
    for (final p in list) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String _appBarTitle(String? convTitle, Persona? persona) {
    if (convTitle == null) return 'Ol1nLLM';
    if (convTitle == 'New conversation' && persona != null) return persona.name;
    return convTitle;
  }
}
