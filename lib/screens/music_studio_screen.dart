import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/theme.dart';
import '../models/music_project.dart';
import '../providers/music_studio_provider.dart';
import '../widgets/music_playback.dart';
import '../widgets/sample_recorder_sheet.dart';

/// The keyboard goes away on anything that obviously isn't typing (see the
/// same helper in the Image Studio).
void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// What the server can decode — ffmpeg reads the audio track of videos too,
/// so a clip from the camera roll works as a sample.
const _kSampleExtensions = [
  'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'aif', 'aiff', //
  'caf', 'mp4', 'mov', 'm4v', 'webm',
];

const _grooveColor = Color(0xFFB388FF);

Color _modeColor(MusicMode m) =>
    m == MusicMode.groove ? _grooveColor : AppTheme.accent;

/// MusicStudio — „vibe z předlohy": pick a music sample, see what the server
/// heard in it (caption, tempo, key), adjust, and compose new tracks with the
/// same sound (vibe) or the same groove in a new coat (groove).
class MusicStudioScreen extends ConsumerStatefulWidget {
  const MusicStudioScreen({super.key});

  @override
  ConsumerState<MusicStudioScreen> createState() => _MusicStudioScreenState();
}

class _MusicStudioScreenState extends ConsumerState<MusicStudioScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(musicStudioProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
          ),
        );
        ref.read(musicStudioProvider.notifier).clearError();
      }
      if (next.info != null && next.info != prev?.info) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.info!)));
        ref.read(musicStudioProvider.notifier).clearInfo();
      }
    });
  }

  Future<void> _pickSample() async {
    _dismissKeyboard();
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kSampleExtensions,
    );
    final path = file?.path;
    if (file == null || path == null) return;
    await ref.read(musicPlaybackProvider).stop();
    await ref.read(musicStudioProvider.notifier).addSample(path, file.name);
  }

  /// Record what's playing around the phone (radio, a speaker) instead of
  /// picking a file — the recording then goes the same way as a picked one.
  Future<void> _recordSample() async {
    _dismissKeyboard();
    // The mic would hear our own playback.
    await ref.read(musicPlaybackProvider).stop();
    if (!mounted) return;
    final path = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SampleRecorderSheet(),
    );
    if (path == null) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'Nahrávka ${now.day}. ${now.month}. ${two(now.hour)}:${two(now.minute)}.m4a';
    await ref.read(musicStudioProvider.notifier).addSample(path, name);
    // addSample copied it into the studio's storage.
    try {
      await File(path).delete();
    } catch (_) {}
  }

  void _openProjects() {
    _dismissKeyboard();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _ProjectsSheet(onNew: _pickSample, onRecord: _recordSample),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicStudioProvider);
    final project = state.active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Studio'),
        actions: [
          if (state.projects.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.library_music_outlined),
              tooltip: 'Předlohy',
              onPressed: _openProjects,
            ),
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Nahrát z okolí',
            onPressed: _recordSample,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nová předloha',
            onPressed: _pickSample,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: project == null
            ? _EmptyState(onPick: _pickSample, onRecord: _recordSample)
            : _ProjectView(key: ValueKey(project.id), project: project),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick, required this.onRecord});

  final VoidCallback onPick;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, size: 56, color: AppTheme.accent),
            const SizedBox(height: 16),
            const Text(
              'Složit ze vzoru',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nahraj, co zrovna hraje (rádio, repro), nebo vyber ukázku '
              '(mp3, wav, m4a, i video). Studio z ní vyčte žánr, nástroje, '
              'tempo a náladu — a složí novou skladbu ve stejném duchu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRecord,
              icon: const Icon(Icons.mic),
              label: const Text('Nahrát z okolí'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('Vybrat soubor'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectView extends ConsumerWidget {
  const _ProjectView({super.key, required this.project});

  final MusicProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = project.status == SampleStatus.ready;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _SampleCard(project: project),
        if (ready) ...[
          const SizedBox(height: 12),
          _SettingsCard(project: project),
          const SizedBox(height: 12),
          _ComposeButton(project: project),
        ],
        if (project.takes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Složené',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final t in project.takes) _TakeCard(take: t),
        ],
      ],
    );
  }
}

// ── Sample ──────────────────────────────────────────────────────────────────

class _SampleCard extends ConsumerWidget {
  const _SampleCard({required this.project});

  final MusicProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = project.analysis;
    final length = project.sampleDurationS;
    final source = project.sourceDurationS;
    final cropped = length != null && source != null && source - length > 1.0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PlayButton(path: project.samplePath),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (a != null && a.genre.isNotEmpty) a.genre,
                        if (length != null)
                          cropped
                              ? 'úsek ${formatSeconds(project.windowStartS ?? 0)}'
                                    '–${formatSeconds((project.windowStartS ?? 0) + length)}'
                                    ' z ${formatSeconds(source)}'
                              : formatSeconds(length),
                      ].join(' · '),
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
          _PlaybackBar(path: project.samplePath),
          if (project.status != SampleStatus.ready) ...[
            const SizedBox(height: 10),
            _AnalysisStatus(project: project),
          ],
          if (a != null && a.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in a.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AnalysisStatus extends ConsumerWidget {
  const _AnalysisStatus({required this.project});

  final MusicProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (project.status == SampleStatus.failed) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              project.error ?? 'Analýza selhala',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              _dismissKeyboard();
              ref.read(musicStudioProvider.notifier).retryAnalysis();
            },
            child: const Text('Znovu'),
          ),
        ],
      );
    }
    final label = project.status == SampleStatus.uploading
        ? 'Nahrávám předlohu…'
        : 'Poslouchám předlohu — žánr, nástroje, tempo…';
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Settings ────────────────────────────────────────────────────────────────

class _SettingsCard extends ConsumerStatefulWidget {
  const _SettingsCard({required this.project});

  final MusicProject project;

  @override
  ConsumerState<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<_SettingsCard> {
  late final TextEditingController _caption;
  late final TextEditingController _hint;

  @override
  void initState() {
    super.initState();
    _caption = TextEditingController(text: widget.project.draft.caption);
    _hint = TextEditingController(text: widget.project.draft.hint);
  }

  @override
  void didUpdateWidget(covariant _SettingsCard old) {
    super.didUpdateWidget(old);
    // Draft replaced from outside (fresh analysis, „Obnovit", „Použít
    // nastavení") — typing goes the other way and already matches.
    final d = widget.project.draft;
    if (_caption.text != d.caption) _caption.text = d.caption;
    if (_hint.text != d.hint) _hint.text = d.hint;
  }

  @override
  void dispose() {
    _caption.dispose();
    _hint.dispose();
    super.dispose();
  }

  MusicStudioNotifier get _n => ref.read(musicStudioProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final d = p.draft;
    final a = p.analysis;
    final edited =
        a != null &&
        (d.caption != a.caption ||
            d.bpm != a.bpm ||
            d.keyscale != a.keyscale ||
            d.timesignature !=
                (a.timesignature.isEmpty ? '4' : a.timesignature));
    final color = _modeColor(d.mode);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<MusicMode>(
            segments: const [
              ButtonSegment(
                value: MusicMode.vibe,
                icon: Icon(Icons.auto_awesome, size: 16),
                label: Text('Vibe'),
              ),
              ButtonSegment(
                value: MusicMode.groove,
                icon: Icon(Icons.graphic_eq, size: 16),
                label: Text('Groove'),
              ),
            ],
            selected: {d.mode},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: color.withValues(alpha: 0.2),
              selectedForegroundColor: color,
            ),
            onSelectionChanged: (s) {
              _dismissKeyboard();
              _n.updateDraft((d) => d.copyWith(mode: s.first));
            },
          ),
          const SizedBox(height: 6),
          Text(
            d.mode == MusicMode.vibe
                ? 'Nová skladba se stejným zvukem, tempem a náladou. Melodie se nekopíruje.'
                : 'Drží rytmus a formu předlohy, mění nástroje a barvu podle popisu.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Co studio slyšelo',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (edited)
                TextButton.icon(
                  onPressed: () {
                    _dismissKeyboard();
                    _n.resetDraftFromAnalysis();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.textSecondary,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Obnovit', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _caption,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: _inputDecoration('Popis hudby (anglicky)'),
            onChanged: (v) => _n.updateDraft((d) => d.copyWith(caption: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hint,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 13),
            decoration: _inputDecoration(
              'Přání — např. more energetic, add strings',
            ),
            onChanged: (v) => _n.updateDraft((d) => d.copyWith(hint: v)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ValueChip(
                icon: Icons.speed,
                label: d.bpm == null ? 'tempo —' : '${d.bpm} BPM',
                source: a?.source['bpm'],
                onTap: () => _pickTempo(context, d),
              ),
              _ValueChip(
                icon: Icons.piano_outlined,
                label: keyLabel(d.keyscale),
                source: a?.source['keyscale'],
                onTap: () => _pickKey(context, d),
              ),
              _ValueChip(
                icon: Icons.av_timer,
                label: timeSignatureLabel(d.timesignature),
                source: a?.source['timesignature'],
                onTap: () => _pickMeter(context, d),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (d.mode == MusicMode.vibe) ...[
            _SliderRow(
              label: 'Délka',
              value: d.durationS ?? p.defaultDurationS,
              min: kMinTrackSeconds,
              max: kMaxTrackSeconds,
              divisions: ((kMaxTrackSeconds - kMinTrackSeconds) / 5).round(),
              display: formatSeconds(d.durationS ?? p.defaultDurationS),
              color: color,
              onChanged: (v) => _n.updateDraft((d) => d.copyWith(durationS: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: d.lmPlan,
              activeThumbColor: color,
              title: const Text(
                'Rozvrhnout skladbu přes LM',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
              subtitle: const Text(
                'Víc tvaru (úvod, závěr), ale ~4× pomalejší a stejný seed '
                'pokaždé zahraje jinou skladbu.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              onChanged: (v) {
                _dismissKeyboard();
                _n.updateDraft((d) => d.copyWith(lmPlan: v));
              },
            ),
          ] else
            _SliderRow(
              label: 'Věrnost',
              value: d.coverStrength,
              min: 0.2,
              max: 0.9,
              divisions: 14,
              display: switch (d.coverStrength) {
                < 0.45 => 'volně',
                < 0.75 => 'drží rytmus',
                _ => 'skoro kopie',
              },
              color: color,
              onChanged: (v) =>
                  _n.updateDraft((d) => d.copyWith(coverStrength: v)),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Variant',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    for (final n in const [1, 2, 3, 4])
                      ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {d.variations},
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: color.withValues(alpha: 0.2),
                    selectedForegroundColor: color,
                  ),
                  onSelectionChanged: (s) {
                    _dismissKeyboard();
                    _n.updateDraft((d) => d.copyWith(variations: s.first));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  Future<T?> _sheet<T>(BuildContext context, String title, Widget child) {
    _dismissKeyboard();
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  void _pickTempo(BuildContext context, MusicDraft d) {
    final heard = widget.project.analysis?.bpm;
    _sheet<void>(
      context,
      'Tempo',
      _TempoPicker(
        initial: d.bpm ?? heard ?? 100,
        heard: heard,
        onChanged: (v) => _n.updateDraft((d) => d.copyWith(bpm: v)),
      ),
    );
  }

  void _pickKey(BuildContext context, MusicDraft d) {
    final parts = d.keyscale.split(' ');
    var note = parts.isNotEmpty && kKeyNotes.contains(parts.first)
        ? parts.first
        : 'C';
    var minor = parts.length > 1 && parts[1] == 'minor';
    _sheet<void>(
      context,
      'Tónina',
      StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply() => _n.updateDraft(
            (d) => d.copyWith(keyscale: '$note ${minor ? 'minor' : 'major'}'),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('dur')),
                  ButtonSegment(value: true, label: Text('moll')),
                ],
                selected: {minor},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setSheet(() => minor = s.first);
                  apply();
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in kKeyNotes)
                    ChoiceChip(
                      label: Text(n),
                      selected: n == note,
                      onSelected: (_) {
                        setSheet(() => note = n);
                        apply();
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _pickMeter(BuildContext context, MusicDraft d) {
    _sheet<void>(
      context,
      'Takt',
      Wrap(
        spacing: 8,
        children: [
          for (final ts in kTimeSignatures)
            ChoiceChip(
              label: Text(timeSignatureLabel(ts)),
              selected: ts == d.timesignature,
              onSelected: (_) {
                _n.updateDraft((d) => d.copyWith(timesignature: ts));
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _TempoPicker extends StatefulWidget {
  const _TempoPicker({
    required this.initial,
    required this.heard,
    required this.onChanged,
  });

  final int initial;
  final int? heard;
  final ValueChanged<int> onChanged;

  @override
  State<_TempoPicker> createState() => _TempoPickerState();
}

class _TempoPickerState extends State<_TempoPicker> {
  late int _bpm = widget.initial.clamp(40, 220);

  void _set(int v) {
    setState(() => _bpm = v.clamp(40, 220));
    widget.onChanged(_bpm);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _set(_bpm - 1),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '$_bpm BPM',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _set(_bpm + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Slider(
          value: _bpm.toDouble(),
          min: 40,
          max: 220,
          divisions: 180,
          onChanged: (v) => _set(v.round()),
        ),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (widget.heard != null) ...[
              ActionChip(
                label: Text('slyšeno ${widget.heard}'),
                onPressed: () => _set(widget.heard!),
              ),
              // Beat trackers and listeners disagree by octaves; one tap
              // fixes a half/double-time reading.
              ActionChip(
                label: const Text('½×'),
                onPressed: () => _set((_bpm / 2).round()),
              ),
              ActionChip(
                label: const Text('2×'),
                onPressed: () => _set(_bpm * 2),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.source,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Where the analysed value came from; librosa means the LM was overruled.
  final String? source;

  @override
  Widget build(BuildContext context) {
    final measured = source == 'librosa';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            ),
            if (measured) ...[
              const SizedBox(width: 4),
              const Tooltip(
                message: 'změřeno librosou, LM se mýlil',
                child: Icon(
                  Icons.straighten,
                  size: 12,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
            const SizedBox(width: 3),
            const Icon(
              Icons.expand_more,
              size: 14,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            onChangeStart: (_) => _dismissKeyboard(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ComposeButton extends ConsumerWidget {
  const _ComposeButton({required this.project});

  final MusicProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = project.draft;
    final busy = project.takes.any((t) => t.inFlight);
    final ready = d.caption.trim().isNotEmpty || d.hint.trim().isNotEmpty;
    final color = _modeColor(d.mode);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: ready
          ? () {
              _dismissKeyboard();
              HapticFeedback.lightImpact();
              ref.read(musicStudioProvider.notifier).generate();
            }
          : null,
      icon: const Icon(Icons.music_note),
      label: Text(
        busy
            ? 'Složit další'
            : d.variations == 1
            ? 'Složit'
            : 'Složit ${d.variations} varianty',
      ),
    );
  }
}

// ── Takes ───────────────────────────────────────────────────────────────────

class _TakeCard extends ConsumerWidget {
  const _TakeCard({required this.take});

  final MusicTake take;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = take.draft;
    final color = _modeColor(d.mode);
    final n = ref.read(musicStudioProvider.notifier);
    final summary = [
      d.mode == MusicMode.vibe ? 'Vibe' : 'Groove',
      if (d.bpm != null) '${d.bpm} BPM',
      if (d.keyscale.isNotEmpty) keyLabel(d.keyscale),
      if (d.mode == MusicMode.groove)
        'věrnost ${d.coverStrength.toStringAsFixed(2)}',
      if (d.mode == MusicMode.vibe && d.lmPlan) 'LM plán',
      if (d.hint.trim().isNotEmpty) '„${d.hint.trim()}“',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  d.mode == MusicMode.vibe
                      ? Icons.auto_awesome
                      : Icons.graphic_eq,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  color: AppTheme.surfaceAlt,
                  onOpened: _dismissKeyboard,
                  onSelected: (v) {
                    if (v == 'reuse') n.reuseTake(take.id);
                    if (v == 'delete') n.deleteTake(take.id);
                    if (v == 'copy') {
                      Clipboard.setData(
                        ClipboardData(text: take.finalCaption ?? d.caption),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'reuse',
                      child: Text('Použít nastavení'),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Text('Kopírovat popis'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Smazat')),
                  ],
                ),
              ],
            ),
            switch (take.status) {
              TakeStatus.queued ||
              TakeStatus.running => _TakeProgress(take: take),
              TakeStatus.failed => Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      take.error ?? 'Selhalo',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _dismissKeyboard();
                      n.retryTake(take.id);
                    },
                    child: const Text('Zkusit znovu'),
                  ),
                ],
              ),
              TakeStatus.done => Column(
                children: [
                  for (final (i, o) in take.outputs.indexed)
                    _OutputRow(index: i, output: o, color: color),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _TakeProgress extends StatelessWidget {
  const _TakeProgress({required this.take});

  final MusicTake take;

  @override
  Widget build(BuildContext context) {
    final label = switch (take.status) {
      TakeStatus.queued
          when take.queuePosition != null && take.queuePosition! > 1 =>
        'Ve frontě (${take.queuePosition}.)',
      TakeStatus.queued => 'Čeká na model…',
      _ =>
        take.draft.variations == 1
            ? 'Skládám…'
            : 'Skládám ${take.draft.variations} varianty…',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            minHeight: 2,
            color: _modeColor(take.draft.mode),
            backgroundColor: Colors.white10,
          ),
        ],
      ),
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({
    required this.index,
    required this.output,
    required this.color,
  });

  final int index;
  final MusicOutput output;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Row(
            children: [
              _PlayButton(path: output.path, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    'Varianta ${index + 1}',
                    formatSeconds(output.durationS),
                    if (output.seed != null) 'seed ${output.seed}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sdílet',
                icon: const Icon(
                  Icons.ios_share,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () {
                  _dismissKeyboard();
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(output.path, mimeType: 'audio/mpeg')],
                    ),
                  );
                },
              ),
            ],
          ),
          _PlaybackBar(path: output.path, color: color),
        ],
      ),
    );
  }
}

// ── Playback ────────────────────────────────────────────────────────────────

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.path, this.color = AppTheme.accent});

  final String path;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(musicPlaybackProvider);
    final playing = playback.isPlaying(path);
    return IconButton.filledTonal(
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
      ),
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      onPressed: () {
        _dismissKeyboard();
        playback.toggle(path);
      },
    );
  }
}

/// Seek bar under the track that is currently loaded; nothing otherwise.
class _PlaybackBar extends ConsumerWidget {
  const _PlaybackBar({required this.path, this.color = AppTheme.accent});

  final String path;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(musicPlaybackProvider);
    if (!playback.isCurrent(path)) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: playback.progress(path),
              activeColor: color,
              onChanged: (v) => playback.seek(path, v),
            ),
          ),
        ),
        Text(
          formatSeconds(playback.position(path).inMilliseconds / 1000),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ── Projects ────────────────────────────────────────────────────────────────

class _ProjectsSheet extends ConsumerWidget {
  const _ProjectsSheet({required this.onNew, required this.onRecord});

  final VoidCallback onNew;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicStudioProvider);
    final n = ref.read(musicStudioProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mic_none, color: AppTheme.accent),
              title: const Text('Nahrát z okolí'),
              onTap: () {
                Navigator.of(context).pop();
                onRecord();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add, color: AppTheme.accent),
              title: const Text('Nová předloha ze souboru'),
              onTap: () {
                Navigator.of(context).pop();
                onNew();
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
                      leading: const Icon(Icons.audio_file_outlined),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (p.analysis?.genre.isNotEmpty ?? false)
                            p.analysis!.genre,
                          '${p.takes.length} ${_takesWord(p.takes.length)}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Smazat',
                        onPressed: () => _confirmDelete(context, ref, p),
                      ),
                      onTap: () {
                        ref.read(musicPlaybackProvider).stop();
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

  static String _takesWord(int n) => switch (n) {
    1 => 'kolo',
    2 || 3 || 4 => 'kola',
    _ => 'kol',
  };

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    MusicProject p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Smazat předlohu?'),
        content: Text(
          '„${p.name}" a všechno, co z ní vzniklo, zmizí z telefonu.',
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
    await ref.read(musicPlaybackProvider).stop();
    await ref.read(musicStudioProvider.notifier).deleteProject(p.id);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material, not a decorated Container: the LM switch is a ListTile and
    // paints its ink on the nearest Material — a coloured box in between
    // would hide it.
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}
