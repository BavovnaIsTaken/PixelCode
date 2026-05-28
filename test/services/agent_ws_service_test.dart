/// Lifecycle tests for `AgentWsService` that don't need a live socket.
///
/// We can exercise: initial state, stream wiring (current value yielded
/// to late subscribers), `log()` formatting + broadcast, `setDeviceName`
/// idempotency, drop-when-disconnected for the `_send` path (via any
/// public sender), and `dispose()` cleanly closing controllers.
///
/// We deliberately do NOT call `connect()` — that requires a real
/// WebSocket. The 11.2% → 12.7% lift this file targets is the "no
/// connection ever opened" surface, which is what the app actually
/// hits on startup before the user picks a server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

void main() {
  group('initial state', () {
    test('isConnected is false before connect()', () {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      expect(svc.isConnected, isFalse);
    });

    test('clientId is 32 lowercase hex chars (stable per instance)', () {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      final a = svc.clientId;
      final b = svc.clientId;
      expect(a, hasLength(32));
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, b, reason: 'clientId must be cached, not re-rolled');
    });

    test('buffered ServerMessages start null', () {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      expect(svc.lastServerInfo, isNull);
      expect(svc.lastChatHistory, isNull);
      expect(svc.lastFacilitatorOutputSync, isNull);
    });
  });

  group('stream initial values', () {
    test('connectionStatus yields current (false) before any change', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      final first = await svc.connectionStatus.first;
      expect(first, isFalse);
    });

    test('phaseStatus yields current (null) before any change', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      final first = await svc.phaseStatus.first;
      expect(first, isNull);
    });
  });

  group('log() ', () {
    test('positive: emits a formatted line on the connectionLog stream',
        () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final future = svc.connectionLog.first;
      svc.log('hello');

      final line = await future.timeout(const Duration(seconds: 1));
      // Format: "[HH:MM:SS] hello"
      expect(line, matches(RegExp(r'^\[\d{2}:\d{2}:\d{2}\] hello$')));
    });

    test('positive: multiple subscribers all receive the line (broadcast)',
        () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final a = svc.connectionLog.first;
      final b = svc.connectionLog.first;
      svc.log('ping');
      expect(await a, endsWith('ping'));
      expect(await b, endsWith('ping'));
    });
  });

  group('send-when-disconnected', () {
    test('non-ephemeral message is queued (not thrown) and logged', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      // sendMessage is non-ephemeral → goes to the outbox.
      final queued = svc.connectionLog
          .firstWhere((l) => l.contains('send_message'))
          .timeout(const Duration(seconds: 1));

      svc.sendMessage('payload');

      final line = await queued;
      expect(line, contains('Outbox queued'),
          reason: 'non-ephemeral messages are queued, not dropped');
      expect(line, contains('send_message'));
    });

    test('ephemeral and non-ephemeral sends each emit a log line', () async {
      final svc = AgentWsService();
      addTearDown(svc.dispose);

      final logs = <String>[];
      final sub = svc.connectionLog.listen(logs.add);
      addTearDown(sub.cancel);

      // new_chat → queued (non-ephemeral)
      // interrupt / get_status → dropped (ephemeral)
      svc.newChat();
      svc.interrupt();
      svc.getStatus();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(logs.any((l) => l.contains('new_chat')), isTrue);
      expect(logs.any((l) => l.contains('interrupt')), isTrue);
      expect(logs.any((l) => l.contains('get_status')), isTrue);
      // Verify the right policy applied to each
      expect(logs.any((l) => l.contains('Outbox queued') && l.contains('new_chat')), isTrue);
      expect(logs.any((l) => l.contains('Ephemeral dropped') && l.contains('interrupt')), isTrue);
    });
  });

  group('setDeviceName', () {
    test('positive: accepts a new value without throwing when offline', () {
      final svc = AgentWsService();
      addTearDown(svc.dispose);
      // Won't trigger _sendClientInfo because !_isConnected — pure no-op
      // on the wire. The point of this test: doesn't crash, doesn't
      // double-buffer, doesn't open a stream.
      svc.setDeviceName('Studio-Mac');
      svc.setDeviceName('Studio-Mac'); // same value — idempotent
      svc.setDeviceName('Different-Name');
      // No assertion needed beyond "didn't throw".
    });
  });

  group('dispose()', () {
    test('is idempotent — calling twice does not throw', () async {
      final svc = AgentWsService();
      await svc.dispose();
      await svc.dispose();
    });

    test('after dispose, log() is a no-op (no "add after close" crash)',
        () async {
      final svc = AgentWsService();
      await svc.dispose();
      // The internal isClosed guard must prevent the exception.
      svc.log('after-dispose');
    });
  });
}
