import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/theme.dart';
import '../models/ocr_scan.dart';
import '../providers/ocr_provider.dart';
import '../widgets/mode_switcher.dart';

/// Top-level OCR mode. Always uses the nemotron-ocr-v2 NIM (no model picker):
/// pick/capture an image, get recognized text, kept in a persistent history.
class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key});

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> {
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    ref.listenManual(ocrProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
          ),
        );
        ref.read(ocrProvider.notifier).clearError();
      }
    });
  }

  Future<void> _pick(ImageSource source) async {
    if (ref.read(ocrProvider).isRunning) return;
    // Vyšší rozlišení = výrazně lepší čtení rukopisu. Qwen2.5-VL zvládne až
    // ~12.8 MP (procesor si víc sám zmenší) a full stránka se vejde do
    // max-model-len 32768; latence ~stejná (dominuje dekódování, ne prefill).
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 95,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref.read(ocrProvider.notifier).scan(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ocrProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR'),
        bottom: const ModeSwitcher(),
      ),
      body: Column(
        children: [
          if (state.isRunning) const LinearProgressIndicator(minHeight: 2),
          _ActionRow(
            busy: state.isRunning,
            onCamera: () => _pick(ImageSource.camera),
            onGallery: () => _pick(ImageSource.gallery),
          ),
          Expanded(
            child: state.scans.isEmpty
                ? const _EmptyHint()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.scans.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (context, i) =>
                        _ScanTile(scan: state.scans[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.busy,
    required this.onCamera,
    required this.onGallery,
  });

  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onCamera,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Vyfotit'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Galerie'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'Vyfoť nebo vyber obrázek s textem —\nrozpoznaný text se uloží do historie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanTile extends ConsumerWidget {
  const _ScanTile({required this.scan});

  final OcrScan scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstLine = scan.text.trim().isEmpty
        ? '(žádný text)'
        : scan.text.trim().split('\n').first;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(scan.imagePath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.broken_image_outlined, size: 20),
          ),
        ),
      ),
      title: Text(
        firstLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        _formatTime(scan.createdAt),
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        color: AppTheme.textSecondary,
        tooltip: 'Smazat',
        onPressed: () => ref.read(ocrProvider.notifier).delete(scan.id),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ScanDetailScreen(scan: scan)),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _ScanDetailScreen extends StatelessWidget {
  const _ScanDetailScreen({required this.scan});

  final OcrScan scan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rozpoznaný text'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Kopírovat',
            onPressed: scan.text.trim().isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: scan.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Text zkopírován do schránky'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(scan.imagePath)),
          ),
          const SizedBox(height: 16),
          SelectableText(
            scan.text.trim().isEmpty
                ? '(žádný text nebyl rozpoznán)'
                : scan.text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
