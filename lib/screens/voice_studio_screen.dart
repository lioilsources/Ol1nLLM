import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/theme.dart';
import '../models/persona.dart';
import '../models/voice.dart';
import '../providers/voice_studio_provider.dart';
import '../services/persona_service.dart';
import '../widgets/music_playback.dart';
import '../widgets/sample_recorder_sheet.dart';
import '../widgets/speak_button.dart';

void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// What the server can decode as a reference — ffmpeg reads the audio track
/// of a video too.
const _kSampleExtensions = [
  'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'aif', 'aiff', //
  'caf', 'mp4', 'mov', 'm4v', 'webm',
];

const _kLanguageNames = {
  'cs': 'Česky',
  'en': 'Anglicky',
  'es': 'Španělsky',
  'fr': 'Francouzsky',
  'it': 'Italsky',
  'pt': 'Portugalsky',
  'ja': 'Japonsky',
  'zh': 'Čínsky',
  'hi': 'Hindsky',
};

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
);

/// Voice Studio — clone a voice from a short recording, try any voice on a
/// sentence, and decide which persona speaks with which voice. The speaker
/// icon under a chat answer then reads it in that voice.
class VoiceStudioScreen extends ConsumerStatefulWidget {
  const VoiceStudioScreen({super.key});

  @override
  ConsumerState<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends ConsumerState<VoiceStudioScreen> {
  final _text = TextEditingController(text: 'Ahoj, takhle zním. Poznáváš mě?');
  String _selected = kDefaultVoiceId;
  String _language = kSpeechLanguage;

  @override
  void initState() {
    super.initState();
    ref.listenManual(voiceStudioProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
          ),
        );
        ref.read(voiceStudioProvider.notifier).clearError();
      }
      if (next.info != null && next.info != prev?.info) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.info!)));
        ref.read(voiceStudioProvider.notifier).clearInfo();
      }
    });
    Future.microtask(ref.read(voiceStudioProvider.notifier).loadVoices);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _select(String voiceId) {
    _dismissKeyboard();
    setState(() => _selected = voiceId);
  }

  Future<void> _recordVoice() async {
    _dismissKeyboard();
    // The mic would hear our own playback.
    await ref.read(musicPlaybackProvider).stop();
    if (!mounted) return;
    final path = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (_) => const SampleRecorderSheet(
        title: 'Nahrát hlas',
        idleHint:
            'Klepni na mikrofon a mluv souvisle, v tichu a jen jeden '
            'člověk. Klon je tak dobrý, jak čistá je nahrávka.',
        readyHint: 'Ideál je 10–20 s. Po půl minutě se nahrávání zastaví samo.',
        minSeconds: kMinVoiceSampleSeconds,
        maxSeconds: kMaxVoiceSampleSeconds,
      ),
    );
    if (path == null) return;
    await _nameVoice(path, 'nahravka.m4a');
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _pickVoice() async {
    _dismissKeyboard();
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kSampleExtensions,
    );
    final path = file?.path;
    if (file == null || path == null) return;
    await _nameVoice(path, file.name);
  }

  Future<void> _nameVoice(String path, String fileName) async {
    if (!mounted) return;
    final created = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (_) => _NewVoiceSheet(samplePath: path, fileName: fileName),
    );
    await ref.read(musicPlaybackProvider).stop();
    if (created != null && mounted) setState(() => _selected = created);
  }

  Future<void> _deleteVoice(Voice voice) async {
    _dismissKeyboard();
    final name = ref.read(voiceStudioProvider).voiceLabel(voice.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Smazat hlas „$name“?'),
        content: const Text(
          'Smaže se na serveru, i pro ostatní aplikace, které ho používají. '
          'Persony, které jím mluvily, se vrátí k výchozímu hlasu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nechat'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Smazat', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(voiceStudioProvider.notifier).deleteVoice(voice);
    if (mounted && _selected == voice.id) {
      setState(() => _selected = kDefaultVoiceId);
    }
  }

  Future<void> _playReference(Voice voice) async {
    _dismissKeyboard();
    try {
      final path = await ref
          .read(voiceStudioProvider.notifier)
          .referencePath(voice);
      await ref.read(musicPlaybackProvider).toggle(path);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nahrávku se nepodařilo stáhnout: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _assignPersona(Persona persona) async {
    _dismissKeyboard();
    final state = ref.read(voiceStudioProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (_) => _VoicePickerSheet(
        title: '${persona.emoji} ${persona.name}',
        current: state.voiceIdForPersona(persona.id),
      ),
    );
    if (picked == null) return;
    await ref
        .read(voiceStudioProvider.notifier)
        .setPersonaVoice(persona.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceStudioProvider);
    final personas = ref.watch(personaListProvider).valueOrNull ?? const [];
    final custom = state.customVoices;
    final languages = <String>{
      for (final v in state.voices)
        if (!v.isCustom && v.language.isNotEmpty) v.language,
    }.toList();
    final ready = [
      for (final v in state.voices)
        if (!v.isCustom && (v.language.isEmpty || v.language == _language)) v,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Studio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Načíst hlasy znovu',
            onPressed: state.loading
                ? null
                : ref.read(voiceStudioProvider.notifier).loadVoices,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _TryCard(
              controller: _text,
              voiceId: _selected,
              voiceLabel: state.voiceLabel(_selected),
            ),
            _SectionTitle(
              'Moje hlasy',
              trailing: state.loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            for (final v in custom)
              _VoiceTile(
                voice: v,
                title: state.voiceLabel(v.id),
                subtitle: _customSubtitle(v, state.stored[v.storedId]),
                selected: v.id == _selected,
                onTap: () => _select(v.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.graphic_eq, size: 20),
                      tooltip: 'Přehrát původní nahrávku',
                      color: AppTheme.textSecondary,
                      onPressed: () => _playReference(v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Smazat',
                      color: AppTheme.textSecondary,
                      onPressed: () => _deleteVoice(v),
                    ),
                  ],
                ),
              ),
            if (custom.isEmpty && !state.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Zatím žádný. Stačí 10–20 s čisté řeči jednoho člověka.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.mic, size: 18),
                    label: const Text('Nahrát hlas'),
                    onPressed: state.uploading ? null : _recordVoice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Ze souboru'),
                    onPressed: state.uploading ? null : _pickVoice,
                  ),
                ),
              ],
            ),
            if (personas.isNotEmpty) ...[
              const _SectionTitle('Hlasy person'),
              for (final p in personas)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(
                    p.name,
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    state.voiceLabel(state.voiceIdForPersona(p.id)),
                    style: TextStyle(
                      color: state.personaVoices.containsKey(p.id)
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                  ),
                  onTap: () => _assignPersona(p),
                ),
            ],
            if (languages.isNotEmpty) ...[
              const _SectionTitle('Hotové hlasy'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final l in languages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_kLanguageNames[l] ?? l),
                          selected: l == _language,
                          onSelected: (_) {
                            _dismissKeyboard();
                            setState(() => _language = l);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              for (final v in ready)
                _VoiceTile(
                  voice: v,
                  title: v.label,
                  subtitle: _readySubtitle(v),
                  selected: v.id == _selected,
                  onTap: () => _select(v.id),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _readySubtitle(Voice v) => [
  if (v.genderLabel.isNotEmpty) v.genderLabel,
  if (v.type == 'builtin') v.models.first.engine,
  if (v.models.isNotEmpty) v.models.first.licenseLabel,
].join(' · ');

/// Length and declared rights, then how the clone may be used in Czech — the
/// server chooses among the cloning models per request, so all are named.
String _customSubtitle(Voice v, StoredVoice? stored) {
  final czech = v.modelsFor(kSpeechLanguage);
  return [
    if (stored != null) '${stored.durationS.round()} s',
    if (stored != null && kVoiceRights[stored.rights] != null)
      kVoiceRights[stored.rights]!.toLowerCase(),
    if (czech.isEmpty)
      'česky neumí'
    else
      'česky: ${czech.map((m) => '${m.model} (${m.licenseLabel})').join(', ')}',
  ].join(' · ');
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    ),
  );
}

/// A sentence and the selected voice: the place to hear any voice before
/// giving it to a persona.
class _TryCard extends StatelessWidget {
  const _TryCard({
    required this.controller,
    required this.voiceId,
    required this.voiceLabel,
  });

  final TextEditingController controller;
  final String voiceId;
  final String voiceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            maxLength: kMaxSpeechChars,
            style: const TextStyle(color: AppTheme.textPrimary, height: 1.4),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              hintText: 'Co má hlas říct…',
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_outlined,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  voiceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              // Rebuilt per keystroke so the button always reads what is
              // in the field right now.
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, value, _) => SpeakButton(
                  text: value.text,
                  voiceId: voiceId,
                  filled: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.voice,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final Voice voice;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.12)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                trailing ?? const SizedBox(width: 8, height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Voices a persona can be given: clones first, then everything that speaks
/// Czech — a voice that cannot would read Czech answers in foreign phonemes.
class _VoicePickerSheet extends ConsumerWidget {
  const _VoicePickerSheet({required this.title, required this.current});

  final String title;
  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceStudioProvider);
    final voices = [
      ...state.customVoices,
      for (final v in state.voices)
        if (!v.isCustom && v.speaks(kSpeechLanguage)) v,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  if (voices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Hlasy se ze serveru nepodařilo načíst.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  for (final v in voices)
                    _VoiceTile(
                      voice: v,
                      title: state.voiceLabel(v.id),
                      subtitle: v.isCustom
                          ? _customSubtitle(v, state.stored[v.storedId])
                          : _readySubtitle(v),
                      selected: v.id == current,
                      onTap: () => Navigator.pop(context, v.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Names a freshly recorded or picked sample and states whose voice it is.
/// Pops with the new voice id once the server has stored it.
class _NewVoiceSheet extends ConsumerStatefulWidget {
  const _NewVoiceSheet({required this.samplePath, required this.fileName});

  final String samplePath;
  final String fileName;

  @override
  ConsumerState<_NewVoiceSheet> createState() => _NewVoiceSheetState();
}

class _NewVoiceSheetState extends ConsumerState<_NewVoiceSheet> {
  final _name = TextEditingController();
  final _source = TextEditingController();
  String _language = kSpeechLanguage;
  String? _rights;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    super.dispose();
  }

  bool get _complete =>
      voiceIdFor(_name.text) != null &&
      _rights != null &&
      _source.text.trim().length >= 3;

  Future<void> _save() async {
    _dismissKeyboard();
    await ref.read(musicPlaybackProvider).stop();
    setState(() => _error = null);
    try {
      final id = await ref
          .read(voiceStudioProvider.notifier)
          .createVoice(
            samplePath: widget.samplePath,
            fileName: widget.fileName,
            name: _name.text,
            language: _language,
            rights: _rights!,
            source: _source.text,
          );
      if (mounted) Navigator.pop(context, id);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploading = ref.watch(voiceStudioProvider.select((s) => s.uploading));
    final playback = ref.watch(musicPlaybackProvider);
    final playing = playback.isPlaying(widget.samplePath);
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Nový hlas',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: const Text('Nahrávka'),
                  onPressed: () {
                    _dismissKeyboard();
                    playback.toggle(widget.samplePath);
                  },
                ),
              ],
            ),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Jméno hlasu',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final l in const ['cs', 'en'])
                  ChoiceChip(
                    label: Text(_kLanguageNames[l]!),
                    selected: l == _language,
                    onSelected: (_) {
                      _dismissKeyboard();
                      setState(() => _language = l);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Čí je to hlas?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in kVoiceRights.entries)
                  ChoiceChip(
                    label: Text(r.value),
                    selected: r.key == _rights,
                    onSelected: (_) {
                      _dismissKeyboard();
                      setState(() => _rights = r.key);
                    },
                  ),
              ],
            ),
            TextField(
              controller: _source,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Kdo mluví a odkud nahrávka je',
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Zapíše se k hlasu na serveru. Cizí hlas bez svolení neklonuj.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red[300])),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _complete && !uploading ? _save : null,
                child: uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Uložit hlas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
