/// Tests for `DebugLogNotifier.addLocal` — the client-side hook that lets
/// non-server domains (e.g. `ChatNotifier`) push diagnostics into the
/// in-app DebugConsole. Without this surface, the only way to see chat-
/// domain events was to attach a terminal to `flutter run`; users
/// reporting bugs from a packaged build could not include them.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<String>.broadcast();

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<String> get connectionLog => _connCtrl.stream;

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

void main() {
  group('DebugLogNotifier.addLocal', () {
    late _FakeWsService ws;
    late ProviderContainer container;

    setUp(() {
      ws = _FakeWsService();
      container = ProviderContainer(
        overrides: [wsServiceProvider.overrideWithValue(ws)],
      );
      // Force notifier build so the addLocal call has somewhere to write.
      container.read(debugLogProvider);
    });

    tearDown(() async {
      container.dispose();
      await ws.dispose();
    });

    test('appends a DebugLogMessage with the given category and message', () {
      container
          .read(debugLogProvider.notifier)
          .addLocal('chat', 'send → manager#1 localId=abc');

      final logs = container.read(debugLogProvider);
      expect(logs.length, 1);
      expect(logs.single.category, 'chat');
      expect(logs.single.message, 'send → manager#1 localId=abc');
      expect(logs.single.level, 'info', reason: 'info is the default level');
    });

    test('honours explicit level (warn / error)', () {
      final notifier = container.read(debugLogProvider.notifier);
      notifier.addLocal('chat', 'snapshot mismatch', level: 'warn');
      notifier.addLocal('chat', 'server error', level: 'error');

      final logs = container.read(debugLogProvider);
      expect(logs.map((l) => l.level).toList(), ['warn', 'error']);
    });

    test('preserves chronological order across mixed sources', () async {
      // Interleave a server-pushed log and a local addLocal — both end up in
      // the same state, in append order.
      final serverLog = DebugLogMessage(
        timestamp: DateTime.utc(2026, 5, 16, 12, 0, 0),
        level: 'info',
        category: 'sdk',
        message: 'server hello',
      );
      ws._msgCtrl.add(serverLog);
      await Future<void>.delayed(Duration.zero);

      container.read(debugLogProvider.notifier).addLocal('chat', 'local hello');

      final logs = container.read(debugLogProvider);
      expect(logs.map((l) => l.message).toList(),
          ['server hello', 'local hello']);
      expect(logs.map((l) => l.category).toList(), ['sdk', 'chat']);
    });

    test('clear() wipes both server-pushed and addLocal entries', () {
      final notifier = container.read(debugLogProvider.notifier);
      notifier.addLocal('chat', 'one');
      notifier.addLocal('chat', 'two');
      expect(container.read(debugLogProvider).length, 2);

      notifier.clear();
      expect(container.read(debugLogProvider), isEmpty);
    });
  });
}
