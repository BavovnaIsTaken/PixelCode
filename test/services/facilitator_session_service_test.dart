import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/mission_briefing.dart';
import 'package:pixelcode/models/quest_line.dart';
import 'package:pixelcode/services/facilitator_session_service.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _score = ScopeScore(
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
);

FacilitatorStyle _makeStyle({
  String id = 'game_master',
  OutputFormat output = OutputFormat.questLine,
}) =>
    FacilitatorStyle(
      id: id,
      displayName: 'Game Master',
      tagline: 'Quests, not tasks',
      laloux: Laloux.green,
      personaPrompt: 'Speak as a DM.',
      lexicon: const {'task': 'quest'},
      ceremonySchedule: const [],
      intakeTemplate: const [],
      outputMapper: output,
      toneModifiers:
          const ToneModifiers(aggression: 0.1, formality: 0.2, verbosity: 0.7),
    );

/// Tiny mission briefing whose `toKanbanTasks()` produces 2 entries — used to
/// assert the kanban dispatch loop without depending on tier sizing.
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

class _FakeKanban {
  final List<Map<String, Object?>> calls = [];

  void create({
    required String title,
    String? description,
    String? color,
    String? priority,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) {
    calls.add({
      'title': title,
      'description': description,
      'color': color,
      'priority': priority,
      'difficulty': difficulty,
      'allowedRoles': allowedRoles,
      'taskType': taskType,
    });
  }
}

class _SendRecorder {
  int sendCount = 0;
  FacilitatorStyle? lastStyle;
  String? lastDescription;
  Map<String, String>? lastAnswers;

  void send({
    required FacilitatorStyle style,
    required String projectDescription,
    required Map<String, String> answers,
  }) {
    sendCount += 1;
    lastStyle = style;
    lastDescription = projectDescription;
    lastAnswers = answers;
  }
}

FacilitatorSeededMessage _seededMessage(MissionBriefing output) =>
    FacilitatorSeededMessage(
      styleId: 'drill_sergeant',
      finalScore: _score,
      outputFormat: OutputFormat.missionBriefing,
      outputJson: output.serialize(),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  test('start — happy path: decodes output, persists, dispatches kanban tasks',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();
    final sender = _SendRecorder();
    final output = _seededOutput();
    var persistCalls = 0;

    final service = FacilitatorSessionService(
      sendStart: sender.send,
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => output,
      persistOutput: (_, _) async => persistCalls += 1,
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {'party': 'Solo'},
    );

    // Server reply must be flushed asynchronously — give the listener a
    // microtask to subscribe before we add the message.
    await Future<void>.delayed(Duration.zero);
    messages.add(_seededMessage(output));

    final result = await future;
    expect(result, isA<FacilitatorSeedSuccess>());
    final success = result as FacilitatorSeedSuccess;
    expect(success.styleId, 'drill_sergeant');
    expect(success.kanbanTaskCount, 2);
    expect(kanban.calls, hasLength(2));
    expect(kanban.calls.first['title'], isNotNull);
    expect(persistCalls, 1);
    expect(sender.sendCount, 1);
    expect(sender.lastDescription, 'Build a todo app');

    await messages.close();
  });

  test('start — server error surfaces as FacilitatorSeedFailure', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorErrorMessage(error: 'style.outputMapper'));

    final result = await future;
    expect(result, isA<FacilitatorSeedFailure>());
    expect((result as FacilitatorSeedFailure).message, 'style.outputMapper');
    expect(kanban.calls, isEmpty);

    await messages.close();
  });

  test('start — unregistered output format returns failure, no kanban writes',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => null, // simulate unknown format
      persistOutput: (_, _) async {},
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(output: OutputFormat.sprintBacklog),
      projectDescription: 'Build a todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorSeededMessage(
      styleId: 'scrum',
      finalScore: _score,
      outputFormat: OutputFormat.sprintBacklog,
      outputJson: '{"format":"sprint_backlog"}',
    ));

    final result = await future;
    expect(result, isA<FacilitatorSeedFailure>());
    expect((result as FacilitatorSeedFailure).message, contains('sprint_backlog'));
    expect(kanban.calls, isEmpty);

    await messages.close();
  });

  test('start — malformed outputJson returns failure', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorSeededMessage(
      styleId: 'game_master',
      finalScore: _score,
      outputFormat: OutputFormat.questLine,
      outputJson: 'not json {{{',
    ));

    final result = await future;
    expect(result, isA<FacilitatorSeedFailure>());
    expect((result as FacilitatorSeedFailure).message, contains('not parseable'));
    expect(kanban.calls, isEmpty);

    await messages.close();
  });

  test('start — timeout when server never responds', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );

    final result = await service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {},
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, isA<FacilitatorSeedFailure>());
    expect((result as FacilitatorSeedFailure).message, contains('timed out'));

    await messages.close();
  });

  test('start — persistence failure does NOT break kanban dispatch', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async => throw StateError('disk full'),
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(_seededMessage(_seededOutput()));

    final result = await future;
    expect(result, isA<FacilitatorSeedSuccess>());
    expect(kanban.calls, hasLength(2));

    await messages.close();
  });

  test('start — ignores non-facilitator messages on the same stream',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Build a todo app',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    // Noise: chat history, errors, init — none should resolve the future.
    messages.add(ErrorMessage(message: 'unrelated'));
    messages.add(InitMessage(sessionId: 's', agents: const []));
    await Future<void>.delayed(Duration.zero);
    expect(kanban.calls, isEmpty); // still waiting

    messages.add(_seededMessage(_seededOutput()));
    final result = await future;
    expect(result, isA<FacilitatorSeedSuccess>());
    expect(kanban.calls, hasLength(2));

    await messages.close();
  });

  test('FacilitatorSeededMessage.fromJson round-trips', () {
    final raw = jsonEncode({
      'type': 'facilitator_seeded',
      'styleId': 'game_master',
      'finalScore': _score.toJson(),
      'outputFormat': 'quest_line',
      'outputJson': '{"format":"quest_line"}',
    });
    final msg = ServerMessage.fromJson(raw);
    expect(msg, isA<FacilitatorSeededMessage>());
    final seeded = msg as FacilitatorSeededMessage;
    expect(seeded.styleId, 'game_master');
    expect(seeded.outputFormat, OutputFormat.questLine);
    expect(seeded.outputJson, '{"format":"quest_line"}');
  });

  // ─── WP7: typed error code propagation + batch path ────────────────────

  test('start — server timeout error surfaces FacilitatorErrorCode.timeout',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: _FakeKanban().create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorErrorMessage(
      error: 'LLM call exceeded 60000ms',
      code: FacilitatorErrorCode.timeout,
    ));
    final result = await future;
    final fail = result as FacilitatorSeedFailure;
    expect(fail.code, FacilitatorErrorCode.timeout);
    expect(fail.isRetryable, isTrue);
    await messages.close();
  });

  test('start — auth failure is NOT retryable', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: _FakeKanban().create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorErrorMessage(
      error: '401 unauthorized',
      code: FacilitatorErrorCode.auth,
    ));
    final fail = (await future) as FacilitatorSeedFailure;
    expect(fail.code, FacilitatorErrorCode.auth);
    expect(fail.isRetryable, isFalse);
    await messages.close();
  });

  test('start — parse failure is NOT retryable', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: _FakeKanban().create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(FacilitatorErrorMessage(
      error: 'no JSON block',
      code: FacilitatorErrorCode.parse,
    ));
    final fail = (await future) as FacilitatorSeedFailure;
    expect(fail.code, FacilitatorErrorCode.parse);
    expect(fail.isRetryable, isFalse);
    await messages.close();
  });

  test('start — local timeout uses FacilitatorErrorCode.timeout', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: _FakeKanban().create,
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final fail = (await service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
      timeout: const Duration(milliseconds: 30),
    )) as FacilitatorSeedFailure;
    expect(fail.code, FacilitatorErrorCode.timeout);
    expect(fail.isRetryable, isTrue);
    await messages.close();
  });

  test(
      'start — uses board_seed_batch when service exposes it; per-task path is skipped',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final perTaskKanban = _FakeKanban();
    final batchCalls = <Map<String, Object?>>[];

    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: perTaskKanban.create,
      seedBoardBatch: ({String? batchId, String? source, required List<Map<String, dynamic>> tasks}) {
        batchCalls.add({
          'batchId': batchId,
          'source': source,
          'taskCount': tasks.length,
          'firstTitle': tasks.isEmpty ? null : tasks.first['title'],
        });
      },
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(_seededMessage(_seededOutput()));
    final ok = (await future) as FacilitatorSeedSuccess;
    expect(ok.kanbanTaskCount, 2);
    // Atomic batch path used.
    expect(batchCalls, hasLength(1));
    expect(batchCalls.first['source'], 'facilitator');
    expect(batchCalls.first['taskCount'], 2);
    expect(batchCalls.first['batchId'], startsWith('facilitator-'));
    // Per-task path not used.
    expect(perTaskKanban.calls, isEmpty);
    await messages.close();
  });

  test(
      'start — falls back to per-task createKanbanTask when seedBoardBatch is absent',
      () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      // seedBoardBatch omitted on purpose
      decodeOutput: (_) => _seededOutput(),
      persistOutput: (_, _) async {},
    );
    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'p',
      answers: const {},
    );
    await Future<void>.delayed(Duration.zero);
    messages.add(_seededMessage(_seededOutput()));
    final ok = (await future) as FacilitatorSeedSuccess;
    expect(ok.kanbanTaskCount, 2);
    expect(kanban.calls, hasLength(2));
    await messages.close();
  });

  test('FacilitatorErrorCode.fromKey maps every typed code', () {
    expect(FacilitatorErrorCode.fromKey('timeout'),
        FacilitatorErrorCode.timeout);
    expect(FacilitatorErrorCode.fromKey('parse'),
        FacilitatorErrorCode.parse);
    expect(FacilitatorErrorCode.fromKey('rate_limit'),
        FacilitatorErrorCode.rateLimit);
    expect(FacilitatorErrorCode.fromKey('auth'),
        FacilitatorErrorCode.auth);
    expect(FacilitatorErrorCode.fromKey('unknown'),
        FacilitatorErrorCode.unknown);
    // Unknown / null keys fall back to unknown so the UI is never
    // forced to pattern-match against an open enum.
    expect(FacilitatorErrorCode.fromKey(null),
        FacilitatorErrorCode.unknown);
    expect(FacilitatorErrorCode.fromKey('made_up'),
        FacilitatorErrorCode.unknown);
  });

  test('FacilitatorErrorMessage.fromJson reads the optional code field', () {
    final raw = jsonEncode({
      'type': 'facilitator_error',
      'error': 'Boom',
      'code': 'rate_limit',
    });
    final msg = ServerMessage.fromJson(raw) as FacilitatorErrorMessage;
    expect(msg.code, FacilitatorErrorCode.rateLimit);
    expect(msg.error, 'Boom');
  });

  test('FacilitatorErrorMessage.fromJson defaults to unknown when code missing',
      () {
    final raw = jsonEncode({
      'type': 'facilitator_error',
      'error': 'Boom',
    });
    final msg = ServerMessage.fromJson(raw) as FacilitatorErrorMessage;
    expect(msg.code, FacilitatorErrorCode.unknown);
  });

  test('facilitatorBoardTaskStream is a broadcast stream', () {
    expect(facilitatorBoardTaskStream, isA<Stream<String>>());
    expect(facilitatorBoardTaskStream.isBroadcast, isTrue);
  });

  test('start — uses _defaultDecode when no decodeOutput is injected', () async {
    final messages = StreamController<ServerMessage>.broadcast();
    final kanban = _FakeKanban();
    final output = _seededOutput();

    // Omit decodeOutput → the private _defaultDecode is wired in, which
    // delegates to FacilitatorOutputPersistenceService.decode.
    final service = FacilitatorSessionService(
      sendStart: ({required style, required projectDescription, required answers}) {},
      messages: messages.stream,
      createKanbanTask: kanban.create,
      persistOutput: (_, _) async {},
    );

    final future = service.start(
      projectPath: '/tmp/proj',
      style: _makeStyle(),
      projectDescription: 'Test',
      answers: const {},
    );

    await Future<void>.delayed(Duration.zero);
    messages.add(_seededMessage(output));

    final result = await future;
    expect(result, isA<FacilitatorSeedSuccess>());
    await messages.close();
  });

  test('FacilitatorErrorMessage.fromJson round-trips', () {
    final raw = jsonEncode({
      'type': 'facilitator_error',
      'error': 'projectDescription must not be empty',
    });
    final msg = ServerMessage.fromJson(raw);
    expect(msg, isA<FacilitatorErrorMessage>());
    expect((msg as FacilitatorErrorMessage).error,
        'projectDescription must not be empty');
  });
}
