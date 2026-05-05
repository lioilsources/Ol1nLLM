import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/nim_service.dart';
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
  }) =>
      ChatState(
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

  final NimService _service = NimService();
  final PersonaService _personaService;
  StreamSubscription<ChatEvent>? _streamSub;

  ChatNotifier(this._personaService) : super(const ChatState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw as String) as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(
        conversations: list,
        activeId: list.isNotEmpty ? list.first.id : null,
      );
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

  void newConversation({String? personaId}) {
    final conv = Conversation.create(personaId: personaId);
    state = state.copyWith(
      conversations: [conv, ...state.conversations],
      activeId: conv.id,
      pendingContinuation: false,
    );
    _save();
  }

  /// Picks a persona for the current chat. If no conversation is active or
  /// the active one already has messages, starts a fresh one with this persona.
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

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isStreaming) return;

    var conv = state.active;
    if (conv == null) {
      conv = Conversation.create();
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        activeId: conv.id,
      );
    }

    // Add user message
    final userMsg = Message(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      createdAt: DateTime.now(),
    );
    final messagesForApi = [...conv.messages, userMsg];
    final newTitle = conv.messages.isEmpty
        ? (text.length > 60 ? '${text.substring(0, 60)}…' : text)
        : conv.title;
    conv = conv.copyWith(
      messages: messagesForApi,
      title: newTitle,
      updatedAt: DateTime.now(),
    );
    _replaceConversation(conv);
    state = state.copyWith(
      isStreaming: true,
      clearError: true,
      pendingContinuation: false,
    );

    try {
      await _save();

      // Resolve persona system prompt (null if no persona).
      final systemPrompt =
          await _personaService.systemPrompt(conv.personaId);

      // Add empty assistant bubble
      final assistantMsg = Message(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
      );
      conv = conv.copyWith(messages: [...conv.messages, assistantMsg]);
      _replaceConversation(conv);

      // Stream response
      _streamSub = _service
          .chat(messagesForApi, systemPrompt: systemPrompt)
          .listen(
        (event) {
          switch (event) {
            case ChatDelta(:final content):
              final current = state.active;
              if (current == null) return;
              final msgs = List<Message>.from(current.messages);
              final last = msgs.last;
              msgs[msgs.length - 1] =
                  last.copyWith(content: last.content + content);
              _replaceConversation(current.copyWith(
                messages: msgs,
                updatedAt: DateTime.now(),
              ));
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
        onError: (e) {
          debugPrint('Stream error: $e');
          state = state.copyWith(isStreaming: false, error: _errorMessage(e));
          _save();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('sendMessage setup error: $e');
      state = state.copyWith(isStreaming: false, error: _errorMessage(e));
    }
  }

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
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(
  (ref) => ChatNotifier(ref.read(personaServiceProvider)),
);
