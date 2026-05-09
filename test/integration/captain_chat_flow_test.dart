/// Integration: captain (manager) chat flow as the user sees it.
///
/// Companion to `server/test/integration/captain_orchestration.integration.test.ts`,
/// which pins the server-side orchestration. This test sits on the
/// other side of the wire: it verifies the client UI state — chat
/// transcript and board snapshots — reacts correctly to the captain's
/// scripted broadcasts.
///
/// What it walks through:
///   1. User sends a chat message (the user's part of the loop).
///   2. The fake server plays the captain's reply: a sequence of
///      `assistant_text` / `assistant_message_done` chat lines and
///      `board_state` broadcasts that mirror what the live server would
///      emit when the manager LLM splits, dispatches, and reports back.
///   3. After every step we snapshot both the chat transcript (from
///      `chatProvider`) and the board (from `taskBoardProvider`) and
///      assert the user-visible state matches what the prompt promises.
///
/// The captain LLM itself is NOT tested here — its actual outputs are
/// non-deterministic. What's tested is the plumbing that turns a
/// well-behaved captain's broadcasts into the correct chat + board UI.
/// This catches regressions in chat merging, board reactivity,
/// optimistic moves, and revision tracking — the failure modes that
/// have been making the core loop feel unstable.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WebSocket service ──────────────────────────────────────────

/// Captures everything the client sends to the server and lets the
/// test inject server-side messages. Stand-in for a live WS connection.
class _FakeWs extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final List<Map<String, Object?>> sent = [];
  final bool _connected = true;

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  void sendMessage(String content,
      {String agentId = 'manager', List<String>? images, String? localId}) {
    sent.add({'op': 'sendMessage', 'content': content, 'agentId': agentId});
  }

  @override
  void boardGetState({int? since}) {
    sent.add({'op': 'boardGetState', 'since': since});
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

// ─── Captain reply helpers ───────────────────────────────────────────

/// Build a TaskCard the way the server would for a captain-created card.
TaskCard _card({
  required String id,
  required String title,
  required TaskColumn column,
  List<String> assignedAgents = const [],
  List<String> allowedRoles = const ['coder'],
}) =>
    TaskCard(
      id: id,
      title: title,
      description: '',
      column: column,
      assignedAgents: assignedAgents,
      allowedRoles: allowedRoles,
      difficulty: 1,
      taskType: 'coding',
      createdAt: DateTime.utc(2026, 5, 2, 10),
      updatedAt: DateTime.utc(2026, 5, 2, 10),
    );

/// Inject one chat line as the captain would emit it: a single
/// `AssistantTextMessage` followed by `AssistantDoneMessage` with the
/// same threadId so the ChatNotifier finalizes a single message.
Future<void> _captainSays(_FakeWs ws, String line, {required String threadId}) async {
  ws.inject(AssistantTextMessage(
    text: line,
    isPartial: false,
    agentId: 'manager#1',
    threadId: threadId,
  ));
  ws.inject(AssistantDoneMessage(
    messageId: 'msg_$threadId',
    text: line,
    agentId: 'manager#1',
    threadId: threadId,
  ));
  // Let the stream listener flush.
  await Future<void>.delayed(Duration.zero);
}

Future<void> _broadcastBoard(
  _FakeWs ws, {
  required List<TaskCard> tasks,
  required int revision,
}) async {
  ws.inject(BoardStateMessage(
    boardState: BoardState(tasks: tasks),
    revision: revision,
  ));
  await Future<void>.delayed(Duration.zero);
}

Future<ProviderContainer> _makeContainer(_FakeWs ws) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    wsServiceProvider.overrideWithValue(ws),
    sharedPrefsProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  // Point the captain at manager#1 so chat messages route to it
  // (matches the test's broadcasts).
  c.read(selectedAgentProvider.notifier).state = 'manager#1';
  // Build both providers so subscriptions are live before we inject.
  c.read(chatProvider);
  c.read(taskBoardProvider);
  await Future<void>.delayed(Duration.zero);
  return c;
}

// ─── Tests ───────────────────────────────────────────────────────────

void main() {
  group('captain chat flow', () {
    test(
      'user → captain split → board fills → tasks dispatch in_progress → captain reports — every state visible to the user',
      () async {
        final ws = _FakeWs();
        final c = await _makeContainer(ws);
        final chat = c.read(chatProvider.notifier);

        // ── User asks for a feature ──
        chat.sendMessage('Build a TODO CRUD');
        await Future<void>.delayed(Duration.zero);

        // The user message is in the transcript and was dispatched on the wire.
        expect(c.read(chatProvider), hasLength(1));
        expect(c.read(chatProvider).first.text, 'Build a TODO CRUD');
        expect(ws.sent.last['op'], 'sendMessage');

        // ── Captain step 1: announces the split + cards land on the board ──
        await _captainSays(
          ws,
          'Розбив "Build a TODO CRUD" на: модель, екран, тести. Беремо модель першим.',
          threadId: 't1',
        );
        await _broadcastBoard(ws, revision: 1, tasks: [
          _card(id: 'task_1_x', title: 'Модель', column: TaskColumn.backlog),
          _card(id: 'task_2_x', title: 'Екран', column: TaskColumn.backlog),
          _card(
            id: 'task_3_x',
            title: 'Тести',
            column: TaskColumn.backlog,
            allowedRoles: const ['tester'],
          ),
        ]);

        // The user sees: 1 user msg, 1 captain split announcement.
        var msgs = c.read(chatProvider);
        expect(msgs, hasLength(2));
        expect(
          msgs[1].text,
          contains('Розбив "Build a TODO CRUD"'),
        );
        // 3 cards in backlog — user can already see what was decomposed.
        var board = c.read(taskBoardProvider);
        expect(board.tasks, hasLength(3));
        for (final t in board.tasks) {
          expect(t.column, TaskColumn.backlog);
          expect(t.assignedAgents, isEmpty);
        }

        // ── Captain step 2: dispatches each card with assignees ──
        await _broadcastBoard(ws, revision: 2, tasks: [
          _card(
            id: 'task_1_x',
            title: 'Модель',
            column: TaskColumn.inProgress,
            assignedAgents: ['coder#1'],
          ),
          _card(
            id: 'task_2_x',
            title: 'Екран',
            column: TaskColumn.inProgress,
            assignedAgents: ['coder#2'],
          ),
          _card(
            id: 'task_3_x',
            title: 'Тести',
            column: TaskColumn.inProgress,
            assignedAgents: ['tester#1'],
            allowedRoles: const ['tester'],
          ),
        ]);
        await _captainSays(ws, 'Працюємо.', threadId: 't2');

        // All 3 visibly moved into in_progress, each with one assignee.
        // No card is double-assigned to coder#1 — captain spread the load.
        board = c.read(taskBoardProvider);
        final byId = {for (final t in board.tasks) t.id: t};
        expect(byId['task_1_x']!.column, TaskColumn.inProgress);
        expect(byId['task_1_x']!.assignedAgents, ['coder#1']);
        expect(byId['task_2_x']!.assignedAgents, ['coder#2']);
        expect(byId['task_3_x']!.assignedAgents, ['tester#1']);
        // Workload-spread invariant: no coder is assigned to more than one
        // card across this batch.
        final coderAssigns = board.tasks
            .expand((t) => t.assignedAgents)
            .where((a) => a.startsWith('coder#'));
        expect(coderAssigns.toSet().length, coderAssigns.length,
            reason: 'no coder should appear on multiple cards in this batch');

        msgs = c.read(chatProvider);
        expect(msgs, hasLength(3));
        expect(msgs[2].text, 'Працюємо.');

        // ── Captain step 3: completion of "Модель" arrives ──
        await _broadcastBoard(ws, revision: 3, tasks: [
          _card(
            id: 'task_1_x',
            title: 'Модель',
            column: TaskColumn.done,
            assignedAgents: ['coder#1'],
          ),
          _card(
            id: 'task_2_x',
            title: 'Екран',
            column: TaskColumn.inProgress,
            assignedAgents: ['coder#2'],
          ),
          _card(
            id: 'task_3_x',
            title: 'Тести',
            column: TaskColumn.inProgress,
            assignedAgents: ['tester#1'],
            allowedRoles: const ['tester'],
          ),
        ]);
        await _captainSays(ws, 'Готово: Модель.', threadId: 't3');

        board = c.read(taskBoardProvider);
        expect(board.tasks.firstWhere((t) => t.id == 'task_1_x').column,
            TaskColumn.done);
        expect(board.tasks.firstWhere((t) => t.id == 'task_2_x').column,
            TaskColumn.inProgress);

        msgs = c.read(chatProvider);
        expect(msgs.last.text, 'Готово: Модель.');
        expect(msgs.length, 4,
            reason:
                'transcript: user msg + 3 captain lines, no duplicates / no leftover streams');
        // Revision tracker advanced — proves the client honored every
        // server-side mutation it saw.
        expect(c.read(taskBoardProvider.notifier).debugAppliedRevision, 3);
      },
    );

    test(
      'optimistic move while captain is mid-flight — user drag does not get clobbered by stale captain broadcast, then snaps to authoritative state',
      () async {
        // Regression bait: when the captain emits a broadcast that
        // doesn't reflect the user's just-completed drag, the user
        // should see the authoritative state win — without flicker
        // erasing their drag forever.
        final ws = _FakeWs();
        final c = await _makeContainer(ws);

        await _broadcastBoard(ws, revision: 1, tasks: [
          _card(
              id: 'task_1_x',
              title: 'A',
              column: TaskColumn.inProgress,
              assignedAgents: ['coder#1']),
        ]);

        var board = c.read(taskBoardProvider);
        expect(board.tasks.first.column, TaskColumn.inProgress);

        // User drags A → testing optimistically.
        c.read(taskBoardProvider.notifier).moveTask(
              taskId: 'task_1_x',
              column: TaskColumn.testing,
            );
        expect(c.read(taskBoardProvider).tasks.first.column,
            TaskColumn.testing,
            reason: 'optimistic move shows immediately');

        // Captain (or another client) broadcasts authoritative state
        // putting it back to in_progress (e.g. server rejected the move).
        await _broadcastBoard(ws, revision: 2, tasks: [
          _card(
              id: 'task_1_x',
              title: 'A',
              column: TaskColumn.inProgress,
              assignedAgents: ['coder#1']),
        ]);

        expect(c.read(taskBoardProvider).tasks.first.column,
            TaskColumn.inProgress,
            reason: 'authoritative state wins, no permanent drift');
        expect(c.read(taskBoardProvider.notifier).debugAppliedRevision, 2);
      },
    );

    test(
      'captain reports overload — chat message is preserved even when no cards are added',
      () async {
        final ws = _FakeWs();
        final c = await _makeContainer(ws);
        final chat = c.read(chatProvider.notifier);

        chat.sendMessage('Audit auth flow');
        await Future<void>.delayed(Duration.zero);

        // Captain refuses without creating a card and tells the user why.
        await _captainSays(
          ws,
          'Команда зараз не тягне аудит безпеки — потрібно найняти security.',
          threadId: 'overload-1',
        );

        // The board stays empty — no security agent to dispatch to.
        expect(c.read(taskBoardProvider).tasks, isEmpty);
        // The user still hears the captain's reason — the chat
        // message must not be silently dropped.
        final msgs = c.read(chatProvider);
        expect(msgs, hasLength(2)); // user + captain
        expect(msgs.last.text, contains('не тягне'));
        expect(msgs.last.text, contains('security'));
      },
    );

    test(
      'captain stream merges progressively — multiple AssistantText chunks form one final message',
      () async {
        // The live server streams text as the captain produces it.
        // Streaming chunks share a threadId; the ChatNotifier must
        // collapse them into one message that finalizes on
        // AssistantDone — otherwise the user sees the captain's reply
        // duplicated 3 times.
        final ws = _FakeWs();
        final c = await _makeContainer(ws);

        ws.inject(AssistantTextMessage(
          text: 'Розбив "X" на: ',
          isPartial: true,
          agentId: 'manager#1',
          threadId: 'stream-1',
        ));
        await Future<void>.delayed(Duration.zero);
        ws.inject(AssistantTextMessage(
          text: 'A, B, C.',
          isPartial: true,
          agentId: 'manager#1',
          threadId: 'stream-1',
        ));
        await Future<void>.delayed(Duration.zero);
        ws.inject(AssistantDoneMessage(
          messageId: 'msg_stream_1',
          text: 'Розбив "X" на: A, B, C.',
          agentId: 'manager#1',
          threadId: 'stream-1',
        ));
        await Future<void>.delayed(Duration.zero);

        final msgs = c.read(chatProvider);
        expect(msgs, hasLength(1),
            reason: 'streaming chunks should collapse into ONE message');
        expect(msgs.first.text, 'Розбив "X" на: A, B, C.');
        expect(msgs.first.isStreaming, isFalse,
            reason: 'AssistantDone finalizes the streaming flag');
      },
    );
  });
}
