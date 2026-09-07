import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/image_session.dart';
import '../models/learned_lookup.dart';
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
                            trailing: _ExportIcon(
                              session: session,
                              exporting:
                                  state.exportingSessionId == session.id,
                              progress: state.exportProgress,
                              enabled: state.exportingSessionId == null &&
                                  session.readyImageCount > 0,
                              onTap: () =>
                                  notifier.exportSession(session.id),
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
            const _KnowledgeFooter(),
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

/// Per-session FINETUNE export trigger + status: upload icon (never exported
/// or new images since), green check (up to date), or a progress ring while
/// this session is being exported.
class _ExportIcon extends StatelessWidget {
  const _ExportIcon({
    required this.session,
    required this.exporting,
    required this.progress,
    required this.enabled,
    required this.onTap,
  });

  final ImageSession session;
  final bool exporting;
  final double? progress;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (exporting) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(value: progress, strokeWidth: 2),
          ),
        ),
      );
    }
    final upToDate = !session.isExportStale;
    return IconButton(
      icon: Icon(
        upToDate ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        size: 20,
        color: upToDate ? Colors.greenAccent : AppTheme.textSecondary,
      ),
      tooltip: upToDate
          ? 'Exportováno do FINETUNE gallery'
          : 'Exportovat do FINETUNE gallery',
      onPressed: enabled ? onTap : null,
    );
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

/// Kdy se appka naposled něco naučila.
///
/// Tichá řádka, ale jediná svého druhu: bez ní nejde poznat, že někdo
/// releasoval bez `lab learn` a appka celé měsíce jede na znalosti, která už
/// neplatí. Proto se stárnutí zvýrazňuje — ne aby otravovalo, ale protože
/// mlčení je tady ta horší varianta.
class _KnowledgeFooter extends StatelessWidget {
  const _KnowledgeFooter();

  @override
  Widget build(BuildContext context) {
    final snapshot = kLearned.snapshotTime;
    final stale = kLearned.isStaleAt(DateTime.now());
    final text = snapshot == null
        // Not a failure: a fresh clone, or a corpus that has not been rated
        // enough for anything to be decided yet. The app runs on its own
        // constants and says so.
        ? 'Znalost: zatím žádná — appka jede na výchozích hodnotách'
        : 'Znalost: ${snapshot.day}. ${snapshot.month}. ${snapshot.year}'
            ' · ${kLearned.ratedImages} hodnocení';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Icon(
            stale ? Icons.update_disabled : Icons.school_outlined,
            size: 13,
            color: stale ? Colors.orangeAccent : AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              stale ? '$text — starší než 30 dní' : text,
              style: TextStyle(
                fontSize: 11,
                color: stale ? Colors.orangeAccent : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
