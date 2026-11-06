import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/theme.dart';
import '../providers/speech_player.dart';

/// Reads [text] aloud in voice [voiceId] through the app's one
/// [SpeechPlayer]: a tap starts reading (sound comes after the first short
/// piece, the rest follows while it plays), later taps pause and resume, and
/// a tap while it is still waiting for audio cancels.
class SpeakButton extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final key = SpeechPlayer.keyOf(text, voiceId);
    ref.listen(speechPlayerProvider, (_, player) {
      final error = player.takeError(key);
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 8),
        ),
      );
    });
    final status = ref.watch(speechPlayerProvider.select((p) => p.status(key)));
    final color = filled ? AppTheme.accent : AppTheme.textSecondary;
    final size = filled ? 24.0 : 18.0;
    final icon = switch (status) {
      SpeechStatus.loading => SizedBox(
        width: size - 4,
        height: size - 4,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      SpeechStatus.playing => Icon(
        Icons.pause,
        size: size,
        color: AppTheme.accent,
      ),
      SpeechStatus.paused => Icon(
        Icons.play_arrow,
        size: size,
        color: AppTheme.accent,
      ),
      SpeechStatus.idle => Icon(
        Icons.volume_up_outlined,
        size: size,
        color: color,
      ),
    };
    final tooltip = switch (status) {
      SpeechStatus.loading => 'Zrušit čtení',
      SpeechStatus.playing => 'Pozastavit',
      SpeechStatus.paused => 'Pokračovat',
      SpeechStatus.idle => 'Přečíst nahlas',
    };
    void tap() {
      // Listening is not typing.
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(speechPlayerProvider).toggle(text, voiceId);
    }

    if (filled) {
      return IconButton.filledTonal(
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
        ),
        tooltip: tooltip,
        icon: icon,
        onPressed: tap,
      );
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      tooltip: tooltip,
      icon: icon,
      onPressed: tap,
    );
  }
}
