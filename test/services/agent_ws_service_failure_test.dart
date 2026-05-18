/// Failure-path tests for `AgentWsService` that exercise the FAIL / TMOUT
/// branches of `connect()`, the post-failure WAIT badge from
/// `_scheduleReconnect`, dispose-cancels-reconnect, and connect-after-dispose
/// no-op guard.
///
/// These tests point the service at unreachable / nonsensical URLs — no
/// working WebSocket server is required. Sibling files cover the happy path
/// and the reconnect race separately; this file stays strictly on the
/// failure branches in `lib/services/agent_ws_service.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

void main() {
  group('connect failure → FAIL phase', () {
    test('invalid URL fails fast and emits FAIL phase', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final failFuture = svc.phaseStatus
          .firstWhere((p) => p == 'FAIL' || p == 'TMOUT')
          .timeout(const Duration(seconds: 5));

      // Fire-and-forget — connect() handles its own errors internally.
      unawaited(svc.connect(
        url: 'ws://not-a-real-host-12345.invalid:99/',
      ));

      final phase = await failFuture;
      expect(phase, anyOf('FAIL', 'TMOUT'));
      expect(svc.isConnected, isFalse);
    });

    test('connecting to a closed port → FAIL (or TMOUT) with log line',
        () async {
      // Bind a TCP server, grab its port, close it immediately. The port is
      // now (almost certainly) unbound — connect attempts get refused.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final logLines = <String>[];
      final sub = svc.connectionLog.listen(logLines.add);
      addTearDown(sub.cancel);

      final failFuture = svc.phaseStatus
          .firstWhere((p) => p == 'FAIL' || p == 'TMOUT')
          .timeout(const Duration(seconds: 5));

      unawaited(svc.connect(url: 'ws://127.0.0.1:$port/'));

      final phase = await failFuture;
      expect(phase, anyOf('FAIL', 'TMOUT'));
      expect(svc.isConnected, isFalse);

      // Allow the matching log line to drain to the controller.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        logLines.any(
          (l) => l.contains('Failed to connect') || l.contains('Timeout'),
        ),
        isTrue,
        reason: 'connection failure must surface in connectionLog',
      );
    });

    test('after FAIL, WAIT badge appears within ~1s', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final phases = <String?>[];
      final sub = svc.phaseStatus.listen(phases.add);
      addTearDown(sub.cancel);

      unawaited(svc.connect(
        url: 'ws://not-a-real-host-12345.invalid:99/',
      ));

      // FAIL/TMOUT lands first, then 700ms later the WAIT badge flips on
      // (per _scheduleReconnect). Cap the wait at ~5s to keep the file fast.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline) &&
          !phases.contains('WAIT')) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(
        phases.any((p) => p == 'FAIL' || p == 'TMOUT'),
        isTrue,
        reason: 'must see the terminal failure phase first',
      );
      expect(
        phases.contains('WAIT'),
        isTrue,
        reason: 'the 700ms-later WAIT branch of _scheduleReconnect must fire',
      );

      // Dispose before the 3s reconnect timer re-fires (see next group).
      await svc.dispose();
    });

    test('a failed connect leaves the service usable (drop log on next send)',
        () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final logLines = <String>[];
      final sub = svc.connectionLog.listen(logLines.add);
      addTearDown(sub.cancel);

      final failFuture = svc.phaseStatus
          .firstWhere((p) => p == 'FAIL' || p == 'TMOUT')
          .timeout(const Duration(seconds: 5));

      unawaited(svc.connect(
        url: 'ws://not-a-real-host-12345.invalid:99/',
      ));
      await failFuture;

      // Send anything — must hit the drop-when-disconnected branch in _send.
      expect(() => svc.sendMessage('x'), returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        logLines.any((l) => l.contains('Message dropped')),
        isTrue,
        reason: 'post-FAIL send must log a drop, not throw',
      );
    });
  });

  group('dispose cancels pending reconnect', () {
    test('dispose() during post-FAIL WAIT window cancels the reconnect timer',
        () async {
      final svc = AgentWsService();
      // No addTearDown — this test disposes explicitly; dispose() is idempotent
      // so a duplicate would be safe anyway, but we keep it tight.

      final logLines = <String>[];
      final sub = svc.connectionLog.listen(logLines.add);

      final failFuture = svc.phaseStatus
          .firstWhere((p) => p == 'FAIL' || p == 'TMOUT')
          .timeout(const Duration(seconds: 5));

      unawaited(svc.connect(
        url: 'ws://not-a-real-host-12345.invalid:99/',
      ));
      await failFuture;

      // The 3s reconnect timer is now armed. Capture the "before dispose"
      // count of `Connecting to` lines, then dispose.
      final connectingBefore =
          logLines.where((l) => l.contains('Connecting to')).length;

      await svc.dispose();
      final disposedAt = DateTime.now();

      // Wait beyond the 3s reconnect window plus a buffer.
      await Future<void>.delayed(const Duration(seconds: 4));

      // Stream is closed by dispose, but anything already buffered in
      // `logLines` is still ours to inspect. Critically, no NEW `Connecting
      // to` line should have arrived between dispose and now.
      final connectingAfter =
          logLines.where((l) => l.contains('Connecting to')).length;
      expect(
        connectingAfter,
        connectingBefore,
        reason: 'dispose() must cancel the armed reconnect Timer',
      );

      // Sanity: subscription is still ours to cancel even after the source
      // controller has closed.
      await sub.cancel();
      expect(
        DateTime.now().difference(disposedAt).inSeconds,
        greaterThanOrEqualTo(3),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  group('connect after dispose', () {
    test('connect() after dispose() is a no-op and does not throw', () async {
      final svc = AgentWsService();
      await svc.dispose();

      // Stream is closed post-dispose, so we can't observe the
      // "disposed, skipping" line via `connectionLog`. The contract we can
      // assert: connect() returns normally, isConnected stays false.
      await expectLater(
        svc.connect(url: 'ws://127.0.0.1:1/'),
        completes,
      );
      expect(svc.isConnected, isFalse);
    });
  });
}
