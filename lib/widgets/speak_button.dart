import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/theme.dart';
import '../providers/voice_studio_provider.dart';
import 'music_playback.dart';

/// Reads [text] aloud in voice [voiceId]: the first tap synthesises (or finds
/// the audio on disk) and plays, later taps pause and resume. Shares the one
/// player with MusicStudio, so starting speech stops whatever played before.
class SpeakButton extends ConsumerStatefulWidget {
  const SpeakButton({
    super.key,
    required this.text,
    required this.voiceId,
    this.filled = false,
  });

  final String text;
  final String voiceId;

  /// Prominent button (Voice Studio) instead of the quiet icon under a chat
  /// bubble.
  final bool filled;

  @override
  ConsumerState<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<SpeakButton> {
  String? _path;
  bool _busy = false;

  @override
  void didUpdateWidget(SpeakButton old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.voiceId != widget.voiceId) _path = null;
  }

  Future<void> _tap() async {
    // Listening is not typing.
    FocusManager.instance.primaryFocus?.unfocus();
    final playback = ref.read(musicPlaybackProvider);
    final path = _path;
    if (path != null && playback.isCurrent(path)) {
      await playback.toggle(path);
      return;
    }
    setState(() => _busy = true);
    try {
      final spoken = await ref
          .read(voiceStudioProvider.notifier)
          .speak(widget.text, widget.voiceId);
      if (!mounted) return;
      _path = spoken;
      await playback.toggle(spoken);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final playing =
        path != null && ref.watch(musicPlaybackProvider).isPlaying(path);
    final color = widget.filled ? AppTheme.accent : AppTheme.textSecondary;
    final size = widget.filled ? 24.0 : 18.0;
    final icon = _busy
        ? SizedBox(
            width: size - 4,
            height: size - 4,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Icon(
            playing ? Icons.pause : Icons.volume_up_outlined,
            size: size,
            color: playing ? AppTheme.accent : color,
          );
    if (widget.filled) {
      return IconButton.filledTonal(
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
        ),
        tooltip: 'Přečíst',
        icon: icon,
        onPressed: _busy ? null : _tap,
      );
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      tooltip: 'Přečíst nahlas',
      icon: icon,
      onPressed: _busy ? null : _tap,
    );
  }
}
