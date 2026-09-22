import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/theme.dart';
import '../models/story_project.dart';
import '../providers/story_studio_provider.dart';
import 'story_setup_screen.dart';
import 'video_player_screen.dart' show VideoPlayerScreen, saveVideo;

/// StoryStudio — minute-long anime stories with your own characters: pick a
/// story, cast its roles, check the keyframes, get a narrated video with
/// music. Rendering runs on SPARK (`video-stack/tools/story.py`) for most of
/// an hour; the app only follows the job and survives being closed.
class StoryStudioScreen extends ConsumerStatefulWidget {
  const StoryStudioScreen({super.key});

  @override
  ConsumerState<StoryStudioScreen> createState() => _StoryStudioScreenState();
}

class _StoryStudioScreenState extends ConsumerState<StoryStudioScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(storyStudioProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
          ),
        );
        ref.read(storyStudioProvider.notifier).clearError();
      }
      if (next.info != null && next.info != prev?.info) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.info!)));
        ref.read(storyStudioProvider.notifier).clearInfo();
      }
    });
    // The catalog also says which roles have a default picture now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(storyStudioProvider.notifier).loadCatalog();
    });
  }

  void _openProjects() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ProjectsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storyStudioProvider);
    final project = state.active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Studio'),
        actions: [
          if (state.projects.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.video_library_outlined),
              tooltip: 'Moje příběhy',
              onPressed: _openProjects,
            ),
          if (project != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nový příběh',
              onPressed: () =>
                  ref.read(storyStudioProvider.notifier).newStory(),
            ),
        ],
      ),
      body: project == null
          ? const _CatalogView()
          : _ProjectView(key: ValueKey(project.id), project: project),
    );
  }
}

// ── Catalog ─────────────────────────────────────────────────────────────────

class _CatalogView extends ConsumerWidget {
  const _CatalogView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storyStudioProvider);
    final n = ref.read(storyStudioProvider.notifier);
    return RefreshIndicator(
      onRefresh: n.loadCatalog,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Vyber příběh a obsaď ho svými postavičkami. Studio nakreslí '
              'záběry, rozanimuje je a přidá vypravěče s hudbou — minutové '
              'video trvá necelou hodinu a poběží i se zavřenou appkou.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (state.catalog.isEmpty && state.catalogLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            ),
          if (state.catalog.isEmpty && state.catalogError != null)
            _Card(
              child: Column(
                children: [
                  Text(
                    state.catalogError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  TextButton(
                    onPressed: n.loadCatalog,
                    child: const Text('Zkusit znovu'),
                  ),
                ],
              ),
            ),
          for (final s in state.catalog) _StoryCard(story: s),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final StoryInfo story;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Card(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StorySetupScreen(story: story)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              story.title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              story.desc,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in story.characters)
                  _Pill(
                    r.name,
                    icon: r.hero ? Icons.star_outline : Icons.person_outline,
                  ),
                _Pill(formatStorySeconds(story.seconds), icon: Icons.timer),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Project ─────────────────────────────────────────────────────────────────

class _ProjectView extends ConsumerWidget {
  const _ProjectView({super.key, required this.project});

  final StoryProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final story = ref.watch(storyStudioProvider).story(project.storyId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _ProjectHeader(project: project),
        const SizedBox(height: 12),
        switch (project.status) {
          StoryStatus.submitting ||
          StoryStatus.queued ||
          StoryStatus.running => _ProgressCard(project: project),
          StoryStatus.review => _ReviewSection(project: project),
          StoryStatus.done => _ResultCard(project: project),
          StoryStatus.failed => _FailedCard(project: project),
        },
        if (story != null && story.script.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Card(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text(
                'Scénář',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: [
                for (final shot in story.script)
                  StoryShotRow(shot: shot, lang: project.lang),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final StoryProject project;

  @override
  Widget build(BuildContext context) {
    final meta = [
      kStoryLanguages[project.lang] ?? project.lang,
      if (project.hd) 'vyšší rozlišení',
      if (project.review) 's kontrolou záběrů',
    ].join(' · ');
    return _Card(
      child: Row(
        children: [
          for (final c in project.cast.values) ...[
            _CastAvatar(cast: c),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.cast});

  static const size = 44.0;
  final StoryCast cast;

  @override
  Widget build(BuildContext context) {
    final path = cast.path;
    return Tooltip(
      message: cast.usesDefault ? '${cast.name} (výchozí)' : cast.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: path != null
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => _placeholder(),
                )
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppTheme.surfaceAlt,
    child: const Icon(Icons.person_outline, color: AppTheme.textSecondary),
  );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.project});

  final StoryProject project;

  @override
  Widget build(BuildContext context) {
    final waitsForReview = project.review && project.stage == 'keyframes';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.phase == 'download'
                ? 'Stahuji hotové video…'
                : storyProgressLabel(project),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 3,
            value: project.phase == 'download'
                ? null
                : storyProgressFraction(project),
            color: AppTheme.accent,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 10),
          Text(
            waitsForReview
                ? 'Po nakreslení záběrů se zastaví a počká na tvoje schválení. '
                      'Appku můžeš zatím zavřít.'
                : 'Odhad ~${project.minutesEst} min na GPU (bez fronty). '
                      'Appku můžeš zavřít, video se dopočítá na serveru.',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedCard extends ConsumerWidget {
  const _FailedCard({required this.project});

  final StoryProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.error ?? 'Render selhal',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () =>
                  ref.read(storyStudioProvider.notifier).retry(project.id),
              child: Text(
                project.serverFailed || project.jobId == null
                    ? 'Spustit znovu'
                    : 'Zkusit znovu',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Review ──────────────────────────────────────────────────────────────────

/// Keyframes are painted and the job waits. Tap shots to repaint them (new
/// seed), or edit a shot's description; otherwise approve and animate.
class _ReviewSection extends ConsumerStatefulWidget {
  const _ReviewSection({required this.project});

  final StoryProject project;

  @override
  ConsumerState<_ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends ConsumerState<_ReviewSection> {
  final Set<String> _selected = {};
  final Map<String, String> _edits = {};
  bool _busy = false;

  StoryProject get p => widget.project;

  Future<void> _editShot(StoryKeyframe kf) async {
    final controller = TextEditingController(text: _edits[kf.id] ?? kf.keyframe);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Záběr ${kf.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (kf.action.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  kf.action,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            TextField(
              controller: controller,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                helperText: 'Co má být na obrázku — anglicky, jako prompt',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Překreslit takhle'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    setState(() {
      if (text.isEmpty || text == kf.keyframe) {
        _edits.remove(kf.id);
      } else {
        _edits[kf.id] = text;
        _selected.remove(kf.id); // the edit repaints it anyway
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final n = ref.read(storyStudioProvider.notifier);
    if (_selected.isEmpty && _edits.isEmpty) {
      await n.approve(p.id);
    } else {
      await n.repaint(p.id, shots: {..._selected}, edits: {..._edits});
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
      _edits.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyframes = ref.watch(
      storyStudioProvider.select((s) => s.keyframes[p.id]),
    );
    final changes = {..._selected, ..._edits.keys}.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Text(
            'Záběry jsou nakreslené. Než se začnou animovat '
            '(~${p.minutesEst} min), projdi je. Klepnutím označíš záběr '
            'k překreslení, tužkou upravíš jeho popis.',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (keyframes == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const CircularProgressIndicator(color: AppTheme.accent),
                TextButton(
                  onPressed: () => ref
                      .read(storyStudioProvider.notifier)
                      .reloadKeyframes(p.id),
                  child: const Text('Načíst záběry'),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.42,
            ),
            itemCount: keyframes.length,
            itemBuilder: (_, i) {
              final kf = keyframes[i];
              return _KeyframeTile(
                project: p,
                keyframe: kf,
                selected: _selected.contains(kf.id),
                edited: _edits.containsKey(kf.id),
                onTap: () => setState(() {
                  if (_edits.remove(kf.id) == null &&
                      !_selected.remove(kf.id)) {
                    _selected.add(kf.id);
                  }
                }),
                onEdit: () => _editShot(kf),
              );
            },
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: keyframes == null || _busy ? null : _submit,
          icon: Icon(changes == 0 ? Icons.play_arrow : Icons.brush_outlined),
          label: Text(
            changes == 0
                ? 'Schválit a animovat'
                : 'Překreslit $changes ${_shotsWord(changes)}',
          ),
        ),
        if (changes > 0)
          TextButton(
            onPressed: () => setState(() {
              _selected.clear();
              _edits.clear();
            }),
            child: const Text('Zrušit výběr'),
          ),
      ],
    );
  }

  static String _shotsWord(int n) => switch (n) {
    1 => 'záběr',
    2 || 3 || 4 => 'záběry',
    _ => 'záběrů',
  };
}

class _KeyframeTile extends ConsumerWidget {
  const _KeyframeTile({
    required this.project,
    required this.keyframe,
    required this.selected,
    required this.edited,
    required this.onTap,
    required this.onEdit,
  });

  final StoryProject project;
  final StoryKeyframe keyframe;
  final bool selected;
  final bool edited;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marked = selected || edited;
    final narration = keyframe.narrationFor(project.lang);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: marked ? AppTheme.accent : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 768 / 1344,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List>(
                    // Same Future per repaint round (cached in the provider).
                    future: ref
                        .read(storyStudioProvider.notifier)
                        .keyframeImage(project, keyframe.id),
                    builder: (_, snap) {
                      if (snap.hasData) {
                        return Image.memory(snap.data!, fit: BoxFit.cover);
                      }
                      if (snap.hasError) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppTheme.textSecondary,
                          ),
                        );
                      }
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _Pill(keyframe.id, dark: true),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: 'Upravit popis',
                      onPressed: onEdit,
                      icon: const CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.edit, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                  if (marked)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _Pill(
                        edited ? 'nový popis' : 'překreslit',
                        icon: edited ? Icons.edit_note : Icons.refresh,
                        accent: true,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      keyframe.action,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    if (narration.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '„$narration"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result ──────────────────────────────────────────────────────────────────

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.project});

  final StoryProject project;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  /// Variant being downloaded (`sub` / `16x9`), for the spinner.
  String? _loading;

  StoryProject get p => widget.project;

  void _play(String path, String title) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(path: path, title: title),
    ),
  );

  Future<void> _variant(String variant, String label) async {
    if (_loading != null) return;
    setState(() => _loading = variant);
    final path = await ref
        .read(storyStudioProvider.notifier)
        .variantPath(p.id, variant);
    if (!mounted) return;
    setState(() => _loading = null);
    if (path != null) _play(path, '${p.title} · $label');
  }

  @override
  Widget build(BuildContext context) {
    final path = p.videoPath;
    if (path == null) return _FailedCard(project: p);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _play(path, p.title),
            icon: const Icon(Icons.play_arrow),
            label: Text('Přehrát (${formatStorySeconds(p.seconds)})'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => saveVideo(context, path),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Do Fotek'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(files: [XFile(path, mimeType: 'video/mp4')]),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Sdílet'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Další verze',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final (variant, label, icon) in const [
                ('sub', 's titulky', Icons.subtitles_outlined),
                ('16x9', 'na šířku 16:9', Icons.crop_landscape),
              ])
                ActionChip(
                  avatar: _loading == variant
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon, size: 16),
                  label: Text(label),
                  onPressed: _loading == null
                      ? () => _variant(variant, label)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Projects ────────────────────────────────────────────────────────────────

class _ProjectsSheet extends ConsumerWidget {
  const _ProjectsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storyStudioProvider);
    final n = ref.read(storyStudioProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: AppTheme.accent),
              title: const Text('Nový příběh'),
              onTap: () {
                n.newStory();
                Navigator.of(context).pop();
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in state.projects)
                    ListTile(
                      selected: p.id == state.activeId,
                      selectedColor: AppTheme.accent,
                      leading: Icon(_statusIcon(p.status)),
                      title: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _statusText(p),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Smazat',
                        onPressed: () => _confirmDelete(context, ref, p),
                      ),
                      onTap: () {
                        n.selectProject(p.id);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(StoryStatus s) => switch (s) {
    StoryStatus.done => Icons.movie_outlined,
    StoryStatus.review => Icons.rate_review_outlined,
    StoryStatus.failed => Icons.error_outline,
    _ => Icons.hourglass_top,
  };

  static String _statusText(StoryProject p) {
    final d = p.createdAt;
    final date = '${d.day}. ${d.month}.';
    final status = switch (p.status) {
      StoryStatus.done => 'hotovo · ${formatStorySeconds(p.seconds)}',
      StoryStatus.review => 'čeká na schválení záběrů',
      StoryStatus.failed => 'selhalo',
      _ => storyProgressLabel(p),
    };
    return '$date · $status';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StoryProject p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Smazat příběh?'),
        content: Text(
          p.inFlight
              ? '„${p.title}" zmizí z telefonu. Na serveru se ale '
                    'dopočítá — zastavit ho odsud nejde.'
              : '„${p.title}" a jeho video zmizí z telefonu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Smazat',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(storyStudioProvider.notifier).deleteProject(p.id);
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon, this.dark = false, this.accent = false});

  final String text;
  final IconData? icon;
  final bool dark;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? Colors.black : AppTheme.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? AppTheme.accent
            : dark
            ? Colors.black54
            : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: fg, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
