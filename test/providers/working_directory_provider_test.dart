/// Regression coverage for the iPhone "working directory not picked up" bug.
///
/// Symptom: on mobile cold-start the server's `InitMessage` was dispatched
/// through the WebSocket broadcast controller before any UI consumer of
/// `workingDirectoryProvider` had been built. The notifier subscribed too
/// late and never saw the message, so `workDir` stayed `null` until reconnect.
///
/// Fix: `AgentWsService` buffers the last `InitMessage` and the notifier
/// seeds its state from that buffer on `build()`. These tests lock in both
/// the post-subscribe path (works as before) and the pre-subscribe path
/// (the actual regression).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();

  /// Mirrors what the real listener does: stash the InitMessage on the
  /// service and forward it to subscribers. Tests that want to exercise
  /// the pre-subscribe path call `inject` *before* reading the provider.
  void inject(ServerMessage msg) {
    if (msg is InitMessage) lastInit = msg;
    _msgCtrl.add(msg);
  }

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    return super.dispose();
  }
}

void main() {
  group('WorkingDirectoryNotifier', () {
    late _FakeWsService ws;
    late ProviderContainer container;

    setUp(() {
      ws = _FakeWsService();
      container = ProviderContainer(
        overrides: [wsServiceProvider.overrideWithValue(ws)],
      );
    });

    tearDown(() async {
      container.dispose();
      await ws.dispose();
    });

    test('initial state is null when no init has arrived', () {
      expect(container.read(workingDirectoryProvider), isNull);
    });

    test('updates when InitMessage arrives after subscribe', () async {
      // Subscribe first (build the notifier).
      expect(container.read(workingDirectoryProvider), isNull);

      ws.inject(InitMessage(
        sessionId: 'sess-1',
        agents: const [],
        workingDirectory: '/Users/dev/Projects/MyApp',
      ));

      // Stream delivery is async — yield once so the listener fires.
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(workingDirectoryProvider),
        '/Users/dev/Projects/MyApp',
      );
    });

    test(
      'seeds from buffer when InitMessage arrived BEFORE subscribe (regression)',
      () async {
        // Simulate the iPhone race: InitMessage flows through the service
        // before any UI consumer of the provider exists.
        ws.inject(InitMessage(
          sessionId: 'sess-1',
          agents: const [],
          workingDirectory: '/Users/dev/Projects/MyApp',
        ));

        // First read of the provider — notifier builds *now*. Must still
        // return the buffered value, not null.
        expect(
          container.read(workingDirectoryProvider),
          '/Users/dev/Projects/MyApp',
        );
      },
    );

    test('ignores InitMessage with null workingDirectory', () async {
      // Seed with a real value first so we can prove null doesn't clobber it.
      ws.inject(InitMessage(
        sessionId: 'sess-1',
        agents: const [],
        workingDirectory: '/path/one',
      ));
      expect(container.read(workingDirectoryProvider), '/path/one');

      ws.inject(InitMessage(
        sessionId: 'sess-2',
        agents: const [],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(workingDirectoryProvider), '/path/one');
    });

    test('updates on subsequent InitMessage with new path (project switch)', () async {
      ws.inject(InitMessage(
        sessionId: 'sess-1',
        agents: const [],
        workingDirectory: '/path/one',
      ));
      expect(container.read(workingDirectoryProvider), '/path/one');

      ws.inject(InitMessage(
        sessionId: 'sess-2',
        agents: const [],
        workingDirectory: '/path/two',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(workingDirectoryProvider), '/path/two');
    });
  });
}
