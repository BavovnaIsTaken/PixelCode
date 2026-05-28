/// Deep coverage for [ChatPanel] — pure-helper unit tests for the parsers,
/// scroll predicate, empty-state classifier, snippet builder and grouping
/// logic that were carved out of `chat_panel.dart` into
/// `chat_panel_helpers.dart`.
///
/// These tests do NOT spin up the full widget — they exercise the side-effect
/// free helpers directly. The narrow integration coverage that does pump the
/// widget lives in `chat_panel_test.dart` (in the sibling worktree) and the
/// other `test/widgets/chat/*_test.dart` files; this file complements them
/// without duplication.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/chat/chat_panel_helpers.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ChatMessage _msg(
  String text, {
  ChatRole role = ChatRole.assistant,
  String agentId = 'manager#1',
  MessageCategory? category,
  String? threadId,
  bool isStreaming = false,
  List<String> images = const [],
  DateTime? timestamp,
}) =>
    ChatMessage(
      role: role,
      text: text,
      agentId: agentId,
      category: category,
      threadId: threadId,
      isStreaming: isStreaming,
      imageBase64s: images,
      timestamp: timestamp ?? DateTime(2026, 5, 2, 12, 30, 0),
    );

ChatMessage _user(String text, {String agentId = 'user'}) =>
    _msg(text, role: ChatRole.user, agentId: agentId);

ChatMessage _status(String text, {String? threadId}) =>
    _msg(text, category: MessageCategory.status, threadId: threadId);

void main() {
  // ─── parseSlashCommand ─────────────────────────────────────────────────────

  group('parseSlashCommand', () {
    test('returns null for empty input', () {
      expect(parseSlashCommand(''), isNull);
    });

    test('returns null for plain text without leading slash', () {
      expect(parseSlashCommand('hello world'), isNull);
      expect(parseSlashCommand('clear'), isNull);
    });

    test('returns null for a bare slash', () {
      expect(parseSlashCommand('/'), isNull);
    });

    test('returns null when leading whitespace precedes the slash', () {
      // A leading space means "literal slash", not a command.
      expect(parseSlashCommand(' /clear'), isNull);
      expect(parseSlashCommand('\t/help'), isNull);
    });

    test('parses simple slash command with no args', () {
      final cmd = parseSlashCommand('/clear');
      expect(cmd, isNotNull);
      expect(cmd!.name, 'clear');
      expect(cmd.args, isEmpty);
    });

    test('parses command with single argument', () {
      final cmd = parseSlashCommand('/agent coder');
      expect(cmd!.name, 'agent');
      expect(cmd.args, 'coder');
    });

    test('parses command with multi-word arguments preserving inner spaces', () {
      final cmd = parseSlashCommand('/copy last  20 lines');
      expect(cmd!.name, 'copy');
      // Inner whitespace within args is preserved verbatim.
      expect(cmd.args, 'last  20 lines');
    });

    test('trims trailing whitespace in args', () {
      final cmd = parseSlashCommand('/help   ');
      expect(cmd!.name, 'help');
      expect(cmd.args, isEmpty);
    });

    test('accepts hyphens, underscores and digits in command name', () {
      expect(parseSlashCommand('/tech-lead')!.name, 'tech-lead');
      expect(parseSlashCommand('/copy_chat')!.name, 'copy_chat');
      expect(parseSlashCommand('/agent2')!.name, 'agent2');
    });

    test('rejects command names containing punctuation', () {
      expect(parseSlashCommand('/clear!'), isNull);
      expect(parseSlashCommand('/clear?'), isNull);
    });

    test('SlashCommand value equality and hashCode', () {
      const a = SlashCommand(name: 'clear', args: '');
      const b = SlashCommand(name: 'clear', args: '');
      const c = SlashCommand(name: 'help', args: '');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('clear'));
    });
  });

  // ─── extractMentions ───────────────────────────────────────────────────────

  group('extractMentions', () {
    test('returns empty list for empty text', () {
      expect(extractMentions(''), isEmpty);
    });

    test('returns empty list when no mentions present', () {
      expect(extractMentions('hello world, no agents here'), isEmpty);
    });

    test('extracts a single simple mention', () {
      expect(extractMentions('ping @coder#1 please'), ['coder#1']);
    });

    test('extracts hyphenated role mentions', () {
      expect(
        extractMentions('@tech-lead#2 review this with @ui-ux-designer#1'),
        ['tech-lead#2', 'ui-ux-designer#1'],
      );
    });

    test('extracts multiple mentions in order', () {
      expect(
        extractMentions('@manager#1 ping @coder#2 then @reviewer#3'),
        ['manager#1', 'coder#2', 'reviewer#3'],
      );
    });

    test('preserves duplicates', () {
      expect(
        extractMentions('@coder#1 @coder#1 @coder#2'),
        ['coder#1', 'coder#1', 'coder#2'],
      );
    });

    test('does not match @ with no role part', () {
      expect(extractMentions('@ #1'), isEmpty);
      expect(extractMentions('@#1'), isEmpty);
    });

    test('does not match malformed mentions without a numeric id', () {
      expect(extractMentions('@coder#'), isEmpty);
      expect(extractMentions('@coder#abc'), isEmpty);
      expect(extractMentions('@coder'), isEmpty);
    });

    test('mentions can be adjacent to punctuation', () {
      expect(extractMentions('cc: @coder#1, please.'), ['coder#1']);
      expect(extractMentions('(@manager#1)'), ['manager#1']);
    });
  });

  // ─── extractChoices ────────────────────────────────────────────────────────

  group('extractChoices', () {
    test('returns null for plain prose', () {
      expect(extractChoices('hello there'), isNull);
    });

    test('returns null when only a single numbered item', () {
      expect(extractChoices('1. only one'), isNull);
    });

    test('returns null when numbered list does not start at 1', () {
      expect(extractChoices('2. two\n3. three'), isNull);
    });

    test('returns null when sequence has gaps', () {
      expect(extractChoices('1. one\n3. three'), isNull);
    });

    test('returns null when text follows the last item', () {
      expect(
        extractChoices('1. one\n2. two\nthat is the plan'),
        isNull,
      );
    });

    test('parses a clean trailing list with header', () {
      expect(
        extractChoices('Pick one:\n1. cats\n2. dogs\n3. capybaras'),
        ['cats', 'dogs', 'capybaras'],
      );
    });

    test('accepts close-paren `)` as the numbering separator', () {
      expect(
        extractChoices('1) yes\n2) no'),
        ['yes', 'no'],
      );
    });

    test('strips inner whitespace from each label', () {
      expect(
        extractChoices('1.   alpha\n2.   beta'),
        ['alpha', 'beta'],
      );
    });

    test('tolerates trailing whitespace after the last item', () {
      expect(
        extractChoices('1. one\n2. two\n   '),
        ['one', 'two'],
      );
    });
  });

  // ─── roleTypeOf / defaultAgentNickname ─────────────────────────────────────

  group('roleTypeOf', () {
    test('strips the #N suffix', () {
      expect(roleTypeOf('coder#1'), 'coder');
      expect(roleTypeOf('manager#42'), 'manager');
    });

    test('handles compound role names', () {
      expect(roleTypeOf('tech-lead#1'), 'tech-lead');
      expect(roleTypeOf('ui-ux-designer#3'), 'ui-ux-designer');
    });

    test('returns the raw id when no hash present', () {
      expect(roleTypeOf('manager'), 'manager');
      expect(roleTypeOf(''), '');
    });
  });

  group('defaultAgentNickname', () {
    test('returns the Ukrainian nickname for known roles', () {
      expect(defaultAgentNickname('manager#1'), 'Капітан');
      expect(defaultAgentNickname('tech-lead#2'), 'Архітект');
      expect(defaultAgentNickname('coder#3'), 'Майстер');
      expect(defaultAgentNickname('reviewer#1'), 'Детектив');
      expect(defaultAgentNickname('tester#1'), 'Крашер');
      expect(defaultAgentNickname('security#1'), 'Страж');
      expect(defaultAgentNickname('ui-ux-designer#1'), 'Піксельник');
      expect(defaultAgentNickname('llm-specialist#1'), 'Промптер');
    });

    test('falls back to the raw id for unknown roles', () {
      expect(defaultAgentNickname('unknown#1'), 'unknown#1');
      expect(defaultAgentNickname('strange-role#9'), 'strange-role#9');
    });
  });

  // ─── Scroll-stick predicate ────────────────────────────────────────────────

  group('isAtBottomReverse', () {
    test('true when pixels equal 0 (at the bottom)', () {
      expect(isAtBottomReverse(0), isTrue);
    });

    test('true when pixels just below threshold', () {
      expect(isAtBottomReverse(39), isTrue);
    });

    test('true exactly at the threshold (inclusive)', () {
      expect(isAtBottomReverse(40), isTrue);
    });

    test('false when scrolled past threshold', () {
      expect(isAtBottomReverse(41), isFalse);
      expect(isAtBottomReverse(2000), isFalse);
    });

    test('threshold can be customised', () {
      expect(isAtBottomReverse(60, threshold: 100), isTrue);
      expect(isAtBottomReverse(101, threshold: 100), isFalse);
    });

    test('negative pixels (overscroll past zero) are still at-bottom', () {
      expect(isAtBottomReverse(-10), isTrue);
    });
  });

  group('shouldAutoStickToBottom', () {
    test('was sticking + still at bottom → keep sticking', () {
      expect(
        shouldAutoStickToBottom(wasAutoScrolling: true, currentPixels: 0),
        isTrue,
      );
    });

    test('was sticking + scrolled away → release', () {
      expect(
        shouldAutoStickToBottom(wasAutoScrolling: true, currentPixels: 200),
        isFalse,
      );
    });

    test('was released + scrolled back to bottom → re-stick', () {
      expect(
        shouldAutoStickToBottom(wasAutoScrolling: false, currentPixels: 0),
        isTrue,
      );
    });

    test('was released + still scrolled away → stay released', () {
      expect(
        shouldAutoStickToBottom(wasAutoScrolling: false, currentPixels: 200),
        isFalse,
      );
    });

    test('threshold parameter is honoured', () {
      // With a tiny threshold of 5px, anything past 5 releases.
      expect(
        shouldAutoStickToBottom(
          wasAutoScrolling: true,
          currentPixels: 6,
          threshold: 5,
        ),
        isFalse,
      );
    });
  });

  // ─── chatEmptyStateKind ────────────────────────────────────────────────────

  group('chatEmptyStateKind', () {
    test('syncing wins regardless of message state', () {
      expect(
        chatEmptyStateKind(isSyncing: true, isEmpty: true, showThinking: false),
        ChatEmptyStateKind.syncing,
      );
      expect(
        chatEmptyStateKind(
            isSyncing: true, isEmpty: false, showThinking: true),
        ChatEmptyStateKind.syncing,
      );
    });

    test('non-empty + ready → messages', () {
      expect(
        chatEmptyStateKind(
            isSyncing: false, isEmpty: false, showThinking: false),
        ChatEmptyStateKind.messages,
      );
    });

    test('empty + thinking → thinkingBubble (not the placeholder)', () {
      expect(
        chatEmptyStateKind(
            isSyncing: false, isEmpty: true, showThinking: true),
        ChatEmptyStateKind.thinkingBubble,
      );
    });

    test('empty + idle → empty placeholder', () {
      expect(
        chatEmptyStateKind(
            isSyncing: false, isEmpty: true, showThinking: false),
        ChatEmptyStateKind.empty,
      );
    });
  });

  // ─── buildChatItems ────────────────────────────────────────────────────────

  group('buildChatItems', () {
    test('empty input → empty list', () {
      expect(buildChatItems([]), isEmpty);
    });

    test('single regular message becomes SingleMessage', () {
      final items = buildChatItems([_msg('hi')]);
      expect(items, hasLength(1));
      expect(items.single, isA<SingleMessage>());
      expect((items.single as SingleMessage).message.text, 'hi');
    });

    test('two consecutive status messages collapse to a StatusGroup', () {
      final items = buildChatItems([_status('a'), _status('b')]);
      expect(items, hasLength(1));
      expect(items.single, isA<StatusGroup>());
      expect((items.single as StatusGroup).messages, hasLength(2));
    });

    test('a single isolated status stays as SingleMessage', () {
      final items = buildChatItems([_status('only')]);
      expect(items.single, isA<SingleMessage>());
    });

    test('status run broken by regular splits into separate items', () {
      final items = buildChatItems([
        _status('s1'),
        _status('s2'),
        _msg('mid'),
        _status('s3'),
        _status('s4'),
      ]);
      expect(items, hasLength(3));
      expect(items[0], isA<StatusGroup>());
      expect(items[1], isA<SingleMessage>());
      expect(items[2], isA<StatusGroup>());
    });

    test('messages sharing threadId merge into a ThreadGroup', () {
      final items = buildChatItems([
        _msg('a', threadId: 'th1'),
        _msg('b', threadId: 'th1'),
        _msg('c', threadId: 'th1'),
      ]);
      expect(items, hasLength(1));
      final tg = items.single as ThreadGroup;
      expect(tg.id, 'th1');
      expect(tg.messages, hasLength(3));
    });

    test('different threadIds produce separate groups', () {
      final items = buildChatItems([
        _msg('a', threadId: 'th1'),
        _msg('b', threadId: 'th2'),
      ]);
      expect(items, hasLength(2));
      expect((items[0] as ThreadGroup).id, 'th1');
      expect((items[1] as ThreadGroup).id, 'th2');
    });

    test('non-consecutive same-thread messages do NOT merge', () {
      final items = buildChatItems([
        _msg('a', threadId: 'th1'),
        _msg('separator'),
        _msg('b', threadId: 'th1'),
      ]);
      expect(items, hasLength(3));
      expect(items[0], isA<ThreadGroup>());
      expect(items[1], isA<SingleMessage>());
      expect(items[2], isA<ThreadGroup>());
    });

    test('status messages with threadId go into the ThreadGroup, not a StatusGroup', () {
      final items = buildChatItems([
        _status('s1', threadId: 'th'),
        _status('s2', threadId: 'th'),
      ]);
      expect(items, hasLength(1));
      expect(items.single, isA<ThreadGroup>());
    });

    test('mixed user and assistant messages stay as SingleMessages each', () {
      final items = buildChatItems([
        _user('q'),
        _msg('a'),
        _user('q2'),
      ]);
      expect(items, hasLength(3));
      for (final item in items) {
        expect(item, isA<SingleMessage>());
      }
    });
  });

  // ─── Snippet formatting ────────────────────────────────────────────────────

  group('formatSnippetTime/Date', () {
    test('time pads single-digit components', () {
      final t = DateTime(2026, 5, 2, 3, 7, 9);
      // toLocal() is identity for non-UTC DateTime.
      expect(formatSnippetTime(t), '03:07:09');
    });

    test('date includes year/month/day and HH:MM', () {
      final t = DateTime(2026, 1, 9, 8, 5);
      expect(formatSnippetDate(t), '2026-01-09 08:05');
    });
  });

  group('buildChatSnippet', () {
    final fixedNow = DateTime(2026, 5, 2, 14, 0, 0);

    test('header includes working dir, agent and message counts', () {
      final out = buildChatSnippet(
        tail: [_msg('hi')],
        totalMessages: 1,
        workingDir: '/tmp/proj',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('# PixelCode chat snippet — 2026-05-02 14:00'));
      expect(out, contains('**Working dir:** `/tmp/proj`'));
      expect(out, contains('**Selected agent:** manager#1 (Капітан)'));
      expect(out, contains('**Messages:** last 1 of 1'));
    });

    test('renders "(unset)" when working dir is null', () {
      final out = buildChatSnippet(
        tail: [_msg('hi')],
        totalMessages: 1,
        workingDir: null,
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('**Working dir:** `(unset)`'));
    });

    test('user lines say "user", assistant lines include agentId + nickname', () {
      final out = buildChatSnippet(
        tail: [
          _user('first user msg', agentId: 'user'),
          _msg('agent reply', agentId: 'coder#1'),
        ],
        totalMessages: 2,
        workingDir: '/tmp',
        selectedAgentId: 'coder#1',
        selectedAgentNickname: 'Майстер',
        now: fixedNow,
      );
      expect(out, contains('— user:**'));
      expect(out, contains('— coder#1 (Майстер):**'));
      expect(out, contains('first user msg'));
      expect(out, contains('agent reply'));
    });

    test('streaming messages are tagged with [streaming]', () {
      final out = buildChatSnippet(
        tail: [_msg('partial…', isStreaming: true)],
        totalMessages: 1,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('_[streaming]_'));
    });

    test('empty-text messages are placeholdered as _(empty)_', () {
      final out = buildChatSnippet(
        tail: [_msg('   ')],
        totalMessages: 1,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('_(empty)_'));
    });

    test('image-bearing messages get an attachment footer', () {
      final out = buildChatSnippet(
        tail: [_msg('see this:', images: const ['x', 'y', 'z'])],
        totalMessages: 1,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('_[+3 image(s)]_'));
    });

    test('uses provided nicknameFor lookup for non-selected agents', () {
      String lookup(String id) => switch (id) {
            'coder#1' => 'CustomCoder',
            _ => 'Other',
          };
      final out = buildChatSnippet(
        tail: [_msg('reply', agentId: 'coder#1')],
        totalMessages: 1,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        nicknameFor: lookup,
        now: fixedNow,
      );
      expect(out, contains('coder#1 (CustomCoder)'));
    });

    test('uses defaultAgentNickname when no lookup provided', () {
      final out = buildChatSnippet(
        tail: [_msg('hi', agentId: 'tester#1')],
        totalMessages: 1,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      // tester → Крашер via the default fallback.
      expect(out, contains('tester#1 (Крашер)'));
    });

    test('reports "last N of TOTAL" correctly when tail < total', () {
      final out = buildChatSnippet(
        tail: [_msg('a'), _msg('b')],
        totalMessages: 50,
        workingDir: '/tmp',
        selectedAgentId: 'manager#1',
        selectedAgentNickname: 'Капітан',
        now: fixedNow,
      );
      expect(out, contains('**Messages:** last 2 of 50'));
    });

    test('produces deterministic output for the same inputs', () {
      final args = {
        'tail': [_msg('hi')],
        'totalMessages': 1,
        'workingDir': '/tmp',
        'selectedAgentId': 'manager#1',
        'selectedAgentNickname': 'Капітан',
        'now': fixedNow,
      };
      final a = buildChatSnippet(
        tail: args['tail'] as Iterable<ChatMessage>,
        totalMessages: args['totalMessages'] as int,
        workingDir: args['workingDir'] as String?,
        selectedAgentId: args['selectedAgentId'] as String,
        selectedAgentNickname: args['selectedAgentNickname'] as String,
        now: args['now'] as DateTime,
      );
      final b = buildChatSnippet(
        tail: args['tail'] as Iterable<ChatMessage>,
        totalMessages: args['totalMessages'] as int,
        workingDir: args['workingDir'] as String?,
        selectedAgentId: args['selectedAgentId'] as String,
        selectedAgentNickname: args['selectedAgentNickname'] as String,
        now: args['now'] as DateTime,
      );
      expect(a, b);
    });
  });
}
