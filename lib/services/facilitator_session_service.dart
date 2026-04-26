/// Orchestrates the client side of the Facilitator vertical slice:
///
///   pick → intake → WS `facilitator_start` → wait for `facilitator_seeded` →
///   decode JSON via persistence registry → save locally →
///   send each `output.toKanbanTasks()` entry as `board_create_task`.
///
/// All collaborators are injected as typedef'd callbacks so the orchestrator
/// is testable without a real WebSocket, filesystem, or kanban server. A
/// thin `bindToWsService` factory wires the production case.
library;

import 'dart:async';
import 'dart:convert';

import '../models/agent_message.dart';
import '../models/facilitator_output.dart';
import '../models/facilitator_style.dart';
import 'agent_ws_service.dart';
import 'facilitator_output_persistence_service.dart';

// ─── Injection seams ─────────────────────────────────────────────────────────

/// Sends the `facilitator_start` WS request. Side-effecting; no return.
typedef SendStartFn = void Function({
  required FacilitatorStyle style,
  required String projectDescription,
  required Map<String, String> answers,
});

/// Creates a single kanban task. Mirrors `AgentWsService.boardCreateTask`.
typedef CreateKanbanTaskFn = void Function({
  required String title,
  String? description,
  String? color,
  String? priority,
  int? difficulty,
  List<String>? allowedRoles,
  String? taskType,
});

/// Decodes a serialized `FacilitatorOutput` payload, dispatching by the
/// `format` discriminator. Returns `null` when no decoder is registered
/// for the format (e.g. an old client encountering a future style).
typedef DecodeOutputFn = FacilitatorOutput? Function(Map<String, dynamic> json);

/// Persists the seeded output. Production wires this to
/// [FacilitatorOutputPersistenceService.save]; tests pass a no-op.
typedef PersistOutputFn = Future<void> Function(
  String projectPath,
  FacilitatorOutput output,
);

// ─── Result types ────────────────────────────────────────────────────────────

sealed class FacilitatorSessionResult {
  const FacilitatorSessionResult();
}

class FacilitatorSeedSuccess extends FacilitatorSessionResult {
  final String styleId;
  final FacilitatorOutput output;

  /// Number of kanban tasks dispatched via `board_create_task`. Equals
  /// `output.toKanbanTasks().length`.
  final int kanbanTaskCount;

  const FacilitatorSeedSuccess({
    required this.styleId,
    required this.output,
    required this.kanbanTaskCount,
  });
}

class FacilitatorSeedFailure extends FacilitatorSessionResult {
  final String message;
  const FacilitatorSeedFailure(this.message);
}

// ─── Service ─────────────────────────────────────────────────────────────────

class FacilitatorSessionService {
  final SendStartFn _sendStart;
  final Stream<ServerMessage> _messages;
  final CreateKanbanTaskFn _createKanbanTask;
  final DecodeOutputFn _decodeOutput;
  final PersistOutputFn _persistOutput;

  FacilitatorSessionService({
    required SendStartFn sendStart,
    required Stream<ServerMessage> messages,
    required CreateKanbanTaskFn createKanbanTask,
    DecodeOutputFn? decodeOutput,
    PersistOutputFn? persistOutput,
  })  : _sendStart = sendStart,
        _messages = messages,
        _createKanbanTask = createKanbanTask,
        _decodeOutput = decodeOutput ?? _defaultDecode,
        _persistOutput = persistOutput ??
            FacilitatorOutputPersistenceService.save;

  /// Wires the orchestrator to a live [AgentWsService]. The session service
  /// only listens — it does not own the connection lifecycle.
  factory FacilitatorSessionService.bindToWsService(AgentWsService ws) =>
      FacilitatorSessionService(
        sendStart: ws.sendFacilitatorStart,
        messages: ws.messages,
        createKanbanTask: ws.boardCreateTask,
      );

  /// Runs one full pick → seed → kanban cycle. Resolves with either a
  /// [FacilitatorSeedSuccess] or [FacilitatorSeedFailure]; never throws
  /// for predictable server-side errors. Hard failures (timeout, decode
  /// error) also surface as [FacilitatorSeedFailure].
  Future<FacilitatorSessionResult> start({
    required String projectPath,
    required FacilitatorStyle style,
    required String projectDescription,
    required Map<String, String> answers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Subscribe BEFORE sending so we don't lose a fast reply. Filter for
    // the two facilitator-related events; ignore everything else.
    final completer = Completer<FacilitatorSessionResult>();
    late final StreamSubscription<ServerMessage> sub;
    sub = _messages.listen((msg) async {
      if (completer.isCompleted) return;
      if (msg is FacilitatorErrorMessage) {
        await sub.cancel();
        completer.complete(FacilitatorSeedFailure(msg.error));
        return;
      }
      if (msg is FacilitatorSeededMessage) {
        await sub.cancel();
        completer.complete(await _onSeeded(projectPath, msg));
      }
    });

    _sendStart(
      style: style,
      projectDescription: projectDescription,
      answers: answers,
    );

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      return FacilitatorSeedFailure(
        'Facilitator start timed out after ${timeout.inSeconds}s',
      );
    }
  }

  Future<FacilitatorSessionResult> _onSeeded(
    String projectPath,
    FacilitatorSeededMessage msg,
  ) async {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(msg.outputJson) as Map<String, dynamic>;
    } catch (e) {
      return FacilitatorSeedFailure('Output JSON not parseable: $e');
    }

    final output = _decodeOutput(json);
    if (output == null) {
      return FacilitatorSeedFailure(
        'No decoder registered for output format "${msg.outputFormat.key}"',
      );
    }

    // Persist first so a kanban-dispatch failure later doesn't lose the
    // seed; if persistence itself fails (disk full, permissions), keep
    // going — local cache is best-effort, the seed is in flight anyway.
    try {
      await _persistOutput(projectPath, output);
    } catch (_) {
      // swallowed: persistence is best-effort
    }

    final tasks = output.toKanbanTasks();
    for (final t in tasks) {
      _createKanbanTask(
        title: t.title,
        description: t.description,
        color: t.color.key,
        priority: t.priority.key,
        difficulty: t.difficulty,
        allowedRoles: t.allowedRoles,
        taskType: t.taskType,
      );
    }

    return FacilitatorSeedSuccess(
      styleId: msg.styleId,
      output: output,
      kanbanTaskCount: tasks.length,
    );
  }
}

// ─── Default decoder ─────────────────────────────────────────────────────────

FacilitatorOutput? _defaultDecode(Map<String, dynamic> json) =>
    FacilitatorOutputPersistenceService.decode(json);
