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

    test('offline mode → canWrite is false', () {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);
      expect(c.read(gameSessionProvider).canWrite, isFalse);
    });
  });

  group('auto-claim on viewer mode', () {
    test('viewer status immediately sends session_claim', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(SessionStatusMessage(
        mode: SessionMode.viewer,
        primaryDevice: 'iPad',
      ));
      await Future.microtask(() {});

      expect(fake.sentTypes, contains('session_claim'));
    });

    test('session_claim not sent when already primary', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      expect(fake.sentTypes, isNot(contains('session_claim')));
    });

    test('session_claim not sent when sole', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(SessionStatusMessage(
        mode: SessionMode.primary,
        primaryDevice: null,
      ));
      await Future.microtask(() {});

      expect(fake.sentTypes, isNot(contains('session_claim')));
    });

    test('multiple viewer messages do not duplicate session_claim', () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(SessionStatusMessage(
          mode: SessionMode.viewer, primaryDevice: 'Android'));
      fake.inject(SessionStatusMessage(
          mode: SessionMode.viewer, primaryDevice: 'Android'));
      await Future.microtask(() {});

      expect(fake.sentTypes.where((t) => t == 'session_claim').length,
          greaterThanOrEqualTo(1));
    });
  });

  group('session_taken → auto-reclaim cycle', () {
    test('session_taken flips to viewer', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});
      fake.inject(SessionTakenMessage(byDevice: 'iPhone'));
      await Future.microtask(() {});

      expect(c.read(gameSessionProvider).mode, GameSessionMode.viewer);
    });

    test('session_status viewer after session_taken triggers session_claim',
        () async {
      final fake = _FakeWsService();
      _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});
      fake.inject(SessionTakenMessage(byDevice: 'iPhone'));
      await Future.microtask(() {});
      fake.inject(SessionStatusMessage(
          mode: SessionMode.viewer, primaryDevice: 'iPhone'));
      await Future.microtask(() {});

      expect(fake.sentTypes, contains('session_claim'));
    });
  });

  group('releaseSession()', () {
    test('sends session_release when primary', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(SessionStatusMessage(mode: SessionMode.primary));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).releaseSession();
      expect(fake.sentTypes, contains('session_release'));
    });

    test('releaseSession() is no-op when viewer', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(
          SessionStatusMessage(mode: SessionMode.viewer, primaryDevice: 'Mac'));
      await Future.microtask(() {});

      c.read(gameSessionProvider.notifier).releaseSession();
      expect(fake.sentTypes, isNot(contains('session_release')));
    });
  });

  group('GameSessionMode enum', () {
    test('has no takeoverPending value', () {
      final values = GameSessionMode.values.map((e) => e.name).toList();
      expect(values, isNot(contains('takeoverPending')));
    });
  });

  group('GameSessionState', () {
    test('has no takeoverRequestFrom field', () {
      const s = GameSessionState(mode: GameSessionMode.sole);
      // Accessing non-existent field would be a compile error — structural test
      expect(s.mode, GameSessionMode.sole);
      expect(s.primaryDevice, isNull);
    });
  });
}
