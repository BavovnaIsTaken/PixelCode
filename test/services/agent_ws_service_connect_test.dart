/// Integration-style coverage for `AgentWsService.connect()` against a real
/// loopback WebSocket server (`HttpServer.bind` + `WebSocketTransformer`).
///
/// Exercises the on-the-wire happy path:
///   * connect → flips `isConnected`, clears `phase`, emits a log line
///   * handshake → first frame is `client_info`, second frame is `get_traits`
///   * onData → server_info / chat_history / facilitator_output_sync are
///     buffered into their `lastX` slots and also flow through `messages`
///   * parse error → garbage payload becomes an `ErrorMessage` on the
///     `messages` stream and the connection stays alive
///
/// The companion file `agent_ws_service_test.dart` covers the offline
/// surface (initial state, log formatting, send-while-disconnected drop,
/// setDeviceName idempotency, dispose idempotency) — none of that is
/// duplicated here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

/// Boots a loopback WebSocket server and returns its URL + a stream of
/// upgraded sockets. Each accepted upgrade is pushed to the controller so
/// tests can await the server-side socket and inspect what the client sends.
Future<({HttpServer server, String url, Stream<WebSocket> sockets})>
    _startServer() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final socketController = StreamController<WebSocket>.broadcast();
  server.listen((HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(request);
      socketController.add(ws);
    } else {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  });
  return (
    server: server,
    url: 'ws://127.0.0.1:${server.port}/',
    sockets: socketController.stream,
  );
}

void main() {
  group('connect — happy path', () {
    test('flips isConnected=true and clears phase to null', () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      // Drain the server socket so the client's frames don't back-pressure.
      s.sockets.listen((ws) => ws.listen((_) {}));

      // Kick off the connect; don't await (it spins up listeners after the
      // initial connect, but the future returns once the handshake is done).
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));

      // connectionStatus yields current value first, so filter for `true`.
      final connected = await svc.connectionStatus
          .firstWhere((c) => c)
          .timeout(const Duration(seconds: 3));
      expect(connected, isTrue);
      expect(svc.isConnected, isTrue);

      final phase = await svc.phaseStatus.first
          .timeout(const Duration(seconds: 3));
      expect(phase, isNull,
          reason: 'phase clears to null on successful connect');
    });

    test('sends client_info → set_bypass_permissions → get_traits as the first three frames',
        () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      // Capture the first three frames the server receives.
      final framesCompleter = Completer<List<String>>();
      final received = <String>[];
      s.sockets.listen((ws) {
        ws.listen((data) {
          received.add(data as String);
          if (received.length == 3 && !framesCompleter.isCompleted) {
            framesCompleter.complete(List.of(received));
          }
        });
      });

      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final frames =
          await framesCompleter.future.timeout(const Duration(seconds: 3));

      final clientInfo = jsonDecode(frames[0]) as Map<String, dynamic>;
      expect(clientInfo['type'], 'client_info');
      expect(clientInfo['clientId'], isA<String>());
      expect(clientInfo['clientId'] as String,
          matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(clientInfo['deviceName'], isA<String>());
      expect((clientInfo['deviceName'] as String).isNotEmpty, isTrue);
      expect(clientInfo['platform'], isA<String>());
      expect((clientInfo['platform'] as String).isNotEmpty, isTrue);

      final bypass = jsonDecode(frames[1]) as Map<String, dynamic>;
      expect(bypass['type'], 'set_bypass_permissions');

      final getTraits = jsonDecode(frames[2]) as Map<String, dynamic>;
      expect(getTraits['type'], 'get_traits');
    });

    test('emits a "Connected to ws://…" log line on connect', () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      s.sockets.listen((ws) => ws.listen((_) {}));

      final connectedLog = svc.connectionLog
          .firstWhere((l) => l.contains('Connected to ${s.url}'))
          .timeout(const Duration(seconds: 3));

      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final line = await connectedLog;
      expect(line, contains('Connected to ${s.url}'));
    });
  });

  group('onData — buffering', () {
    test('server_info messages land in lastServerInfo', () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final socketReady = s.sockets.first;
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final ws = await socketReady.timeout(const Duration(seconds: 3));
      // Drain inbound client frames so the socket stays healthy.
      ws.listen((_) {});

      final serverInfoSeen = svc.messages
          .firstWhere((m) => m is ServerInfoMessage)
          .timeout(const Duration(seconds: 3));

      ws.add(jsonEncode({
        'type': 'server_info',
        'hostname': 'studio-mac.local',
        'localIps': ['192.168.1.10'],
        'port': 9720,
      }));

      await serverInfoSeen;
      expect(svc.lastServerInfo, isNotNull);
      expect(svc.lastServerInfo!.hostname, 'studio-mac.local');
      expect(svc.lastServerInfo!.port, 9720);
    });

    test('chat_history messages land in lastChatHistory', () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final socketReady = s.sockets.first;
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final ws = await socketReady.timeout(const Duration(seconds: 3));
      ws.listen((_) {});

      final chatHistorySeen = svc.messages
          .firstWhere((m) => m is ChatHistoryMessage)
          .timeout(const Duration(seconds: 3));

      ws.add(jsonEncode({
        'type': 'chat_history',
        'messages': <Map<String, dynamic>>[],
      }));

      await chatHistorySeen;
      expect(svc.lastChatHistory, isNotNull);
      expect(svc.lastChatHistory!.messages, isEmpty);
    });

    test('facilitator_output_sync messages land in lastFacilitatorOutputSync',
        () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final socketReady = s.sockets.first;
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final ws = await socketReady.timeout(const Duration(seconds: 3));
      ws.listen((_) {});

      final syncSeen = svc.messages
          .firstWhere((m) => m is FacilitatorOutputSyncMessage)
          .timeout(const Duration(seconds: 3));

      ws.add(jsonEncode({
        'type': 'facilitator_output_sync',
        'styleId': 'x',
        'outputFormat': 'quest_line',
        'outputJson': '{}',
      }));

      await syncSeen;
      expect(svc.lastFacilitatorOutputSync, isNotNull);
      expect(svc.lastFacilitatorOutputSync!.styleId, 'x');
      expect(svc.lastFacilitatorOutputSync!.outputJson, '{}');
    });

    test('parsed messages flow through the messages stream', () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final socketReady = s.sockets.first;
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final ws = await socketReady.timeout(const Duration(seconds: 3));
      ws.listen((_) {});

      final next = svc.messages.first.timeout(const Duration(seconds: 3));
      ws.add(jsonEncode({
        'type': 'server_info',
        'hostname': 'live-emit-host',
        'localIps': <String>[],
        'port': 9720,
      }));

      final m = await next;
      expect(m, isA<ServerInfoMessage>());
      final info = m as ServerInfoMessage;
      expect(info.hostname, 'live-emit-host');
      // And the same instance must be the buffered one — buffering happens
      // BEFORE the controller.add inside the listener.
      expect(identical(svc.lastServerInfo, info), isTrue);
    });
  });

  group('onData — parse error', () {
    test('garbage payload becomes an ErrorMessage and stays connected',
        () async {
      final s = await _startServer();
      addTearDown(() async => s.server.close(force: true));
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final socketReady = s.sockets.first;
      await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
      final ws = await socketReady.timeout(const Duration(seconds: 3));
      ws.listen((_) {});

      final errSeen = svc.messages
          .firstWhere((m) => m is ErrorMessage)
          .timeout(const Duration(seconds: 3));

      ws.add('not json');

      final err = await errSeen as ErrorMessage;
      expect(err.message, contains('Parse error'));
      expect(svc.isConnected, isTrue,
          reason: 'parse failure must not tear the socket down');
    });
  });
}
