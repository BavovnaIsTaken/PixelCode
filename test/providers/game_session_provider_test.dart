import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/game_session_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WS service ─────────────────────────────────────────────────────────

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final List<String> sentTypes = [];

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus async* {
    yield true;
  }

  @override
  void claimSession() => sentTypes.add('session_claim');

  @override
  void releaseSession() => sentTypes.add('session_release');

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    return super.dispose();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer(_FakeWsService fake) {
  final c = ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  // Eagerly read so the notifier subscribes to the fake stream.
  c.read(gameSessionProvider);
  return c;
}

void main() {
  group('GameSessionProvider — initial state', () {
    test('starts offline', () {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);
      expect(c.read(gameSessionProvider).mode, GameSessionMode.offline);
    });
  });

  group('session_status → mode mapping', () {
    test('primary with no other device → sole', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      expect(c.read(gameSessionProvider).mode, GameSessionMode.sole);
      expect(c.read(gameSessionProvider).canWrite, isTrue);
    });

    test('primary with primaryDevice set → primary (multi-device)', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(
        mode: SessionMode.primary,
        primaryDevice: 'MacBook',
      ));
      await Future.microtask(() {});

      expect(c.read(gameSessionProvider).mode, GameSessionMode.primary);
      expect(c.read(gameSessionProvider).canWrite, isTrue);
    });

    test('viewer mode → canWrite is false', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(
        mode: SessionMode.viewer,
        primaryDevice: 'iPhone',
      ));
      await Future.microtask(() {});

      final s = c.read(gameSessionProvider);
      expect(s.mode, GameSessionMode.viewer);
      expect(s.primaryDevice, 'iPhone');
      expect(s.canWrite, isFalse);
    });
  });

  group('claimSession()', () {
    test('transitions to takeoverPending and sends session_claim', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      // Put into viewer mode first.
      fake.inject(SessionStatusMessage(
        mode: SessionMode.viewer,
        primaryDevice: 'iPad',
      ));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).claimSession();
      await Future.microtask(() {});

      expect(c.read(gameSessionProvider).mode, GameSessionMode.takeoverPending);
      expect(fake.sentTypes, contains('session_claim'));
    });

    test('claimSession() is no-op when already primary', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).claimSession();
      expect(fake.sentTypes, isNot(contains('session_claim')));
      expect(c.read(gameSessionProvider).mode, GameSessionMode.sole);
    });
  });

  group('session_takeover_request', () {
    test('populates takeoverRequestFrom when primary', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      fake.inject(SessionTakeoverRequestMessage(fromDevice: 'Android'));
      await Future.microtask(() {});

      expect(c.read(gameSessionProvider).takeoverRequestFrom, 'Android');
    });

    test('releaseSession() sends session_release', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).releaseSession();
      expect(fake.sentTypes, contains('session_release'));
    });

    test('dismissTakeoverRequest() clears the request', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});
      fake.inject(SessionTakeoverRequestMessage(fromDevice: 'iPhone'));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).dismissTakeoverRequest();
      expect(c.read(gameSessionProvider).takeoverRequestFrom, isNull);
    });
  });

  group('session_taken', () {
    test('moves to viewer and clears takeover request', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});
      fake.inject(SessionTakeoverRequestMessage(fromDevice: 'iPhone'));
      await Future.microtask(() {});

      fake.inject(SessionTakenMessage(byDevice: 'iPhone'));
      await Future.microtask(() {});

      final s = c.read(gameSessionProvider);
      expect(s.mode, GameSessionMode.viewer);
      expect(s.takeoverRequestFrom, isNull);
    });
  });
}
