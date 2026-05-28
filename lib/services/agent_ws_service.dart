/// WebSocket client that connects to the PixelCode Node.js server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/agent_message.dart';
import '../models/facilitator_style.dart';
import '../utils/device_identity.dart';
import 'ws_outbox.dart';

class AgentWsService {
  WebSocket? _ws;
  StreamSubscription? _wsSub;
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _connLogController = StreamController<String>.broadcast();
  final _phaseController = StreamController<String?>.broadcast();
  bool _isConnected = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// Outbox for messages submitted while the socket is down. Drained in
  /// FIFO order after the next successful (re)connect, immediately after
  /// the `client_info` handshake. Capped + ephemeral-type denylist live
  /// inside `WsOutbox`; the service just forwards.
  final WsOutbox _outbox = WsOutbox();

  /// Short status token (≤5 chars) shown by the connection terminal widget.
  /// `null` once a session is established — the widget hides itself.
  String? _phase;

  void _emitPhase(String? phase) {
    _phase = phase;
    if (!_phaseController.isClosed) _phaseController.add(phase);
  }

  /// Stable client ID (generated once per app instance).
  late final String clientId = _generateClientId();

  /// Device label sent in the `client_info` handshake — auto-derived from the
  /// OS hostname. Re-sent on every (re)connect. Surfaced to the host via the
  /// admin HTTP API; main clients no longer display a connected-devices list.
  String _deviceName = sanitizeDeviceName(
    Platform.localHostname,
    currentPlatformName(),
  );

  static String _generateClientId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Last received server_info (buffered so late subscribers can read it).
  ServerInfoMessage? lastServerInfo;

  /// Last received chat_history (buffered so late subscribers can read it).
  /// Fixes race condition where chat_history arrives before ChatNotifier subscribes
  /// (common on localhost where server response is near-instant).
  ChatHistoryMessage? lastChatHistory;

  /// Last received facilitator_output_sync — buffered so the onboarding check
  /// can find it before the disk write completes (eliminates the race window
  /// between server connect and FacilitatorAutoOnboarder._maybeRun).
  FacilitatorOutputSyncMessage? lastFacilitatorOutputSync;

  /// Last received init — buffered so late subscribers (notably
  /// WorkingDirectoryNotifier on mobile cold-start) can read the working
  /// directory even if their first `ref.read` happens after the InitMessage
  /// already passed through the broadcast controller. Without this buffer
  /// the value stays `null` until a reconnect.
  InitMessage? lastInit;

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

  /// Short status token stream (≤5 chars). `null` means connected/idle.
  /// Yields current value first so late subscribers see state immediately.
  Stream<String?> get phaseStatus async* {
    yield _phase;
    yield* _phaseController.stream;
  }

  Future<void> connect({required String url}) async {
    if (_disposed) {
      _log('connect($url) — disposed, skipping');
      return;
    }
    _log('Connecting to $url …');
    _emitPhase('CONN');
    try {
      // For .ts.net hosts: try normal connection first, use DoH custom
      // client only if system DNS can't resolve the hostname.
      HttpClient? customClient;
      final uri = Uri.parse(url);
      if (uri.host.endsWith('.ts.net')) {
        _emitPhase('DNS');
        final dohIp = await _resolveViaDoHIfNeeded(uri.host);
        if (dohIp != null) {
          _log('Using DoH route → $dohIp:443');
          customClient = HttpClient()
            ..connectionFactory =
                (Uri u, String? proxyHost, int? proxyPort) {
              return Socket.startConnect(dohIp, 443);
            };
        }
        _emitPhase('CONN');
      }

      _ws = await WebSocket.connect(url, customClient: customClient)
          .timeout(const Duration(seconds: 10));
      // dispose() may have been called while we were awaiting the connection.
      if (_disposed) { await _ws?.close(); return; }
      // Heartbeat: dart:io's WebSocket sends a Ping every [pingInterval] and
      // expects a Pong within the same window — if the peer is silent the
      // socket closes with 1006, which fires onDone and triggers reconnect.
      // Pairs with the server-side ping cycle in server.ts: either side can
      // notice a half-open socket within ~30 s on mobile Wi-Fi↔LTE handoffs.
      _ws!.pingInterval = const Duration(seconds: 30);
      _isConnected = true;
      _reconnectAttempt = 0;
      if (!_connectionController.isClosed) _connectionController.add(true);
      _emitPhase(null);
      _reconnectTimer?.cancel();
      _log('Connected to $url');
      _sendClientInfo();
      setBypassPermissions(true);
      getTraits();
      // Drain anything queued during the outage. Order: client_info first
      // so the server has re-identified this device before user-action
      // replays land — keeps session presence stable across the gap.
      _drainOutbox();

      _wsSub = _ws!.listen(
        (data) {
          try {
            final msg = ServerMessage.fromJson(data as String);
            // Buffer server_info so late subscribers can read it
            if (msg is ServerInfoMessage) lastServerInfo = msg;
            // Buffer chat_history so late subscribers can read it
            if (msg is ChatHistoryMessage) lastChatHistory = msg;
            // Buffer facilitator sync so onboarding skips before disk check
            if (msg is FacilitatorOutputSyncMessage) lastFacilitatorOutputSync = msg;
            // Buffer init so WorkingDirectoryNotifier can seed from it
            if (msg is InitMessage) lastInit = msg;
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
          _emitPhase('DROP');
          _scheduleReconnect(url);
        },
        onError: (e) {
          _log('Connection error: $e');
          if (_disposed) return;
          _isConnected = false;
          if (!_connectionController.isClosed) _connectionController.add(false);
          _emitPhase('ERR');
          _scheduleReconnect(url);
        },
      );
    } on TimeoutException {
      _log('Timeout connecting to $url (10s)');
      if (_disposed) return;
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
      _emitPhase('TMOUT');
      _scheduleReconnect(url);
    } catch (e) {
      _log('Failed to connect: $e');
      if (_disposed) return;
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
      _emitPhase('FAIL');
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
    String? localId,
  }) {
    _send({
      'type': 'send_message',
      'content': content,
      'agentId': agentId,
      if (images != null && images.isNotEmpty) 'images': images,
      'localId': ?localId,
    });
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

  /// Request the current board state.
  ///
  /// On reconnect, pass [since] = last applied revision so the server can
  /// reply with a cheap `board_state_unchanged` instead of re-shipping
  /// every task. Pre-WP2 servers ignore the field and always send a full
  /// snapshot.
  void boardGetState({int? since}) {
    _send({
      'type': 'board_get_state',
      'since': ?since,
    });
  }

  /// Pull the tech-lead pulse (recent task-completion digest) from the
  /// server. Server replies with a [TechLeadPulseMessage] regardless of
  /// whether the digest has any entries — clients use the response to
  /// transition out of a loading state.
  void getTechLeadPulse({int? limit}) {
    _send({
      'type': 'get_tech_lead_pulse',
      'limit': ?limit,
    });
  }

  /// Atomically seed multiple tasks. Server validates every entry first;
  /// on any failure none are committed and a `board_seed_batch_result`
  /// with `ok: false` is returned. [source] is stamped onto each task so
  /// the manager auto-dispatcher can recognise facilitator-emitted tasks.
  void boardSeedBatch({
    String? batchId,
    String? source,
    required List<Map<String, dynamic>> tasks,
  }) {
    _send({
      'type': 'board_seed_batch',
      'batchId': ?batchId,
      'source': ?source,
      'tasks': tasks,
    });
  }

  void boardCreateTask({
    required String title,
    String? description,
    String? color,
    String? priority,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) {
    _send({
      'type': 'board_create_task',
      'title': title,
      'description': ?description,
      'color': ?color,
      'priority': ?priority,
      'difficulty': ?difficulty,
      'allowedRoles': ?allowedRoles,
      'taskType': ?taskType,
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

  void boardAddAttachment({
    required String taskId,
    required String name,
    required String mimeType,
    required int sizeBytes,
    required String dataBase64,
  }) {
    _send({
      'type': 'board_add_attachment',
      'taskId': taskId,
      'name': name,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'dataBase64': dataBase64,
    });
  }

  void boardRemoveAttachment({
    required String taskId,
    required String attachmentId,
  }) {
    _send({
      'type': 'board_remove_attachment',
      'taskId': taskId,
      'attachmentId': attachmentId,
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

  /// Send the current game state to the server.
  ///
  /// [instances] keys the hired agents by their instanceId (e.g. "coder#1").
  /// Each value carries roleType, nickname, hardware tier index, and skill
  /// levels — matches the server's `GameStateData` contract.
  void setGameState({
    required Map<String, Map<String, dynamic>> instances,
    String? fullState,
    int? stateUpdatedAt,
    String? deepseekApiKey,
    String? kimiApiKey,
  }) {
    _send({
      'type': 'set_game_state',
      'instances': instances,
      'fullState': fullState,
      'stateUpdatedAt': stateUpdatedAt,
      'deepseekApiKey': deepseekApiKey,
      'kimiApiKey': kimiApiKey,
    });
  }

  // ─── Session presence ────────────────────────────────────────────────────

  void claimSession() => _send({'type': 'session_claim'});
  void releaseSession() => _send({'type': 'session_release'});

  // ─── Active agents ───────────────────────────────────────────────────────

  void listActiveAgents() => _send({'type': 'list_active_agents'});
  void cancelDispatchAgent(String dispatchId) =>
      _send({'type': 'cancel_dispatch_agent', 'dispatchId': dispatchId});
  void cancelChatQuery(String queryId) =>
      _send({'type': 'cancel_chat_query', 'queryId': queryId});
  void cancelAllActive() => _send({'type': 'cancel_all_active'});

  // ─── Run history ─────────────────────────────────────────────────────────

  /// Ask the server for every run that started after [sinceRunId]. A null
  /// cursor returns everything the server knows about — used on first connect
  /// and after server respawn so the UI can show interrupted runs.
  void listRunsSince(String? sinceRunId) {
    _send({
      'type': 'list_runs_since',
      'sinceRunId': ?sinceRunId,
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

  // ─── Facilitator System ──────────────────────────────────────────────────

  /// Seeds a project with the chosen facilitator style. The server runs
  /// intake → scope-score → output-generator and replies with either a
  /// `facilitator_seeded` (success) or `facilitator_error` ServerMessage.
  ///
  /// The full style is sent over the wire so the server stays neutral
  /// about presets — same path also serves user-defined / marketplace
  /// styles down the line.
  void sendFacilitatorStart({
    required FacilitatorStyle style,
    required String projectDescription,
    required Map<String, String> answers,
  }) {
    _send({
      'type': 'facilitator_start',
      'style': style.toJson(),
      'projectDescription': projectDescription,
      'answers': answers,
    });
  }

  /// Ask the server for its persisted facilitator output.
  /// Server replies with `facilitator_output_sync` if one exists.
  void sendGetFacilitatorOutput() {
    _send({'type': 'get_facilitator_output'});
  }

  /// Upload local facilitator output to the server so other devices can sync.
  /// Server only stores it if it has nothing yet (safe to call unconditionally).
  void sendPushFacilitatorOutput({
    required String outputFormat,
    required String outputJson,
  }) {
    _send({
      'type': 'push_facilitator_output',
      'outputFormat': outputFormat,
      'outputJson': outputJson,
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

  void androidDeployWatchDevices() {
    _send({'type': 'android_deploy_watch_devices'});
  }

  void androidDeployUnwatchDevices() {
    _send({'type': 'android_deploy_unwatch_devices'});
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

  // ─── Network diagnostics ────────────────────────────────────────────────

  void healthCheckRequest() {
    _send({'type': 'health_check_request'});
  }

  void healthFixRequest(String itemId) {
    _send({'type': 'health_fix_request', 'id': itemId});
  }

  // ─── Permissions bypass ───────────────────────────────────────────────────

  void setBypassPermissions(bool enabled) {
    _send({'type': 'set_bypass_permissions', 'enabled': enabled});
  }

  // ─── Client identification ───────────────────────────────────────────────

  /// Override the device label sent in the `client_info` handshake. Safe to
  /// call at any time: if already connected, the server is notified
  /// immediately; otherwise the new value is used on the next (re)connect.
  void setDeviceName(String deviceName) {
    final platform = currentPlatformName();
    final resolved = sanitizeDeviceName(deviceName, platform);
    if (resolved == _deviceName) return;
    _deviceName = resolved;
    if (_isConnected) _sendClientInfo();
  }

  void _sendClientInfo() {
    _send({
      'type': 'client_info',
      'clientId': clientId,
      'deviceName': _deviceName,
      'platform': currentPlatformName(),
    });
  }

  /// Close the current connection without scheduling a reconnect.
  /// Used when the app goes to background so the server receives a clean
  /// close frame rather than a TCP timeout.
  Future<void> disconnect() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    if (_isConnected) {
      _isConnected = false;
      if (!_connectionController.isClosed) _connectionController.add(false);
    }
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
      return;
    }
    if (_disposed) return;
    final type = msg['type'] as String?;
    final result = _outbox.enqueue(msg);
    switch (result) {
      case EnqueueResult.droppedEphemeral:
        _log('Ephemeral dropped (not connected): $type');
      case EnqueueResult.evictedOldest:
        _log('Outbox full — evicted oldest to make room for: $type');
      case EnqueueResult.enqueued:
        _log('Outbox queued (${_outbox.length}/${_outbox.cap}): $type');
    }
  }

  /// Send everything sitting in the outbox in FIFO order. Called after a
  /// reconnect once `client_info` has been resent so the server has
  /// already re-identified this device. Server-side `ChatHistory.add` is
  /// idempotent on caller-supplied id, so even if a queued message
  /// originally raced past flush before onDone fired, the replay is safe.
  void _drainOutbox() {
    if (!_isConnected || _ws == null || _disposed) return;
    final pending = _outbox.drainAll();
    if (pending.isEmpty) return;
    _log('Draining outbox (${pending.length} message(s))');
    for (final m in pending) {
      _ws!.add(jsonEncode(m));
    }
  }

  void _scheduleReconnect(String url) {
    if (_disposed) return;
    final delay = backoffDelay(_reconnectAttempt, Random().nextDouble());
    _reconnectAttempt++;
    _log('Reconnect in ${delay.inMilliseconds}ms (attempt $_reconnectAttempt) → $url');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _emitPhase('RTRY');
      connect(url: url);
    });
    // While the timer is counting down, surface a WAIT badge — but only if
    // we're not already showing a more specific terminal phase like FAIL/ERR
    // (those flip to WAIT after a brief moment so the user sees the cause first).
    Timer(const Duration(milliseconds: 700), () {
      if (_disposed) return;
      if (_isConnected) return;
      if (_reconnectTimer?.isActive != true) return;
      _emitPhase('WAIT');
    });
  }

  /// Exponential backoff with ±20% jitter. Caps at 30 s.
  /// [jitter] is a [0, 1) random value — injectable for tests.
  @visibleForTesting
  static Duration backoffDelay(int attempt, double jitter) {
    final base = min(1 << attempt, 30); // seconds: 1,2,4,8,16,30,30,…
    final ms = (base * 1000 * (0.8 + jitter * 0.4)).round();
    return Duration(milliseconds: ms);
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
    await _phaseController.close();
  }
}
