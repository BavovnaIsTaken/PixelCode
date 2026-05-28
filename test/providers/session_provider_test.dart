/// Tests for SessionProvider — profile CRUD, persistence, active profile switching.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/session_profile.dart';
import 'package:pixelcode/providers/session_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

ProviderContainer _makeContainer(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

SessionProfile _profile({
  String id = 'p1',
  String name = 'Test',
  String host = 'localhost',
  int port = 9720,
}) =>
    SessionProfile(id: id, name: name, host: host, port: port);

void main() {
  group('SessionState', () {
    test('activeProfile returns null when no active id set', () {
      const state = SessionState(profiles: [], activeProfileId: null);
      expect(state.activeProfile, null);
    });

    test('activeProfile returns the matching profile', () {
      final p = _profile(id: 'x');
      final state = SessionState(profiles: [p], activeProfileId: 'x');
      expect(state.activeProfile, p);
    });

    test('activeProfile returns null when active id has no match', () {
      final p = _profile(id: 'x');
      final state = SessionState(profiles: [p], activeProfileId: 'missing');
      expect(state.activeProfile, null);
    });
  });

  group('SessionNotifier initial state', () {
    test('empty when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      final state = container.read(sessionProvider);
      expect(state.profiles, isEmpty);
      expect(state.activeProfileId, null);
    });
  });

  group('SessionNotifier.addProfile', () {
    test('adds a profile to the list', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));

      expect(container.read(sessionProvider).profiles, hasLength(1));
      expect(container.read(sessionProvider).profiles.first.id, 'p1');
    });

    test('auto-activates the first added profile', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'first'));

      expect(container.read(sessionProvider).activeProfileId, 'first');
    });

    test('does not change active profile when a second is added', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));
      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p2'));

      expect(container.read(sessionProvider).activeProfileId, 'p1');
      expect(container.read(sessionProvider).profiles, hasLength(2));
    });

    test('persists profile to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1', name: 'Home'));
      container.dispose();

      final container2 = _makeContainer(prefs);
      addTearDown(container2.dispose);
      expect(container2.read(sessionProvider).profiles.first.name, 'Home');
    });
  });

  group('SessionNotifier.updateProfile', () {
    test('replaces the profile with the same id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1', name: 'Old'));
      final updated = _profile(id: 'p1', name: 'New');
      await container.read(sessionProvider.notifier).updateProfile(updated);

      expect(container.read(sessionProvider).profiles.first.name, 'New');
    });
  });

  group('SessionNotifier.deleteProfile', () {
    test('removes the profile from the list', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));
      await container.read(sessionProvider.notifier).deleteProfile('p1');

      expect(container.read(sessionProvider).profiles, isEmpty);
    });

    test('clears active profile when the active one is deleted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));
      expect(container.read(sessionProvider).activeProfileId, 'p1');

      await container.read(sessionProvider.notifier).deleteProfile('p1');

      expect(container.read(sessionProvider).activeProfileId, null);
    });

    test('keeps active profile when a different profile is deleted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));
      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p2'));
      await container.read(sessionProvider.notifier).setActive('p2');

      await container.read(sessionProvider.notifier).deleteProfile('p1');

      expect(container.read(sessionProvider).activeProfileId, 'p2');
    });
  });

  group('SessionNotifier.setActive', () {
    test('changes the active profile', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p1'));
      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'p2'));

      await container.read(sessionProvider.notifier).setActive('p2');

      expect(container.read(sessionProvider).activeProfileId, 'p2');
    });
  });

  group('SessionNotifier.migrateFromLegacy', () {
    test('creates a profile from the legacy settings_server_url', () async {
      SharedPreferences.setMockInitialValues({
        'settings_server_url': 'ws://192.168.1.5:9720',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).migrateFromLegacy();

      final state = container.read(sessionProvider);
      expect(state.profiles, hasLength(1));
      expect(state.profiles.first.host, '192.168.1.5');
      expect(state.profiles.first.port, 9720);
      // Legacy key should be removed
      expect(prefs.getString('settings_server_url'), null);
    });

    test('does nothing when profiles already exist', () async {
      SharedPreferences.setMockInitialValues({
        'settings_server_url': 'ws://192.168.1.5:9720',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).addProfile(_profile(id: 'existing'));
      await container.read(sessionProvider.notifier).migrateFromLegacy();

      // Still just the one manually added profile
      expect(container.read(sessionProvider).profiles, hasLength(1));
      expect(container.read(sessionProvider).profiles.first.id, 'existing');
    });

    test('does nothing when no legacy URL stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).migrateFromLegacy();

      expect(container.read(sessionProvider).profiles, isEmpty);
    });
  });
}
