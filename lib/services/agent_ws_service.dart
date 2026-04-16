/// WebSocket client that connects to the PixelCode Node.js server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/agent_message.dart';

class AgentWsService {
  WebSocket? _ws;
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _isConnected = false;
  bool _disposed = false;
  Timer? _reconnectTimer;

  Stream<ServerMessage> get messages => _messageController.stream;

  /// Connection status stream that immediately yields the current state,
  /// then forwards all subsequent changes from the broadcast controller.
  /// This prevents StreamProviders from sitting in `loading` state.
  Stream<bool> get connectionStatus async* {
    yield _isConnected;
    yield* _connectionController.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect({required String url}) async {
    if (_disposed) return;
    try {
      _ws = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 10));
      _isConnected = true;
      _connectionController.add(true);
      _reconnectTimer?.cancel();

      _ws!.listen(
        (data) {
          try {
            final msg = ServerMessage.fromJson(data as String);
            _messageController.add(msg);
          } catch (e) {
            _messageController.add(ErrorMessage(message: 'Parse error: $e'));
          }
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect(url);
        },
        onError: (e) {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect(url);
        },
      );
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect(url);
    }
  }

  void sendMessage(
    String content, {
    String agentId = 'manager',
    List<String>? images,
  }) {
    _send({
      'type': 'send_message',
      'content': content,
      'agentId': agentId,
      if (images != null && images.isNotEmpty) 'images': images,
    });
  }

  void resumeSession(String sessionId) {
    _send({'type': 'resume_session', 'sessionId': sessionId});
  }

  void newChat() {
    _send({'type': 'new_chat'});
  }

  void clearSessions() {
    _send({'type': 'clear_sessions'});
  }

  void interrupt() {
    _send({'type': 'interrupt'});
  }

  void getStatus() {
    _send({'type': 'get_status'});
  }

  // ─── Task board ──────────────────────────────────────────────────────────

  void boardGetState() {
    _send({'type': 'board_get_state'});
  }

  void boardCreateTask({
    required String title,
    String? description,
    String? color,
    String? priority,
  }) {
    _send({
      'type': 'board_create_task',
      'title': title,
      'description': ?description,
      'color': ?color,
      'priority': ?priority,
    });
  }

  void boardMoveTask({required String taskId, required String column}) {
    _send({'type': 'board_move_task', 'taskId': taskId, 'column': column});
  }

  void boardUpdateTask({
    required String taskId,
    required Map<String, dynamic> updates,
  }) {
    _send({'type': 'board_update_task', 'taskId': taskId, 'updates': updates});
  }

  void boardDeleteTask({required String taskId}) {
    _send({'type': 'board_delete_task', 'taskId': taskId});
  }

  void boardAssignAgent({
    required String taskId,
    required String agentId,
    required bool assign,
  }) {
    _send({
      'type': 'board_assign_agent',
      'taskId': taskId,
      'agentId': agentId,
      'assign': assign,
    });
  }

  // ─── Project management ───────────────────────────────────────────────────

  void setProject(String path) {
    _send({'type': 'set_project', 'path': path});
  }

  void setProjectContext(String memories) {
    _send({'type': 'set_project_context', 'memories': memories});
  }

  void generateSummary() {
    _send({'type': 'generate_summary'});
  }

  // ─── Game economy ────────────────────────────────────────────────────────

  void setGameState({
    required List<String> hiredAgents,
    required Map<String, int> agentHardware,
    required Map<String, Map<String, int>> agentSkills,
    String? fullState,
  }) {
    _send({
      'type': 'set_game_state',
      'hiredAgents': hiredAgents,
      'agentHardware': agentHardware,
      'agentSkills': agentSkills,
      'fullState': ?fullState,
    });
  }

  // ─── Agent traits ────────────────────────────────────────────────────────

  void getTraits() {
    _send({'type': 'get_traits'});
  }

  void recordLesson({
    required String agentId,
    required String lessonType,
    required String category,
    required String tag,
    required String lesson,
  }) {
    _send({
      'type': 'record_lesson',
      'agentId': agentId,
      'lessonType': lessonType,
      'category': category,
      'tag': tag,
      'lesson': lesson,
    });
  }

  void removeLesson(String lessonId) {
    _send({'type': 'remove_lesson', 'lessonId': lessonId});
  }

  // ─── Character position sync ─────────────────────────────────────────────

  void syncPositions(Map<String, Map<String, dynamic>> positions) {
    _send({'type': 'sync_positions', 'positions': positions});
  }

  // ─── Live input sync ─────────────────────────────────────────────────────

  void sendInputText(String text) {
    _send({'type': 'input_text', 'text': text});
  }

  void sendInputImages(List<String> images) {
    _send({'type': 'input_images', 'images': images});
  }

  // ─── iOS deploy ──────────────────────────────────────────────────────────

  void iosDeployCheck() {
    _send({'type': 'ios_deploy_check'});
  }

  void iosDeployStart() {
    _send({'type': 'ios_deploy_start'});
  }

  void iosDeployCancel() {
    _send({'type': 'ios_deploy_cancel'});
  }

  // ─── Permissions bypass ───────────────────────────────────────────────────

  void setBypassPermissions(bool enabled) {
    _send({'type': 'set_bypass_permissions', 'enabled': enabled});
  }

  /// Force-close the current connection and reconnect immediately.
  Future<void> reconnect({required String url}) async {
    _reconnectTimer?.cancel();
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    _isConnected = false;
    _connectionController.add(false);
    await connect(url: url);
  }

  void _send(Map<String, dynamic> msg) {
    if (_ws != null && _isConnected) {
      _ws!.add(jsonEncode(msg));
    } else {
      debugPrint('[WS] Message dropped (not connected): ${msg['type']}');
    }
  }

  void _scheduleReconnect(String url) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => connect(url: url),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    await _ws?.close();
    await _messageController.close();
    await _connectionController.close();
  }
}
