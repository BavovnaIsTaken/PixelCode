/// Recording WebSocket fake — captures every board_* call and lets tests
/// pump server messages into the notifier.
library;

import 'dart:async';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class RecordedCall {
  final String method;
  final Map<String, dynamic> args;
  RecordedCall(this.method, this.args);

  @override
  String toString() => '$method(${args.toString()})';
}

class RecordingWsService extends AgentWsService {
  RecordingWsService({bool connected = true}) : _connected = connected;

  final _msgController = StreamController<ServerMessage>.broadcast();
  final _connController = StreamController<bool>.broadcast();
  bool _connected;
  final List<RecordedCall> calls = [];

  @override
  Stream<ServerMessage> get messages => _msgController.stream;

  @override
  Stream<bool> get connectionStatus async* {
    yield _connected;
    yield* _connController.stream;
  }

  @override
  Stream<String> get connectionLog => const Stream.empty();

  @override
  Stream<String?> get phaseStatus async* {
    yield null;
  }

  @override
  bool get isConnected => _connected;

  void setConnected(bool value) {
    _connected = value;
    _connController.add(value);
  }

  void emit(ServerMessage msg) {
    _msgController.add(msg);
  }

  RecordedCall? lastCall(String method) {
    for (final c in calls.reversed) {
      if (c.method == method) return c;
    }
    return null;
  }

  int countCalls(String method) =>
      calls.where((c) => c.method == method).length;

  // ─── Recorded board API ─────────────────────────────────────────────────

  @override
  void boardGetState({int? since}) {
    calls.add(RecordedCall('boardGetState', {
      if (since != null) 'since': since,
    }));
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
    calls.add(RecordedCall('boardCreateTask', {
      'title': title,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
      if (priority != null) 'priority': priority,
      if (difficulty != null) 'difficulty': difficulty,
      if (allowedRoles != null) 'allowedRoles': allowedRoles,
      if (taskType != null) 'taskType': taskType,
    }));
  }

  @override
  void boardMoveTask({required String taskId, required String column}) {
    calls.add(RecordedCall('boardMoveTask', {
      'taskId': taskId,
      'column': column,
    }));
  }

  @override
  void boardUpdateTask({
    required String taskId,
    required Map<String, dynamic> updates,
  }) {
    calls.add(RecordedCall('boardUpdateTask', {
      'taskId': taskId,
      'updates': updates,
    }));
  }

  @override
  void boardDeleteTask({required String taskId}) {
    calls.add(RecordedCall('boardDeleteTask', {'taskId': taskId}));
  }

  @override
  void boardAssignAgent({
    required String taskId,
    required String agentId,
    required bool assign,
  }) {
    calls.add(RecordedCall('boardAssignAgent', {
      'taskId': taskId,
      'agentId': agentId,
      'assign': assign,
    }));
  }

  @override
  void boardAddAttachment({
    required String taskId,
    required String name,
    required String mimeType,
    required int sizeBytes,
    required String dataBase64,
  }) {
    calls.add(RecordedCall('boardAddAttachment', {
      'taskId': taskId,
      'name': name,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'dataBase64': dataBase64,
    }));
  }

  @override
  void boardRemoveAttachment({
    required String taskId,
    required String attachmentId,
  }) {
    calls.add(RecordedCall('boardRemoveAttachment', {
      'taskId': taskId,
      'attachmentId': attachmentId,
    }));
  }

  @override
  Future<void> dispose() async {
    await _msgController.close();
    await _connController.close();
  }
}
