import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/theme.dart';
import '../models/conversation.dart';
import '../models/persona.dart';
import '../providers/chat_provider.dart';
import '../services/persona_service.dart';

enum InputMode { chat, generateImage, editImage, ocr }

extension on InputMode {
  IconData get icon => switch (this) {
    InputMode.chat => Icons.chat_bubble_outline,
    InputMode.generateImage => Icons.auto_awesome,
    InputMode.editImage => Icons.brush_outlined,
    InputMode.ocr => Icons.document_scanner_outlined,
  };

  String get label => switch (this) {
    InputMode.chat => 'Chat',
    InputMode.generateImage => 'Generate image',
    InputMode.editImage => 'Edit image',
    InputMode.ocr => 'OCR',
  };

  String get hint => switch (this) {
    InputMode.chat => 'Message lab…',
    InputMode.generateImage => 'Describe an image to generate…',
    InputMode.editImage => 'Describe the edit…',
    InputMode.ocr => 'Optional instruction…',
  };

  bool get needsImage => this == InputMode.editImage || this == InputMode.ocr;
}

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key});

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  static const _continuationPrompt = 'Pokračuj';

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();

  InputMode _mode = InputMode.chat;
  Uint8List? _imageBytes;
  String? _imageBase64;

  /// Explicit role pick for the next message; null = inherit the active
  /// branch's persona. Reset after each send and when switching conversations.
  String? _personaOverride;

  String? _effectivePersonaId(Conversation? conv) =>
      _personaOverride ?? conv?.activePersonaId;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend {
    final hasText = _controller.text.trim().isNotEmpty;
    final hasImage = _imageBytes != null;
    return switch (_mode) {
      InputMode.chat => hasText,
      InputMode.generateImage => hasText,
      InputMode.editImage => hasText && hasImage,
      InputMode.ocr => hasImage,
    };
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageBase64 = base64Encode(bytes);
    });
  }

  void _clearImage() {
    setState(() {
      _imageBytes = null;
      _imageBase64 = null;
    });
  }

  void _setMode(InputMode mode) {
    setState(() {
      _mode = mode;
      if (!mode.needsImage) _clearImage();
    });
  }

  Future<void> _send() async {
    final notifier = ref.read(chatProvider.notifier);
    final text = _controller.text;
    if (!_canSend) return;

    switch (_mode) {
      case InputMode.chat:
        final personaId = _effectivePersonaId(ref.read(chatProvider).active);
        _controller.clear();
        _focusNode.requestFocus();
        setState(() => _personaOverride = null);
        await notifier.sendMessage(text, personaId: personaId);
      case InputMode.generateImage:
        _controller.clear();
        await notifier.generateImage(text);
      case InputMode.editImage:
        final image = _imageBase64!;
        _controller.clear();
        _clearImage();
        await notifier.editImage(image, text);
      case InputMode.ocr:
        final image = _imageBase64!;
        _controller.clear();
        _clearImage();
        await notifier.runOcr(image, prompt: text);
    }
  }

  void _prefillContinuation() {
    if (_controller.text.trim().isNotEmpty) return;
    _controller.value = TextEditingValue(
      text: _continuationPrompt,
      selection: const TextSelection.collapsed(
        offset: _continuationPrompt.length,
      ),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(chatProvider.select((s) => s.pendingContinuation), (
      prev,
      next,
    ) {
      if (next && prev != true) _prefillContinuation();
    });
    // Drop an explicit role pick when the conversation changes.
    ref.listen<String?>(chatProvider.select((s) => s.activeId), (_, __) {
      if (_personaOverride != null) setState(() => _personaOverride = null);
    });

    final isBusy = ref.watch(chatProvider).isStreaming;
    final conv = ref.watch(chatProvider).active;
    final personas = ref
        .watch(personaListProvider)
        .maybeWhen(data: (l) => l, orElse: () => const <Persona>[]);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceAlt,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imageBytes != null) _buildImagePreview(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildModeButton(isBusy),
                if (_mode == InputMode.chat && personas.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildPersonaButton(isBusy, conv, personas),
                ],
                if (_mode.needsImage) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    color: AppTheme.textSecondary,
                    tooltip: 'Pick image',
                    onPressed: isBusy ? null : _pickImage,
                  ),
                ],
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: Scrollbar(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !isBusy,
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: _mode.hint,
                          hintStyle: const TextStyle(
                            color: AppTheme.textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppTheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: isBusy ? null : (_) => _send(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  isBusy: isBusy,
                  enabled: _canSend,
                  onSend: _send,
                  onStop: () => ref.read(chatProvider.notifier).cancelStream(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(bool isBusy) {
    return PopupMenuButton<InputMode>(
      enabled: !isBusy,
      tooltip: 'Mode',
      icon: Icon(_mode.icon, color: AppTheme.accent),
      color: AppTheme.surface,
      onSelected: _setMode,
      itemBuilder: (context) => InputMode.values
          .map(
            (m) => PopupMenuItem(
              value: m,
              child: Row(
                children: [
                  Icon(
                    m.icon,
                    size: 18,
                    color: m == _mode
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    m.label,
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  /// Role switcher: shows the emoji of the role the next message will use
  /// (an explicit pick, else the active branch's persona). Picking a different
  /// one here forks the branch under that role on the next send.
  Widget _buildPersonaButton(
    bool isBusy,
    Conversation? conv,
    List<Persona> personas,
  ) {
    final selectedId = _effectivePersonaId(conv);
    final selected = personas.where((p) => p.id == selectedId).firstOrNull;
    return GestureDetector(
      onTap: isBusy ? null : () => _pickPersona(conv, personas),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: _personaOverride != null ? AppTheme.accent : Colors.white24,
            width: _personaOverride != null ? 1.5 : 0.5,
          ),
        ),
        child: selected != null
            ? Text(selected.emoji, style: const TextStyle(fontSize: 18))
            : const Icon(
                Icons.person_outline,
                size: 18,
                color: AppTheme.textSecondary,
              ),
      ),
    );
  }

  void _pickPersona(Conversation? conv, List<Persona> personas) {
    final selectedId = _effectivePersonaId(conv);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Role pro další zprávu',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in personas)
                    ListTile(
                      leading: Text(
                        p.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(
                        p.name,
                        style: TextStyle(
                          color: p.id == selectedId
                              ? AppTheme.accent
                              : AppTheme.textPrimary,
                        ),
                      ),
                      trailing: p.id == selectedId
                          ? const Icon(Icons.check, color: AppTheme.accent, size: 20)
                          : null,
                      onTap: () {
                        setState(() => _personaOverride = p.id);
                        Navigator.of(ctx).pop();
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

  Widget _buildImagePreview() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _imageBytes!,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: IconButton(
                icon: const Icon(Icons.cancel, size: 20),
                color: Colors.white70,
                onPressed: _clearImage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool isBusy;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _ActionButton({
    required this.isBusy,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final active = isBusy || enabled;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: active ? AppTheme.accent : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          isBusy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          color: active ? Colors.white : AppTheme.textSecondary,
          size: 20,
        ),
        onPressed: isBusy ? onStop : (enabled ? onSend : null),
      ),
    );
  }
}
