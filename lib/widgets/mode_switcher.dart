import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../providers/home_mode_provider.dart';

/// Segmented Chat / Studio / OCR switcher. Sits as `AppBar.bottom` on every
/// top-level screen so all three modes are peers on one level.
class ModeSwitcher extends ConsumerWidget implements PreferredSizeWidget {
  const ModeSwitcher({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(homeModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<HomeMode>(
          segments: const [
            ButtonSegment(
              value: HomeMode.chat,
              icon: Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('Chat'),
            ),
            ButtonSegment(
              value: HomeMode.studio,
              icon: Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text('Studio'),
            ),
            ButtonSegment(
              value: HomeMode.ocr,
              icon: Icon(Icons.document_scanner_outlined, size: 18),
              label: Text('OCR'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (sel) =>
              ref.read(homeModeProvider.notifier).state = sel.first,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: const WidgetStatePropertyAll(
              BorderSide(color: Colors.white24),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : AppTheme.textSecondary,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppTheme.accent
                  : AppTheme.surface,
            ),
          ),
        ),
      ),
    );
  }
}
