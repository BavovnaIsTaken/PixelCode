/// WebSocket client that connects to the PixelCode Node.js server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/agent_message.dart';

class AgentWsService {
  WebSocket? _ws;
  StreamSubscription? _wsSub;
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _connLogController = StreamController<String>.broadcast();
  bool _isConnected = false;
  bool _disposed = false;
  Timer? _reconnectTimer;

  /// Stable client ID (generated once per app instance).
  late final String clientId = _generateClientId();

  static String _generateClientId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String get _platformName {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// Last received server_info (buffered so late subscribers can read it).
  ServerInfoMessage? lastServerInfo;

  /// Last received chat_history (buffered so late subscribers can read it).
  /// Fixes race condition where chat_history arrives before ChatNotifier subscribes
  /// (common on localhost where server response is near-instant).
  ChatHistoryMessage? lastChatHistory;

  Stream<ServerMessage> get messages => _messageController.stream;

  /// In-app connection log — visible on device for debugging.
  Stream<String> get connectionLog => _connLogController.stream;

  void _log(String msg) => log(msg);

  /// Public log sink — other services (e.g. mDNS discovery) can write here
  /// so their output appears in the in-app connection console.
  void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$ts] $msg';
    debugPrint('[WS] $msg');
    if (!_connLogController.isClosed) _connLogController.add(line);
  }

  /// Connection status stream that immediately yields the current state,
  /// then forwards all subsequent changes from the broadcast controller.
  /// This prevents StreamProviders from sitting in `loading` state.
  Stream<bool> get connectionStatus async* {
    yield _isConnected;
    yield* _connectionController.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect({required String url}) async {
    if (_disposed) {
      _log('connect($url) — disposed, skipping');
      return;
    }
    _log('Connecting to $url …');
    try {
      // For .ts.net hosts: try normal connection first, use DoH custom
      // client only if system DNS can't resolve the hostname.
      HttpClient? customClient;
      final uri = Uri.parse(url);
      if (uri.host.endsWith('.ts.net')) {
        final dohIp = await _resolveViaDoHIfNeeded(uri.host);
        if (dohIp != null) {
          _log('Using DoH route → $dohIp:443');
          customClient = HttpClient()
            ..connectionFactory =
                (Uri u, String? proxyHost, int? proxyPort) {
              return Socket.startConnect(dohIp, 443);
            };
        }
      }

      _ws = await WebSocket.connect(url, customClient: customClient)
          .timeout(const Duration(seconds: 10));
      // dispose() may have been called while we were awaiting the connection.
      if (_disposed) { await _ws?.close(); return; }
      _isConnected = true;
      if (!_connectionController.isClosed) _connectionController.add(true);
      _reconnectTimer?.cancel();
      _log('Connected to $url');
      _sendClientInfo();

      _wsSub = _ws!.listen(
        (data) {
          try {
            final msg = ServerMessage.fromJson(data as String);
            // Buffer server_info so late subscribers can read it
            if (msg is ServerInfoMessage) lastServerInfo = msg;
            // Buffer chat_history so late subscribers can read it
            if (msg is ChatHistoryMessage) lastChatHistory = msg;
            if (!_messageController.isClosed) _messageController.add(msg);
          } catch (e) {
            if (!_messageController.isClosed) {
              _messageController.add(ErrorMessage(message: 'Parse error: $e'));
            }
          }
        },
        onDone: () {
          _log('Connection closed (onDone)');
          if (_disposed) return;
          _isConnected = false;
          if (!_connectionController.isClosed) _connectionController.add(false);
          _scheduleReconnect(url);
        },
        onError: (e) {
          _log('Connection error: $e');
          if (_disposed) return;
          _isConnected = false;
          if (!_connectionController.isClosed) _connectionController.add(false);
          _scheduleReconnect(url);
        },
      );
    } on TimeoutException {
      _log('Timeout connecting to $url (10s)');
      if (_disposed) return;
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
      _scheduleReconnect(url);
    } catch (e) {
      _log('Failed to connect: $e');
      if (_disposed) return;
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
      _scheduleReconnect(url);
    }
  }

  // ─── DNS resolution with DoH fallback ────────────────────────────────────

  /// Returns a DoH-resolved IP only when system DNS fails.
  /// Returns null when system DNS works (let WebSocket.connect handle it).
  Future<String?> _resolveViaDoHIfNeeded(String hostname) async {
    // 1. Check system DNS — if it works, return null (no override needed)
    try {
      final results = await InternetAddress.lookup(hostname)
          .timeout(const Duration(seconds: 3));
      if (results.isNotEmpty) {
        _log('System DNS OK: $hostname → ${results.first.address}');
        return null;
      }
    } catch (_) {
      _log('System DNS failed for $hostname, trying DoH…');
    }

    // 2. System DNS failed — resolve via DNS-over-HTTPS
    try {
      final dohUri = Uri.parse(
        'https://dns.google/resolve?name=$hostname&type=A',
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(dohUri)
            .timeout(const Duration(seconds: 5));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final answers = json['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          final ip = answers.first['data'] as String;
          _log('DoH resolved: $hostname → $ip');
          return ip;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _log('DoH resolution failed: $e');
    }

    return null;
  }

  void sendMessage(
    String content, {
    String agentId = 'manager',
    List<String>? images,
    int? taskDifficulty,
    bool forceSend = false,
  }) {
    _send({
      'type': 'send_message',
      'content': content,
      'agentId': agentId,
      if (images != null && images.isNotEmpty) 'images': images,
      if (taskDifficulty != null) 'taskDifficulty': taskDifficulty,
      if (forceSend) 'forceSend': true,
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
    int? stateUpdatedAt,
  }) {
    _send({
      'type': 'set_game_state',
      'hiredAgents': hiredAgents,
      'agentHardware': agentHardware,
      'agentSkills': agentSkills,
      'fullState': ?fullState,
      'stateUpdatedAt': ?stateUpdatedAt,
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

  // ─── Dungeon training ────────────────────────────────────────────────────

  void startDungeon({
    required String agentId,
    required int skillType,
    required int difficulty,
  }) {
    _send({
      'type': 'start_dungeon',
      'agentId': agentId,
      'skillType': skillType,
      'difficulty': difficulty.clamp(1, 3),
    });
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

  // ─── Android deploy ──────────────────────────────────────────────────────

  void androidDeployCheck() {
    _send({'type': 'android_deploy_check'});
  }

  void androidDeployListDevices() {
    _send({'type': 'android_deploy_list_devices'});
  }

  void androidDeployStart({String? deviceSerial}) {
    _send({
      'type': 'android_deploy_start',
      'deviceSerial': ?deviceSerial,
    });
  }

  void androidDeployCancel() {
    _send({'type': 'android_deploy_cancel'});
  }

  // ─── Device screenshot ───────────────────────────────────────────────────

  void captureScreenshot({required String platform, String? deviceSerial}) {
    _send({
      'type': 'screenshot_capture',
      'platform': platform,
      'deviceSerial': ?deviceSerial,
    });
  }

  // ─── Tailscale setup ─────────────────────────────────────────────────────

  void tailscaleConnect() {
    _send({'type': 'tailscale_connect'});
  }

  // ─── Permissions bypass ───────────────────────────────────────────────────

  void setBypassPermissions(bool enabled) {
    _send({'type': 'set_bypass_permissions', 'enabled': enabled});
  }

  // ─── Client identification ───────────────────────────────────────────────

  void _sendClientInfo() {
    _send({
      'type': 'client_info',
      'hostname': Platform.localHostname,
      'platform': _platformName,
      'clientId': clientId,
    });
  }

  /// Force-close the current connection and reconnect immediately.
  Future<void> reconnect({required String url}) async {
    if (_disposed) return;
    _log('Reconnecting to $url …');
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    _isConnected = false;
    if (!_connectionController.isClosed) _connectionController.add(false);
    await connect(url: url);
  }

  void _send(Map<String, dynamic> msg) {
    if (_ws != null && _isConnected && !_disposed) {
      _ws!.add(jsonEncode(msg));
    } else {
      _log('Message dropped (not connected): ${msg['type']}');
    }
  }

  void _scheduleReconnect(String url) {
    if (_disposed) return;
    _log('Reconnect scheduled in 3s → $url');
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
    // Cancel the WS subscription BEFORE closing controllers — onDone/onError
    // are delivered as microtasks and can arrive after _ws?.close() resolves,
    // causing "Bad state: Cannot add new events after calling close".
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.close();
    await _messageController.close();
    await _connectionController.close();
    await _connLogController.close();
  }
}
