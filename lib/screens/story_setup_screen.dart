import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/theme.dart';
import '../models/story_project.dart';
import '../providers/story_studio_provider.dart';

/// One story before it starts: who plays which role (your own characters,
/// or the server's default picture where it has one), narrator language,
/// review of keyframes and quality — and the screenplay to read first.
class StorySetupScreen extends ConsumerStatefulWidget {
  const StorySetupScreen({super.key, required this.story});

  final StoryInfo story;

  @override
  ConsumerState<StorySetupScreen> createState() => _StorySetupScreenState();
}

class _StorySetupScreenState extends ConsumerState<StorySetupScreen> {
  final _picker = ImagePicker();

  /// role → picked image (temporary path until the provider copies it).
  final Map<String, String> _cast = {};

  /// role → who the picture shows. Prefilled from the screenplay, so leaving
  /// it alone keeps the story as written; rewriting it recasts the role —
  /// „kocour Mourek" → „ježek Bodlinka" swaps the animal everywhere, in the
  /// pictures, in what the narrator says and in the subtitles.
  final Map<String, TextEditingController> _who = {};

  TextEditingController _whoCtl(StoryRole role) =>
      _who.putIfAbsent(role.role, () => TextEditingController(text: role.name));

  @override
  void dispose() {
    for (final c in _who.values) {
      c.dispose();
    }
    super.dispose();
  }
  late String _lang = widget.story.languages.contains('cs')
      ? 'cs'
      : widget.story.languages.first;

  /// Stop after keyframes and wait for approval — an hour of GPU is not
  /// spent on shots that came out wrong. On by default.
  bool _review = true;
  bool _hd = false;
  bool _starting = false;

  StoryInfo get story => widget.story;

  bool get _ready => story.characters.every(
    (r) => _cast.containsKey(r.role) || r.hasDefault,
  );

  Future<void> _pick(StoryRole role) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Z Fotek'),
              onTap: () => Navigator.of(ctx).pop('photos'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Ze souborů'),
              onTap: () => Navigator.of(ctx).pop('files'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    String? path;
    try {
      if (source == 'photos') {
        // The server scales the reference for Kontext anyway; 1536 px keeps
        // the face detail without sending tens of MB through Cloudflare.
        final file = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1536,
          maxHeight: 1536,
          imageQuality: 92,
        );
        path = file?.path;
      } else {
        final file = await FilePicker.pickFile(type: FileType.image);
        path = file?.path;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Obrázek se nepodařilo načíst: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }
    if (path == null || !mounted) return;
    setState(() => _cast[role.role] = path!);
  }

  Future<void> _start() async {
    if (!_ready || _starting) return;
    HapticFeedback.lightImpact();
    setState(() => _starting = true);
    await ref
        .read(storyStudioProvider.notifier)
        .start(
          story,
          castPaths: {for (final r in story.characters) r.role: _cast[r.role]},
          castWho: {
            for (final r in story.characters)
              if ((_who[r.role]?.text.trim() ?? '') != r.name)
                r.role: _who[r.role]!.text.trim(),
          },
          lang: _lang,
          review: _review,
          hd: _hd,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _hd ? story.minutesEstHd : story.minutesEst;
    return Scaffold(
      appBar: AppBar(title: Text(story.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.desc,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatStorySeconds(story.seconds)} · ${story.shots} záběrů'
                  ' · vypravěč, hudba, titulky',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Kdo hraje'),
          for (final r in story.characters)
            _CastTile(
              role: r,
              path: _cast[r.role],
              who: _whoCtl(r),
              onPick: () => _pick(r),
              onClear: () => setState(() {
                _cast.remove(r.role);
                _whoCtl(r).text = r.name;
              }),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'Nejlíp funguje celá postava zepředu na jednoduchém pozadí. '
              'Ze vzhledu postavy se nakreslí všech 12 záběrů. Když je na '
              'obrázku někdo jiný, než čeká scénář, přepiš, kdo to je — '
              'příběh se podle toho přepíše.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Nastavení'),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (story.languages.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Vypravěč',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final l in story.languages)
                              ButtonSegment(
                                value: l,
                                label: Text(kStoryLanguages[l] ?? l),
                              ),
                          ],
                          selected: {_lang},
                          onSelectionChanged: (s) =>
                              setState(() => _lang = s.first),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  value: _review,
                  onChanged: (v) => setState(() => _review = v),
                  title: const Text('Zkontrolovat záběry před animací'),
                  subtitle: const Text(
                    'Po nakreslení záběrů se zastaví a počká na tebe. '
                    'Nepovedené záběry jde nechat překreslit.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SwitchListTile(
                  value: _hd,
                  onChanged: (v) => setState(() => _hd = v),
                  title: const Text('Vyšší rozlišení'),
                  subtitle: Text(
                    '~${story.minutesEstHd} min místo ~${story.minutesEst} min',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _ready && !_starting ? _start : null,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.movie_filter_outlined),
            label: Text(
              _ready
                  ? 'Spustit (~$minutes min na GPU)'
                  : 'Vyber obrázky postav',
            ),
          ),
          const SizedBox(height: 24),
          _ScriptSection(story: story, lang: _lang),
        ],
      ),
    );
  }
}

class _CastTile extends StatelessWidget {
  const _CastTile({
    required this.role,
    required this.path,
    required this.who,
    required this.onPick,
    required this.onClear,
  });

  final StoryRole role;
  final String? path;
  final TextEditingController who;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final picked = path != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 96,
                  child: picked
                      ? Image.file(File(path!), fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.surfaceAlt,
                          child: Icon(
                            role.hasDefault
                                ? Icons.person_outline
                                : Icons.add_photo_alternate_outlined,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          role.name,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (role.hero) ...[
                        const SizedBox(width: 6),
                        const _Badge('hlavní postava'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role.lookOrDesc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onPick,
                        child: Text(picked ? 'Změnit' : 'Vybrat obrázek'),
                      ),
                      if (picked) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: AppTheme.textSecondary,
                          ),
                          onPressed: onClear,
                          child: Text(
                            role.hasDefault ? 'Použít výchozí' : 'Odebrat',
                          ),
                        ),
                      ] else if (role.hasDefault) ...[
                        const SizedBox(width: 12),
                        const Text(
                          'jinak výchozí ze serveru',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (picked) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: who,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Kdo to je',
                        helperText: 'např. ježek Bodlinka',
                        helperStyle: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screenplay: setting, then shot by shot what happens and what the
/// narrator says (in the chosen language).
class _ScriptSection extends StatelessWidget {
  const _ScriptSection({required this.story, required this.lang});

  final StoryInfo story;
  final String lang;

  @override
  Widget build(BuildContext context) {
    if (story.script.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Scénář'),
        if (story.setting.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              story.setting,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        for (final shot in story.script) StoryShotRow(shot: shot, lang: lang),
      ],
    );
  }
}

/// One shot of the screenplay; shared with the project view.
class StoryShotRow extends StatelessWidget {
  const StoryShotRow({super.key, required this.shot, required this.lang});

  final StoryShotInfo shot;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final narration = shot.narrationFor(lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              shot.id,
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shot.control != null || shot.camera != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (shot.control != null)
                          _Badge('tanec · ${danceLabel(shot.control!)}'),
                        if (shot.camera != null)
                          _Badge('kamera · ${cameraLabel(shot.camera!)}'),
                      ],
                    ),
                  ),
                Text(
                  shot.action,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (narration.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '„$narration"',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // Material, not a decorated Container: the switches are ListTiles and
    // paint their ink on the nearest Material.
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
