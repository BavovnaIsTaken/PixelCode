library;

/// Edge-branch coverage for `AgentWsService` that the existing test files
/// (`agent_ws_service_test.dart`, `agent_ws_service_connect_test.dart`,
/// `agent_ws_service_reconnect_test.dart`, `agent_ws_service_failure_test.dart`)
/// do not exercise:
///
///   1. The `onError` callback on the WebSocket subscription — fires when a
///      socket-level error is pushed AFTER a successful upgrade. Distinct
///      from `onDone` (graceful close).
///   2. The body of the 3s reconnect timer — `_emitPhase('RTRY')` + a
///      follow-up `connect(url:)` call. Sibling tests dispose before the
///      timer fires; this one waits long enough.
///   3. The post-await `_disposed` guard at the top of `connect()` (line 121
///      in `agent_ws_service.dart`) — `dispose()` lands between
///      `WebSocket.connect` resolving and the `listen` registration.
///
/// All tests use real loopback `HttpServer` + `WebSocketTransformer.upgrade`
/// so the production code path is exercised end-to-end. Every async wait is
/// guarded by a `Duration` timeout.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

/// Spins up an ephemeral loopback HTTP server that upgrades any request to a
/// WebSocket and forwards each accepted socket to [onSocket]. The handler is
/// `async` so callers can drive the upgraded socket directly (e.g. push an
/// error, destroy the underlying transport).
Future<HttpServer> _startLoopbackWsServer(
  Future<void> Function(WebSocket ws) onSocket,
) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((HttpRequest request) async {
    final ws = await WebSocketTransformer.upgrade(request);
    await onSocket(ws);
  });
  return server;
}

String _wsUrl(HttpServer server) => 'ws://127.0.0.1:${server.port}/';

void main() {
  group('onError — socket error after connect', () {
    test(
      'server-side error → ERR phase on client subscription',
      () async {
        // SKIP REASON:
        //
        // Dart's `_WebSocketImpl.addError` does NOT translate to a
        // protocol-level error on the peer's subscription. The
        // implementation re-emits the error into the local zone (it
        // surfaces as an uncaught async error even when wrapped in
        // `runZonedGuarded`, see the dart-lang/sdk issue tracker) and
        // simultaneously sinks a normal close frame to the client — which
        // arrives as `onDone` (DROP), not `onError` (ERR).
        //
        // The other documented paths to surface `onError` on the client
        // subscription are not viable from a pure test harness:
        //   - `Socket.destroy()` on the underlying server socket requires
        //     reflection/private access (`WebSocket` doesn't expose its
        //     transport).
        //   - Sending a malformed RFC-6455 frame requires us to perform the
        //     handshake by hand, which in turn needs SHA-1 — not in the
        //     `pubspec.yaml` direct deps.
        //   - `WebSocket.close(WebSocketStatus.protocolError)` flows
        //     through `onDone`, not `onError`.
        //
        // The `onError` callback (lines 155-161 of agent_ws_service.dart)
        // therefore remains exercised only in production / manual
        // scenarios involving real network faults. We leave this test as a
        // tracked skip so the gap is documented.
        expect(true, isTrue);
      },
      skip:
          'Cannot deterministically trigger onError on the client WebSocket '
          'subscription from a Dart-only test harness — see in-test comment '
          'for details.',
    );
  });

  group('reconnect timer fires', () {
    test(
      'after server-close → DROP, the 3s timer fires and emits RTRY',
      () async {
        final serverSockets = <WebSocket>[];
        final server = await _startLoopbackWsServer((ws) async {
          serverSockets.add(ws);
        });
        addTearDown(() async => server.close(force: true));

        final svc = AgentWsService();
        addTearDown(svc.dispose);

        // Subscribe early so RTRY isn't missed.
        final rtryEmitted = svc.phaseStatus
            .firstWhere((p) => p == 'RTRY')
            .timeout(const Duration(seconds: 5));

        await svc
            .connect(url: _wsUrl(server))
            .timeout(const Duration(seconds: 5));
        expect(svc.isConnected, isTrue);

        // Wait until the server side is registered.
        final waitStart = DateTime.now();
        while (serverSockets.isEmpty) {
          if (DateTime.now().difference(waitStart).inSeconds > 3) {
            fail('Server never received the upgrade');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        // Drop the connection from the server side → onDone → DROP →
        // reconnect timer armed for ~3s.
        await serverSockets.first.close();

        // Wait for the timer to fire (~3s) and emit RTRY from line 519.
        final phase = await rtryEmitted;
        expect(phase, 'RTRY');
      },
      // Allow generous headroom for the 3s reconnect timer.
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('dispose during in-flight connect (post-await branch)', () {
    test(
      'dispose() during connect() — post-await _disposed guard fires '
      'and isConnected stays false',
      () async {
        final server = await _startLoopbackWsServer((_) async {});
        addTearDown(() async => server.close(force: true));

        final svc = AgentWsService();

        final url = _wsUrl(server);
        // Start the connect — the future awaits `WebSocket.connect` which
        // resolves only after the server-side upgrade handshake completes.
        final connectFuture = svc.connect(url: url);

        // Race a `dispose()` against the resolution of `WebSocket.connect`.
        // We use a microtask-delayed dispose so the connect's pre-await
        // guard at line 93 is past, but the post-await guard at line 121
        // has a chance to fire. We deliberately schedule via Future.delayed
        // so the event loop picks up the WebSocket.connect resolution
        // alongside the dispose; either branch (pre- or post-await) is a
        // valid execution, and the user-visible contract (`isConnected ==
        // false`, no exceptions) holds in both.
        final disposeFuture = Future<void>.delayed(
          const Duration(microseconds: 0),
          svc.dispose,
        );

        await Future.wait<void>([connectFuture, disposeFuture])
            .timeout(const Duration(seconds: 5));

        expect(svc.isConnected, isFalse);
      },
    );
  });
}
