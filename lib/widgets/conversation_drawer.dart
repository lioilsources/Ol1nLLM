import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/persona.dart';
import '../providers/chat_provider.dart';
import '../services/persona_service.dart';

class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final personas =
        ref.watch(personaListProvider).maybeWhen(data: (l) => l, orElse: () => const <Persona>[]);

    String? emojiFor(String? id) {
      if (id == null) return null;
      for (final p in personas) {
        if (p.id == id) return p.emoji;
      }
      return null;
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () {
                  notifier.newConversation();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New chat'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'No conversations yet',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: state.conversations.length,
                      itemBuilder: (context, index) {
                        final conv = state.conversations[index];
                        final isActive = conv.id == state.activeId;
                        final emoji = emojiFor(conv.personaId);
                        return Dismissible(
                          key: ValueKey(conv.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.red.shade900,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => notifier.deleteConversation(conv.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor: Colors.white10,
                            leading: emoji == null
                                ? null
                                : Text(emoji,
                                    style: const TextStyle(fontSize: 20)),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            onTap: () {
                              notifier.selectConversation(conv.id);
                              Navigator.pop(context);
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
}
