import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/chat/chat_grouping.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ChatMessage _msg(
  String text, {
  ChatRole role = ChatRole.assistant,
  String agentId = 'manager#1',
  MessageCategory? category,
  String? threadId,
}) =>
    ChatMessage(
      role: role,
      text: text,
      agentId: agentId,
      category: category,
      threadId: threadId,
    );

ChatMessage _user(String text) => _msg(text, role: ChatRole.user, agentId: 'user');

ChatMessage _status(String text, {String? threadId}) =>
    _msg(text, category: MessageCategory.status, threadId: threadId);

// ─── itemSender ───────────────────────────────────────────────────────────────

void main() {
  group('itemSender', () {
    test('returns role:agentId key for SingleMessage', () {
      final item = SingleMessage(_msg('hi', agentId: 'coder#1'));
      expect(itemSender(item), 'assistant:coder#1');
    });

    test('distinguishes user from assistant even for same agentId', () {
      final asst = SingleMessage(_msg('hi', agentId: 'x'));
      final user = SingleMessage(_msg('hi', role: ChatRole.user, agentId: 'x'));
      expect(itemSender(asst), isNot(equals(itemSender(user))));
    });

    test('returns null for StatusGroup', () {
      final item = StatusGroup([_status('s1'), _status('s2')]);
      expect(itemSender(item), isNull);
    });

    test('returns null for ThreadGroup', () {
      final item = ThreadGroup(id: 't1', messages: [_msg('m', threadId: 't1')]);
      expect(itemSender(item), isNull);
    });
  });

  // ─── buildChatItems ─────────────────────────────────────────────────────────

  group('buildChatItems — empty input', () {
    test('returns empty list', () {
      expect(buildChatItems([]), isEmpty);
    });
  });

  group('buildChatItems — SingleMessage', () {
    test('single regular message becomes SingleMessage', () {
      final items = buildChatItems([_msg('hello')]);
      expect(items, hasLength(1));
      expect(items.first, isA<SingleMessage>());
    });

    test('preserves order across multiple regular messages', () {
      final items = buildChatItems([_msg('a'), _msg('b'), _msg('c')]);
      expect(items, hasLength(3));
      expect((items[0] as SingleMessage).message.text, 'a');
      expect((items[1] as SingleMessage).message.text, 'b');
      expect((items[2] as SingleMessage).message.text, 'c');
    });

    test('single status message (run of 1) becomes SingleMessage, not StatusGroup', () {
      final items = buildChatItems([_status('only one')]);
      expect(items.first, isA<SingleMessage>());
    });
  });

  group('buildChatItems — StatusGroup', () {
    test('two consecutive status messages become StatusGroup', () {
      final items = buildChatItems([_status('s1'), _status('s2')]);
      expect(items, hasLength(1));
      expect(items.first, isA<StatusGroup>());
      expect((items.first as StatusGroup).messages, hasLength(2));
    });

    test('five consecutive status messages collapse into one StatusGroup', () {
      final msgs = List.generate(5, (i) => _status('s$i'));
      final items = buildChatItems(msgs);
      expect(items, hasLength(1));
      expect((items.first as StatusGroup).messages, hasLength(5));
    });

    test('status run broken by regular message produces separate items', () {
      final items = buildChatItems([
        _status('s1'),
        _status('s2'),
        _msg('regular'),
        _status('s3'),
        _status('s4'),
      ]);
      expect(items, hasLength(3));
      expect(items[0], isA<StatusGroup>());
      expect(items[1], isA<SingleMessage>());
      expect(items[2], isA<StatusGroup>());
    });

    test('status messages with threadId are NOT grouped into StatusGroup', () {
      final items = buildChatItems([
        _status('s1', threadId: 'th1'),
        _status('s2', threadId: 'th1'),
      ]);
      // Both have threadId → ThreadGroup, not StatusGroup
      expect(items, hasLength(1));
      expect(items.first, isA<ThreadGroup>());
    });
  });

  group('buildChatItems — ThreadGroup', () {
    test('consecutive messages with same threadId become ThreadGroup', () {
      final items = buildChatItems([
        _msg('m1', threadId: 'th1'),
        _msg('m2', threadId: 'th1'),
        _msg('m3', threadId: 'th1'),
      ]);
      expect(items, hasLength(1));
      final tg = items.first as ThreadGroup;
      expect(tg.id, 'th1');
      expect(tg.messages, hasLength(3));
    });

    test('different threadIds produce separate ThreadGroups', () {
      final items = buildChatItems([
        _msg('a', threadId: 'th1'),
        _msg('b', threadId: 'th2'),
      ]);
      expect(items, hasLength(2));
      expect((items[0] as ThreadGroup).id, 'th1');
      expect((items[1] as ThreadGroup).id, 'th2');
    });

    test('non-consecutive messages with same threadId are NOT merged', () {
      final items = buildChatItems([
        _msg('a', threadId: 'th1'),
        _msg('separator'),          // breaks the run
        _msg('b', threadId: 'th1'),
      ]);
      expect(items, hasLength(3));
      expect(items[0], isA<ThreadGroup>());
      expect(items[1], isA<SingleMessage>());
      expect(items[2], isA<ThreadGroup>());
    });

    test('mixed status + text inside thread are all included', () {
      final items = buildChatItems([
        _status('tool call', threadId: 'th1'),
        _msg('result', threadId: 'th1'),
      ]);
      expect(items, hasLength(1));
      expect((items.first as ThreadGroup).messages, hasLength(2));
    });
  });

  group('buildChatItems — stacking key via itemSender', () {
    test('consecutive assistant messages from same agent share sender key', () {
      final items = buildChatItems([
        _msg('first', agentId: 'coder#1'),
        _msg('second', agentId: 'coder#1'),
      ]);
      expect(items, hasLength(2));
      expect(itemSender(items[0]), equals(itemSender(items[1])));
    });

    test('messages from different agents have distinct sender keys', () {
      final items = buildChatItems([
        _msg('from manager', agentId: 'manager#1'),
        _msg('from coder', agentId: 'coder#1'),
      ]);
      expect(itemSender(items[0]), isNot(equals(itemSender(items[1]))));
    });

    test('user message and assistant message have distinct sender keys', () {
      final items = buildChatItems([_user('q'), _msg('a')]);
      expect(itemSender(items[0]), isNot(equals(itemSender(items[1]))));
    });

    test('ThreadGroup between two same-agent bubbles breaks stacking', () {
      final items = buildChatItems([
        _msg('before', agentId: 'manager#1'),
        _msg('thread msg', agentId: 'manager#1', threadId: 'th1'),
        _msg('after', agentId: 'manager#1'),
      ]);
      expect(items, hasLength(3));
      // Middle item is ThreadGroup → itemSender returns null → breaks stack
      expect(itemSender(items[1]), isNull);
    });
  });
}
