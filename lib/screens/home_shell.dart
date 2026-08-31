import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_mode_provider.dart';
import 'chat_screen.dart';
import 'image_studio_screen.dart';
import 'ocr_screen.dart';

/// Root shell hosting the three top-level modes in an [IndexedStack] so each
/// keeps its state while hidden. The active mode is driven by
/// [homeModeProvider]; the segmented switcher lives in each screen's AppBar.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(homeModeProvider);
    return IndexedStack(
      index: mode.index,
      children: const [ChatScreen(), ImageStudioScreen(), OcrScreen()],
    );
  }
}
