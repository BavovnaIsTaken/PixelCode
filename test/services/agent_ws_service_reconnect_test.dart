library;

/// Integration-style coverage for `AgentWsService` paths that need a live
/// loopback WebSocket: the onDone reconnect cycle (DROP → WAIT badges),
/// the manual `reconnect()` force-restart, the `setDeviceName` wire-level
/// re-handshake while connected, and the dispose-during-await race.
///
/// Sibling coverage (don't duplicate here):
///   - `agent_ws_service_test.dart` — offline lifecycle, drop logs, dispose
///     idempotency.
///   - `agent_ws_service_connect_test.dart` — happy-path connect, onData
///     buffering, parse-error surface.
///
/// We bind a real loopback server (`127.0.0.1:0` so the kernel picks a free
/// port) and upgrade incoming HTTP requests to WebSockets. Every test owns
/// its own server + service pair and cleans them up via `addTearDown`.
/// Wall-clock waits are kept short (≤1s) and we always dispose **before**
/// the service's 3s reconnect timer fires.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_service.dart';
import 'package:pixelcode/utils/device_identity.dart';

/// Spins up an ephemeral loopback HTTP server that upgrades any request to
/// a WebSocket, pushing each upgraded socket onto [onSocket] for the test
/// to drive.
Future<HttpServer> _startLoopbackWsServer(
  void Function(WebSocket ws) onSocket,
) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((HttpRequest request) async {
    final ws = await WebSocketTransformer.upgrade(request);
    onSocket(ws);
  });
  return server;
}

String _wsUrl(HttpServer server) =>
    'ws://127.0.0.1:${server.port}/';

void main() {
  group('onDone — server closes connection', () {
    test('flips to disconnected + emits DROP phase', () async {
      final serverSockets = <WebSocket>[];
      final server = await _startLoopbackWsServer(serverSockets.add);
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      // Track phases from subscription start so we don't miss `DROP`.
      final phases = <String?>[];
      final phaseSub = svc.phaseStatus.listen(phases.add);
      addTearDown(phaseSub.cancel);

      await svc.connect(url: _wsUrl(server))
          .timeout(const Duration(seconds: 3));
      expect(svc.isConnected, isTrue);

      // Wait until the server's side of the socket is registered.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(serverSockets, isNotEmpty);

      // Race-free disconnect listener: subscribe BEFORE closing.
      final disconnected = svc.connectionStatus
          .firstWhere((c) => c == false)
          .timeout(const Duration(seconds: 3));
      final dropEmitted = svc.phaseStatus
          .firstWhere((p) => p == 'DROP')
          .timeout(const Duration(seconds: 3));

      await serverSockets.first.close();

      await disconnected;
      await dropEmitted;

      expect(svc.isConnected, isFalse);
      expect(phases, contains('DROP'));
    });

    test('after DROP, WAIT phase appears within ~1s', () async {
      final serverSockets = <WebSocket>[];
      final server = await _startLoopbackWsServer(serverSockets.add);
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      await svc.connect(url: _wsUrl(server))
          .timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final waitEmitted = svc.phaseStatus
          .firstWhere((p) => p == 'WAIT')
          .timeout(const Duration(seconds: 3));

      await serverSockets.first.close();
      await waitEmitted;
      // dispose() runs via addTearDown before the 3s reconnect timer fires.
    });

    test('connectionLog records "Connection closed (onDone)"', () async {
      final serverSockets = <WebSocket>[];
      final server = await _startLoopbackWsServer(serverSockets.add);
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final loggedClose = svc.connectionLog
          .firstWhere((l) => l.contains('Connection closed (onDone)'))
          .timeout(const Duration(seconds: 3));

      await svc.connect(url: _wsUrl(server))
          .timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await serverSockets.first.close();

      final line = await loggedClose;
      expect(line, contains('Connection closed (onDone)'));
    });
  });

  group('reconnect() — manual force-restart', () {
    test('closes existing socket and re-establishes (server sees 2 upgrades)',
        () async {
      final serverSockets = <WebSocket>[];
      final upgradeCount = StreamController<int>.broadcast();
      addTearDown(upgradeCount.close);
      var count = 0;
      final server = await _startLoopbackWsServer((ws) {
        serverSockets.add(ws);
        count++;
        upgradeCount.add(count);
      });
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final url = _wsUrl(server);
      await svc.connect(url: url).timeout(const Duration(seconds: 3));
      expect(svc.isConnected, isTrue);
      expect(serverSockets, hasLength(1));

      // Watch for the connect=true after the force-restart cycle.
      final statusEvents = <bool>[];
      final statusSub = svc.connectionStatus.listen(statusEvents.add);
      addTearDown(statusSub.cancel);

      final secondUpgrade = upgradeCount
          .stream
          .firstWhere((n) => n >= 2)
          .timeout(const Duration(seconds: 3));

      await svc.reconnect(url: url).timeout(const Duration(seconds: 3));
      await secondUpgrade;

      expect(svc.isConnected, isTrue);
      expect(serverSockets, hasLength(2));

      // statusEvents starts with the yielded current value, then changes.
      // Once seen: [true (initial), false (reconnect tears down), true (new conn)].
      // We don't pin order strictly — just verify both transitions are present.
      expect(statusEvents.where((e) => e == false), isNotEmpty,
          reason: 'reconnect() must surface a false transition');
      expect(statusEvents.last, isTrue,
          reason: 'after reconnect() completes we should be connected');
    });
  });

  group('setDeviceName when connected', () {
    test('changing the name pushes a fresh client_info frame', () async {
      final framesPerSocket = <List<String>>[];
      final server = await _startLoopbackWsServer((ws) {
        final frames = <String>[];
        framesPerSocket.add(frames);
        ws.listen((data) {
          if (data is String) frames.add(data);
        });
      });
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      await svc.connect(url: _wsUrl(server))
          .timeout(const Duration(seconds: 3));

      // Wait for the initial handshake to land server-side.
      final waitStart = DateTime.now();
      while (framesPerSocket.isEmpty || framesPerSocket.first.isEmpty) {
        if (DateTime.now().difference(waitStart).inSeconds > 3) {
          fail('Initial client_info never reached the server');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final initialCount = framesPerSocket.first.length;

      // ASCII-only label — should survive sanitization untouched.
      const newName = 'Studio-Mac-2';
      svc.setDeviceName(newName);

      // Poll briefly for the new frame.
      final pollStart = DateTime.now();
      while (framesPerSocket.first.length <= initialCount) {
        if (DateTime.now().difference(pollStart).inSeconds > 3) {
          fail('setDeviceName did not push a new frame');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final newFrame = framesPerSocket.first.last;
      final decoded = jsonDecode(newFrame) as Map<String, dynamic>;
      expect(decoded['type'], 'client_info');
      final expected = sanitizeDeviceName(newName, currentPlatformName());
      expect(decoded['deviceName'], expected);
    });

    test('setting the same name twice does not re-send', () async {
      final framesPerSocket = <List<String>>[];
      final server = await _startLoopbackWsServer((ws) {
        final frames = <String>[];
        framesPerSocket.add(frames);
        ws.listen((data) {
          if (data is String) frames.add(data);
        });
      });
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      await svc.connect(url: _wsUrl(server))
          .timeout(const Duration(seconds: 3));

      // Wait for initial handshake.
      final waitStart = DateTime.now();
      while (framesPerSocket.isEmpty || framesPerSocket.first.isEmpty) {
        if (DateTime.now().difference(waitStart).inSeconds > 3) {
          fail('Initial client_info never reached the server');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // First setDeviceName('Foo') → expect a new frame.
      const label = 'Foo';
      final before = framesPerSocket.first.length;
      svc.setDeviceName(label);

      final pollStart = DateTime.now();
      while (framesPerSocket.first.length <= before) {
        if (DateTime.now().difference(pollStart).inSeconds > 3) {
          fail('First setDeviceName did not push a new frame');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final afterFirst = framesPerSocket.first.length;

      // Second call with the SAME value — must be a no-op on the wire.
      svc.setDeviceName(label);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(framesPerSocket.first.length, afterFirst,
          reason: 'identical setDeviceName must not re-send client_info');
    });
  });

  group('dispose during in-flight connect', () {
    test('dispose() while connect() is awaiting completes without throwing',
        () async {
      final server = await _startLoopbackWsServer((_) {});
      addTearDown(() async => server.close(force: true));

      final svc = AgentWsService();

      final url = _wsUrl(server);
      // Fire-and-forget the connect — do NOT await it.
      final connectFuture = svc.connect(url: url);
      // Immediately dispose. The service must guard the post-await window.
      final disposeFuture = svc.dispose();

      // Both should settle cleanly — no "Bad state: ..." exceptions.
      await Future.wait<void>([connectFuture, disposeFuture])
          .timeout(const Duration(seconds: 5));

      expect(svc.isConnected, isFalse);
    });
  });
}
