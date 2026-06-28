import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/image_session.dart';
import '../providers/image_studio_provider.dart';

class ImageSessionDrawer extends ConsumerWidget {
  const ImageSessionDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageStudioProvider);
    final notifier = ref.read(imageStudioProvider.notifier);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () {
                  notifier.newSession();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New session'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.sessions.isEmpty
                  ? const Center(
                      child: Text(
                        'No saved sessions yet',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: state.sessions.length,
                      itemBuilder: (context, index) {
                        final session = state.sessions[index];
                        final isActive = session.id == state.activeSessionId;
                        return Dismissible(
                          key: ValueKey(session.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.red.shade900,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => notifier.deleteSession(session.id),
                          child: ListTile(
                            selected: isActive,
                            selectedTileColor: Colors.white10,
                            leading: _SessionThumbnail(session: session),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              _formatDate(session.updatedAt),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            onTap: () {
                              notifier.selectSession(session.id);
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

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'dnes';
    if (diff == 1) return 'včera';
    final yearSuffix = dt.year != now.year ? ' ${dt.year}' : '';
    return '${dt.day}. ${dt.month}.$yearSuffix';
  }
}

class _SessionThumbnail extends StatelessWidget {
  const _SessionThumbnail({required this.session});

  final ImageSession session;

  @override
  Widget build(BuildContext context) {
    final path = session.thumbnailFilePath;
    if (path == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.auto_awesome, size: 20, color: AppTheme.textSecondary),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        cacheWidth: 40,
        cacheHeight: 40,
      ),
    );
  }
}
