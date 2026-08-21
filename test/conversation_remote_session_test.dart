import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/conversation.dart';
import 'package:ol1n_llm/models/library_source.dart';
import 'package:ol1n_llm/models/message.dart';

/// The library RAG server keeps one linear history per `session_id`, while a
/// Conversation here is a tree. Reusing the session is only safe while the
/// server's history ends at the message the next send will extend — that is
/// exactly `canReuseRemoteSession`. These tests pin the cases where it must
/// refuse, because a false positive means silently wrong server-side memory.
Message _msg(String id, {String? parentId, MessageRole? role}) => Message(
  id: id,
  parentId: parentId,
  role: role ?? MessageRole.user,
  content: id,
  createdAt: DateTime(2026, 8, 5),
);

Conversation _conv({
  required List<Message> messages,
  String? activeLeafId,
  String? remoteSessionId,
  String? remoteLeafId,
}) => Conversation(
  id: 'c1',
  title: 't',
  messages: messages,
  updatedAt: DateTime(2026, 8, 5),
  activeLeafId: activeLeafId,
  remoteSessionId: remoteSessionId,
  remoteLeafId: remoteLeafId,
);

void main() {
  group('canReuseRemoteSession', () {
    test('reuses when the server history ends at the active leaf', () {
      final conv = _conv(
        messages: [_msg('u1'), _msg('a1', parentId: 'u1')],
        activeLeafId: 'a1',
        remoteSessionId: 's-1',
        remoteLeafId: 'a1',
      );
      expect(conv.canReuseRemoteSession, isTrue);
    });

    test('refuses with no session yet', () {
      final conv = _conv(messages: [_msg('u1')], activeLeafId: 'u1');
      expect(conv.canReuseRemoteSession, isFalse);
    });

    test('refuses after switching to a sibling branch tip', () {
      // The killer case: 'a2' is a leaf with no children, so a
      // forks-on-next-send style check would wrongly say "linear, reuse it",
      // yet the server's deque still holds the a1 branch.
      final conv = _conv(
        messages: [
          _msg('u1'),
          _msg('a1', parentId: 'u1', role: MessageRole.assistant),
          _msg('u2', parentId: 'u1'),
          _msg('a2', parentId: 'u2', role: MessageRole.assistant),
        ],
        activeLeafId: 'a2',
        remoteSessionId: 's-1',
        remoteLeafId: 'a1',
      );
      expect(conv.forksOnNextSend, isFalse, reason: 'a2 has no children');
      expect(conv.canReuseRemoteSession, isFalse);
    });

    test('refuses when the leaf moved back to fork from an older turn', () {
      final conv = _conv(
        messages: [
          _msg('u1'),
          _msg('a1', parentId: 'u1', role: MessageRole.assistant),
        ],
        activeLeafId: 'u1', // user jumped back; next send branches
        remoteSessionId: 's-1',
        remoteLeafId: 'a1',
      );
      expect(conv.canReuseRemoteSession, isFalse);
    });

    test('refuses after a failed turn left remoteLeafId stale', () {
      final conv = _conv(
        messages: [_msg('u1')],
        activeLeafId: 'u1',
        remoteSessionId: 's-1',
        remoteLeafId: 'a-old',
      );
      expect(conv.canReuseRemoteSession, isFalse);
    });
  });

  group('persistence', () {
    test('round-trips the remote session fields', () {
      final conv = _conv(
        messages: [_msg('u1')],
        activeLeafId: 'u1',
        remoteSessionId: 's-1',
        remoteLeafId: 'u1',
      );
      final back = Conversation.fromJson(conv.toJson());
      expect(back.remoteSessionId, 's-1');
      expect(back.remoteLeafId, 'u1');
      expect(back.canReuseRemoteSession, isTrue);
    });

    test('omits the fields entirely when unset', () {
      final json = _conv(messages: const [], activeLeafId: null).toJson();
      expect(json.containsKey('remoteSessionId'), isFalse);
      expect(json.containsKey('remoteLeafId'), isFalse);
    });

    test('loads a legacy conversation that predates all new fields', () {
      // Exactly what an old Hive blob looks like: no remote session, no
      // sources on messages. Must load without migration.
      final legacy = {
        'id': 'c-old',
        'title': 'staré',
        'updatedAt': '2026-01-01T00:00:00.000',
        'messages': [
          {
            'id': 'm1',
            'role': 'user',
            'content': 'ahoj',
            'createdAt': '2026-01-01T00:00:00.000',
          },
          {
            'id': 'm2',
            'role': 'assistant',
            'content': 'zdravím',
            'createdAt': '2026-01-01T00:00:01.000',
          },
        ],
      };
      final conv = Conversation.fromJson(legacy);
      expect(conv.remoteSessionId, isNull);
      expect(conv.remoteLeafId, isNull);
      expect(conv.canReuseRemoteSession, isFalse);
      expect(conv.messages.every((m) => m.sources.isEmpty), isTrue);
      // legacy flat chain still gets linked into a degenerate tree
      expect(conv.thread, hasLength(2));
    });

    test('carries citations on the message they belong to', () {
      const source = LibrarySource(
        work: 'Tao te ťing',
        group: 'chinese',
        distance: 0.3,
        excerpt: 'úryvek',
      );
      final answer = _msg(
        'a1',
        parentId: 'u1',
        role: MessageRole.assistant,
      ).copyWith(sources: const [source]);
      final conv = _conv(messages: [_msg('u1'), answer], activeLeafId: 'a1');

      final back = Conversation.fromJson(conv.toJson());
      final restored = back.messages.firstWhere((m) => m.id == 'a1');
      expect(restored.sources, hasLength(1));
      expect(restored.sources.first.work, 'Tao te ťing');
      expect(restored.sources.first.distance, closeTo(0.3, 1e-9));
    });
  });
}
