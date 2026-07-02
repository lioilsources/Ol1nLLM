import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/media_service.dart';
import '../services/vllm_service.dart';
import '../services/persona_service.dart';

const _uuid = Uuid();

class ChatState {
  final List<Conversation> conversations;
  final String? activeId;
  final bool isStreaming;
  final String? error;

  /// True when the last assistant response was cut off because the model
  /// hit max_tokens. The UI uses this to pre-fill a "continue" prompt.
  final bool pendingContinuation;

  const ChatState({
    this.conversations = const [],
    this.activeId,
    this.isStreaming = false,
    this.error,
    this.pendingContinuation = false,
  });

  Conversation? get active =>
      conversations.where((c) => c.id == activeId).firstOrNull;

  ChatState copyWith({
    List<Conversation>? conversations,
    String? activeId,
    bool clearActive = false,
    bool? isStreaming,
    String? error,
    bool clearError = false,
    bool? pendingContinuation,
  }) => ChatState(
    conversations: conversations ?? this.conversations,
    activeId: clearActive ? null : (activeId ?? this.activeId),
    isStreaming: isStreaming ?? this.isStreaming,
    error: clearError ? null : (error ?? this.error),
    pendingContinuation: pendingContinuation ?? this.pendingContinuation,
  );
}

class ChatNotifier extends StateNotifier<ChatState> {
  static const _boxName = 'conversations';
  static const _key = 'all';

  final VllmService _service = VllmService();
  final MediaService _mediaService = MediaService(); // OCR only
  final PersonaService _personaService;
  StreamSubscription<ChatEvent>? _streamSub;

  ChatNotifier(this._personaService) : super(const ChatState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw != null) {
        final list = (jsonDecode(raw as String) as List)
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        state = state.copyWith(
          conversations: list,
          activeId: list.isNotEmpty ? list.first.id : null,
        );
      }
    } catch (e) {
      debugPrint('ChatNotifier load error: $e');
    }
  }

  Future<void> _save() async {
    final box = await Hive.openBox(_boxName);
    await box.put(
      _key,
      jsonEncode(state.conversations.map((c) => c.toJson()).toList()),
    );
  }

  // ── Conversation management ───────────────────────────────────────────────

  void newConversation({String? personaId}) {
    final conv = Conversation.create(personaId: personaId);
    state = state.copyWith(
      conversations: [conv, ...state.conversations],
      activeId: conv.id,
      pendingContinuation: false,
    );
    _save();
  }

  void selectPersona(String personaId) {
    final conv = state.active;
    if (conv == null || conv.messages.isNotEmpty) {
      newConversation(personaId: personaId);
      return;
    }
    _replaceConversation(conv.copyWith(personaId: personaId));
    _save();
  }

  void selectConversation(String id) {
    _cancelStream();
    state = state.copyWith(activeId: id, pendingContinuation: false);
  }

  /// Switch the active branch to the turn started by [userMessageId]. Moves the
  /// leaf to that turn's reply (or the user message itself if it has none), so
  /// the thread shows that path and the next message branches from there.
  void selectBranch(String userMessageId) {
    if (state.isStreaming) return;
    final conv = state.active;
    if (conv == null) return;
    final leaf = conv.replyOf(userMessageId)?.id ?? userMessageId;
    if (!conv.messages.any((m) => m.id == leaf)) return;
    _replaceConversation(conv.copyWith(activeLeafId: leaf));
    _save();
  }

  void dismissContinuation() =>
      state = state.copyWith(pendingContinuation: false);

  void deleteConversation(String id) {
    final remaining = state.conversations.where((c) => c.id != id).toList();
    final newActive = state.activeId == id
        ? (remaining.isNotEmpty ? remaining.first.id : null)
        : state.activeId;
    state = ChatState(
      conversations: remaining,
      activeId: newActive,
      isStreaming: false,
    );
    _save();
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text, {String? personaId}) async {
    if (text.trim().isEmpty || state.isStreaming) return;

    var conv = state.active;
    if (conv == null) {
      conv = Conversation.create();
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        activeId: conv.id,
      );
    }

    // Role for this turn: an explicit pick, else the active branch's persona.
    final turnPersonaId = personaId ?? conv.activePersonaId;
    final userMsg = Message(
      id: _uuid.v4(),
      parentId: conv.activeLeafId,
      role: MessageRole.user,
      content: text.trim(),
      createdAt: DateTime.now(),
      personaId: turnPersonaId,
    );
    // API sees only the active branch (root→leaf) plus the new user turn.
    final messagesForApi = [...conv.thread, userMsg];
    final newTitle = conv.messages.isEmpty
        ? (text.length > 60 ? '${text.substring(0, 60)}…' : text)
        : conv.title;
    conv = conv.copyWith(
      messages: [...conv.messages, userMsg],
      title: newTitle,
      updatedAt: DateTime.now(),
      activeLeafId: userMsg.id,
    );
    _replaceConversation(conv);
    state = state.copyWith(
      isStreaming: true,
      clearError: true,
      pendingContinuation: false,
    );

    try {
      await _save();

      final systemPrompt = await _personaService.systemPrompt(turnPersonaId);

      final assistantMsg = Message(
        id: _uuid.v4(),
        parentId: userMsg.id,
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
      );
      conv = conv.copyWith(
        messages: [...conv.messages, assistantMsg],
        activeLeafId: assistantMsg.id,
      );
      _replaceConversation(conv);

      _streamSub = _service
          .chat(messagesForApi, systemPrompt: systemPrompt)
          .listen(
            (event) {
              switch (event) {
                case ChatDelta(:final content):
                  final current = state.active;
                  if (current == null) return;
                  final msgs = current.messages
                      .map(
                        (m) => m.id == assistantMsg.id
                            ? m.copyWith(content: m.content + content)
                            : m,
                      )
                      .toList();
                  _replaceConversation(
                    current.copyWith(messages: msgs, updatedAt: DateTime.now()),
                  );
                case ChatDone(:final truncatedByLength):
                  if (truncatedByLength) {
                    state = state.copyWith(pendingContinuation: true);
                  }
              }
            },
            onDone: () {
              state = state.copyWith(isStreaming: false);
              _save();
            },
            onError: (e, st) {
              debugPrint('[vllm] stream error type=${e.runtimeType} msg=$e');
              debugPrint('[vllm] stack: $st');
              state = state.copyWith(
                isStreaming: false,
                error: _errorMessage(e),
              );
              _save();
            },
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('sendMessage setup error: $e');
      state = state.copyWith(isStreaming: false, error: _errorMessage(e));
    }
  }

  // ── OCR ──────────────────────────────────────────────────────────────────

  Future<void> runOcr(String imageBase64, {String? prompt}) async {
    if (imageBase64.isEmpty || state.isStreaming) return;
    await _runMedia(
      userMsg: Message(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: prompt?.trim() ?? '',
        createdAt: DateTime.now(),
        images: [imageBase64],
      ),
      titleSeed: 'OCR',
      task: () async {
        final text = await _mediaService.ocr(
          imageBase64: imageBase64,
          prompt: prompt,
        );
        return Message(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: text.isEmpty ? '_(no text recognized)_' : text,
          createdAt: DateTime.now(),
        );
      },
    );
  }

  /// OCR uses synchronous endpoint — old _runMedia pattern.
  Future<void> _runMedia({
    required Message userMsg,
    required String titleSeed,
    required Future<Message> Function() task,
  }) async {
    var conv = state.active;
    if (conv == null) {
      conv = Conversation.create();
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        activeId: conv.id,
      );
    }

    final user = userMsg.copyWith(parentId: conv.activeLeafId);
    final placeholderId = _uuid.v4();
    final placeholder = Message(
      id: placeholderId,
      parentId: user.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    final newTitle = conv.messages.isEmpty
        ? (titleSeed.length > 60 ? '${titleSeed.substring(0, 60)}…' : titleSeed)
        : conv.title;
    conv = conv.copyWith(
      messages: [...conv.messages, user, placeholder],
      title: newTitle,
      updatedAt: DateTime.now(),
      activeLeafId: placeholderId,
    );
    _replaceConversation(conv);
    state = state.copyWith(
      isStreaming: true,
      clearError: true,
      pendingContinuation: false,
    );

    final convId = conv.id;
    try {
      await _save();
      final result = await task();
      final current = state.conversations
          .where((c) => c.id == convId)
          .firstOrNull;
      if (current != null) {
        // Keep the placeholder's id/parent so the branch tip stays valid.
        _replaceConversation(
          current.copyWith(
            messages: current.messages
                .map(
                  (m) => m.id == placeholderId
                      ? m.copyWith(content: result.content, images: result.images)
                      : m,
                )
                .toList(),
            updatedAt: DateTime.now(),
          ),
        );
      }
      state = state.copyWith(isStreaming: false);
      await _save();
    } catch (e) {
      debugPrint('media op error: $e');
      _removePlaceholder(convId, placeholderId);
      state = state.copyWith(isStreaming: false, error: _errorMessage(e));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _errorMessage(Object e) {
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return e.toString();
  }

  void cancelStream() => _cancelStream();

  void clearError() => state = state.copyWith(clearError: true);

  void _cancelStream() {
    _streamSub?.cancel();
    _streamSub = null;
    if (state.isStreaming) {
      state = state.copyWith(isStreaming: false);
    }
  }

  void _removePlaceholder(String convId, String placeholderId) {
    final conv = state.conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null) return;
    // Drop the placeholder and pull the branch tip back to its parent so the
    // user can retry from the same point.
    final placeholder = conv.messages
        .where((m) => m.id == placeholderId)
        .firstOrNull;
    final newLeaf = conv.activeLeafId == placeholderId
        ? placeholder?.parentId
        : conv.activeLeafId;
    _replaceConversation(
      conv.copyWith(
        messages: conv.messages.where((m) => m.id != placeholderId).toList(),
        activeLeafId: newLeaf,
      ),
    );
  }

  void _replaceConversation(Conversation updated) {
    final list = state.conversations
        .map((c) => c.id == updated.id ? updated : c)
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(conversations: list);
  }

  @override
  void dispose() {
    _cancelStream();
    _service.dispose();
    _mediaService.dispose();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(
  (ref) => ChatNotifier(ref.read(personaServiceProvider)),
);
