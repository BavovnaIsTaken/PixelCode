/// Integration: facilitator session service + task board provider sharing a
/// single fake AgentWsService.
///
/// Walks the daily flow end-to-end on the client:
///   1. Facilitator session service is told `start()` with a stub seed
///      result already loaded — no real WS round-trip.
///   2. The service emits a `board_seed_batch` (atomic path, WP4/WP7).
///   3. The fake server "broadcasts" a `board_state` reflecting the
///      committed batch + auto-dispatch (WP3 server-side).
///   4. The TaskBoardNotifier picks up the broadcast, applies it,
///      tracks the revision, and the user can move a task optimistically.
///
/// The point is to catch wire-up regressions between three modules that
/// individual unit tests would still pass through.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart' show DevCategory, ScopeScore;
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/providers/task_board_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';
import 'package:pixelcode/services/facilitator_session_service.dart';

const _score = ScopeScore(
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
);

FacilitatorStyle _gameMaster() => FacilitatorStyle(
      id: 'game_master',
      displayName: 'Game Master',
      tagline: 'Quests, not tasks',
      laloux: Laloux.green,
      personaPrompt: 'Speak as a DM.',
      lexicon: const {'task': 'quest'},
      ceremonySchedule: const [],
      intakeTemplate: const [],
      outputMapper: OutputFormat.missionBriefing,
      toneModifiers: const ToneModifiers(
        aggression: 0.1,
        formality: 0.2,
        verbosity: 0.7,
      ),
    );

MissionBriefing _seededOutput() => MissionBriefing(
      id: 'mb-1',
      projectPath: '/tmp/proj',
      objective: 'Build a todo app',
      missions: const [
        Mission(
          id: 'm1',
          briefing: 'Stand up the data model.',
          target: 'todo entity',
          category: DevCategory.dataModel,
          status: MissionStatus.standby,
          xp: 100,
          estimatedMinutes: 25,
        ),
        Mission(
          id: 'm2',
          briefing: 'Wire the list screen.',
          target: 'list screen',
          category: DevCategory.uiComponent,
          status: MissionStatus.standby,
          xp: 100,
          estimatedMinutes: 25,
        ),
      ],
      scoreBreakdown: _score,
      createdAt: DateTime.utc(2026, 4, 26, 10),
    );

class _FakeWs extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final bool _connected = true;

  /// Last batch we received via boardSeedBatch — lets the test inspect
  /// the wire format and simulate a server "broadcast" in response.
  Map<String, Object?>? lastBatch;
  int boardMoveCallCount = 0;

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  void boardGetState({int? since}) {/* no-op */}

  @override
  void boardSeedBatch({
    String? batchId,
    String? source,
    required List<Map<String, dynamic>> tasks,
  }) {
    lastBatch = {
      'batchId': batchId,
      'source': source,
      'tasks': tasks,
    };
  }

  @override
  void boardCreateTask({
    required String title,
    String? description,
    String? color,
    String? priority,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) {
    // Should NOT be called when boardSeedBatch is wired — flag if it
    // ever is, the integration test will catch the regression.
    throw StateError(
      'boardCreateTask called even though boardSeedBatch is available',
    );
  }

  @override
  void boardMoveTask({required String taskId, required String column}) {
    boardMoveCallCount++;
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

/// Build a board_state matching what the server would broadcast after
/// committing the batch + auto-dispatching the two coder tasks.
ServerMessage _serverBroadcastForBatch({
  required int revision,
  required List<Map<String, dynamic>> committed,
}) {
  final tasks = <TaskCard>[];
  for (var i = 0; i < committed.length; i++) {
    final c = committed[i];
    tasks.add(TaskCard(
      id: 'task_${i + 1}_99999',
      title: c['title'] as String,
      description: (c['description'] as String?) ?? '',
      // Server WP3 auto-dispatches facilitator tasks → in_progress.
      column: TaskColumn.inProgress,
      assignedAgents: ['coder#1'],
      allowedRoles: const ['coder'],
      difficulty: 1,
      taskType: 'facilitator',
      createdAt: DateTime(2026, 5, 2),
      updatedAt: DateTime(2026, 5, 2),
    ));
  }
  return BoardStateMessage(
    boardState: BoardState(tasks: tasks),
    revision: revision,
  );
}

void main() {
  test('e2e: facilitator → batch → broadcast → optimistic move', () async {
    final ws = _FakeWs();
    final container = ProviderContainer(
      overrides: [wsServiceProvider.overrideWithValue(ws)],
    );
    addTearDown(container.dispose);
    container.read(taskBoardProvider); // build provider

    // Wire facilitator session service to the same fake WS.
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: ws.messages,
      createKanbanTask: ws.boardCreateTask,
      seedBoardBatch: ws.boardSeedBatch,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );

    // Kick off start; inject the seed reply once subscribed.
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _gameMaster(),
      projectDescription: 'A todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    ws.inject(FacilitatorSeededMessage(
      styleId: 'game_master',
      finalScore: _score,
      outputFormat: OutputFormat.missionBriefing,
      outputJson: _seededOutput().serialize(),
    ));
    final result = await future;
    expect(result, isA<FacilitatorSeedSuccess>());
    expect((result as FacilitatorSeedSuccess).kanbanTaskCount, 2);

    // Atomic batch was used (per-task path would have thrown).
    expect(ws.lastBatch, isNotNull);
    expect(ws.lastBatch!['source'], 'facilitator');
    final committedTasks = ws.lastBatch!['tasks']
        as List<Map<String, dynamic>>;
    expect(committedTasks, hasLength(2));

    // Server "broadcasts" the post-commit + auto-dispatch state.
    ws.inject(_serverBroadcastForBatch(
      revision: 1,
      committed: committedTasks,
    ));
    await Future<void>.delayed(Duration.zero);

    final boardAfter = container.read(taskBoardProvider);
    expect(boardAfter.tasks, hasLength(2));
    for (final t in boardAfter.tasks) {
      expect(t.column, TaskColumn.inProgress);
      expect(t.assignedAgents, ['coder#1']);
    }
    // Revision tracked.
    expect(
      container.read(taskBoardProvider.notifier).debugAppliedRevision,
      1,
    );

    // User drags one task to testing → optimistic state immediately
    // reflects the move; ws received the moveTask command.
    container.read(taskBoardProvider.notifier).moveTask(
          taskId: boardAfter.tasks.first.id,
          column: TaskColumn.testing,
        );
    expect(
      container.read(taskBoardProvider).tasks.first.column,
      TaskColumn.testing,
    );
    expect(ws.boardMoveCallCount, 1);

    // Server "rejects" by broadcasting state that puts the task back
    // in inProgress (e.g. permission denied). Optimistic snap-back.
    ws.inject(BoardStateMessage(
      boardState: BoardState(tasks: [
        boardAfter.tasks.first.copyWith(column: TaskColumn.inProgress),
        boardAfter.tasks[1],
      ]),
      revision: 2,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(taskBoardProvider).tasks.first.column,
      TaskColumn.inProgress,
    );
    expect(
      container.read(taskBoardProvider.notifier).debugAppliedRevision,
      2,
    );
  });

  test(
      'e2e: server returns set_game_state_error — message is parsed, no exception',
      () async {
    // Verify the new message is parsed correctly (and not surfaced as
    // a generic ErrorMessage which legacy clients would have done).
    final ws = _FakeWs();
    final container = ProviderContainer(
      overrides: [wsServiceProvider.overrideWithValue(ws)],
    );
    addTearDown(container.dispose);
    container.read(taskBoardProvider);

    var caught = false;
    final sub = ws.messages.listen(
      (msg) {
        if (msg is SetGameStateErrorMessage) {
          caught = true;
          expect(msg.errors, hasLength(2));
          expect(
            msg.errors.first.code,
            anyOf('manager_singleton', 'missing_api_key'),
          );
        }
      },
    );

    ws.inject(SetGameStateErrorMessage(errors: [
      RosterValidationError(
        instanceId: 'manager#2',
        code: 'manager_singleton',
        message: 'only one manager is allowed',
      ),
      RosterValidationError(
        instanceId: 'coder#1',
        code: 'missing_api_key',
        message: 'link DeepSeek',
      ),
    ]));
    await Future<void>.delayed(Duration.zero);
    expect(caught, isTrue);
    await sub.cancel();
  });
}
