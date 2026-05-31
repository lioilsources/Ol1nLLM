import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/media_service.dart';
import '../services/nim_service.dart';
import '../services/persona_service.dart';

const _uuid = Uuid();
const _pendingJobKey = 'pending_image_job';

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
  final MediaService _mediaService = MediaService();
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
    await _resumePendingJob();
  }

  Future<void> _save() async {
    final box = await Hive.openBox(_boxName);
    await box.put(
      _key,
      jsonEncode(state.conversations.map((c) => c.toJson()).toList()),
    );
  }

  // ── Job persistence ───────────────────────────────────────────────────────

  Future<void> _persistJob({
    required String jobId,
    required String convId,
    required String placeholderId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingJobKey,
      jsonEncode({
        'job_id': jobId,
        'conv_id': convId,
        'placeholder_id': placeholderId,
      }),
    );
  }

  Future<void> _clearPendingJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingJobKey);
  }

  Future<void> _resumePendingJob() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingJobKey);
    if (raw == null) return;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    final jobId = data['job_id'] as String;
    final convId = data['conv_id'] as String;
    final placeholderId = data['placeholder_id'] as String;

    final conv = state.conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null ||
        !conv.messages.any((m) => m.id == placeholderId)) {
      await _clearPendingJob();
      return;
    }

    state = state.copyWith(isStreaming: true);
    _pollAndUpdate(jobId, convId, placeholderId);
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

      final systemPrompt = await _personaService.systemPrompt(conv.personaId);

      final assistantMsg = Message(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
      );
      conv = conv.copyWith(messages: [...conv.messages, assistantMsg]);
      _replaceConversation(conv);

      _streamSub = _service.chat(messagesForApi, systemPrompt: systemPrompt).listen(
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

  // ── Media (async job model) ───────────────────────────────────────────────

  Future<void> generateImage(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || state.isStreaming) return;
    await _runMediaAsync(
      userMsg: Message(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: text,
        createdAt: DateTime.now(),
      ),
      titleSeed: text,
      submitJob: () => _mediaService.submitGeneration(prompt: text),
    );
  }

  Future<void> editImage(String imageBase64, String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || imageBase64.isEmpty || state.isStreaming) return;
    await _runMediaAsync(
      userMsg: Message(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: text,
        createdAt: DateTime.now(),
        images: [imageBase64],
      ),
      titleSeed: text,
      submitJob: () =>
          _mediaService.submitEdit(imageBase64: imageBase64, prompt: text),
    );
  }

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

  /// Submit an image job then poll, updating the placeholder message in place.
  Future<void> _runMediaAsync({
    required Message userMsg,
    required String titleSeed,
    required Future<String> Function() submitJob,
  }) async {
    var conv = state.active;
    if (conv == null) {
      conv = Conversation.create();
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        activeId: conv.id,
      );
    }

    final placeholderId = _uuid.v4();
    final placeholder = Message(
      id: placeholderId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );

    final newTitle = conv.messages.isEmpty
        ? (titleSeed.length > 60 ? '${titleSeed.substring(0, 60)}…' : titleSeed)
        : conv.title;
    conv = conv.copyWith(
      messages: [...conv.messages, userMsg, placeholder],
      title: newTitle,
      updatedAt: DateTime.now(),
    );
    _replaceConversation(conv);
    state = state.copyWith(
      isStreaming: true,
      clearError: true,
      pendingContinuation: false,
    );
    await _save();

    String jobId;
    try {
      jobId = await submitJob();
    } catch (e) {
      debugPrint('media submit error: $e');
      _removePlaceholder(conv.id, placeholderId);
      state = state.copyWith(isStreaming: false, error: _errorMessage(e));
      return;
    }

    await _persistJob(
      jobId: jobId,
      convId: conv.id,
      placeholderId: placeholderId,
    );

    _pollAndUpdate(jobId, conv.id, placeholderId);
  }

  void _pollAndUpdate(String jobId, String convId, String placeholderId) {
    _mediaService.pollJob(jobId).listen(
      (status) {
        switch (status) {
          case JobQueued(:final position):
            final text =
                position > 0 ? '⏳ Ve frontě – pozice $position' : '⚙️ Spouštím…';
            _updatePlaceholder(convId, placeholderId, text);
          case JobRunning(:final step, :final total):
            final text =
                step == 0 ? '⚙️ Spouštím…' : '⚙️ Generuji krok $step/$total';
            _updatePlaceholder(convId, placeholderId, text);
          case JobDone(:final images):
            _clearPendingJob();
            _replacePlaceholder(
              convId,
              placeholderId,
              Message(
                id: _uuid.v4(),
                role: MessageRole.assistant,
                content: '',
                createdAt: DateTime.now(),
                images: images,
              ),
            );
            state = state.copyWith(isStreaming: false);
            _save();
          case JobFailed(:final message):
            _clearPendingJob();
            _removePlaceholder(convId, placeholderId);
            state = state.copyWith(isStreaming: false, error: message);
          case JobExpired():
            _clearPendingJob();
            _removePlaceholder(convId, placeholderId);
            state = state.copyWith(
              isStreaming: false,
              error: 'Výsledek vypršel – zkus vygenerovat znovu',
            );
        }
      },
      onError: (e) {
        debugPrint('poll error: $e');
        _clearPendingJob();
        _removePlaceholder(convId, placeholderId);
        state = state.copyWith(isStreaming: false, error: _errorMessage(e));
      },
    );
  }

  void _updatePlaceholder(String convId, String placeholderId, String content) {
    final conv =
        state.conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null) return;
    _replaceConversation(conv.copyWith(
      messages: conv.messages
          .map((m) => m.id == placeholderId ? m.copyWith(content: content) : m)
          .toList(),
    ));
  }

  void _replacePlaceholder(
      String convId, String placeholderId, Message replacement) {
    final conv =
        state.conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null) return;
    _replaceConversation(conv.copyWith(
      messages: conv.messages
          .map((m) => m.id == placeholderId ? replacement : m)
          .toList(),
      updatedAt: DateTime.now(),
    ));
  }

  void _removePlaceholder(String convId, String placeholderId) {
    final conv =
        state.conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null) return;
    _replaceConversation(conv.copyWith(
      messages: conv.messages.where((m) => m.id != placeholderId).toList(),
    ));
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

    final placeholderId = _uuid.v4();
    final placeholder = Message(
      id: placeholderId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    final newTitle = conv.messages.isEmpty
        ? (titleSeed.length > 60 ? '${titleSeed.substring(0, 60)}…' : titleSeed)
        : conv.title;
    conv = conv.copyWith(
      messages: [...conv.messages, userMsg, placeholder],
      title: newTitle,
      updatedAt: DateTime.now(),
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
      final current =
          state.conversations.where((c) => c.id == convId).firstOrNull;
      if (current != null) {
        _replaceConversation(current.copyWith(
          messages: current.messages
              .map((m) => m.id == placeholderId ? result : m)
              .toList(),
          updatedAt: DateTime.now(),
        ));
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
