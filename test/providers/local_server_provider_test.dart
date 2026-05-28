/// Tests for LocalServerProvider — config persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/local_server_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

ProviderContainer _makeContainer(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('LocalServerNotifier initial state', () {
    test('defaults to empty config when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      final config = container.read(localServerProvider);
      expect(config.apiKey, null);
      expect(config.hasApiKey, false);
      expect(config.autoStart, false);
    });

    test('restores persisted config on build', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setApiKey('test-key');
      await container.read(localServerProvider.notifier).setAutoStart(true);
      container.dispose();

      // Second container reads from the same prefs
      final container2 = _makeContainer(prefs);
      addTearDown(container2.dispose);

      final config = container2.read(localServerProvider);
      expect(config.apiKey, 'test-key');
      expect(config.autoStart, true);
    });
  });

  group('LocalServerNotifier.setApiKey', () {
    test('sets and persists a non-empty key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setApiKey('my-key');

      expect(container.read(localServerProvider).apiKey, 'my-key');
      expect(container.read(localServerProvider).hasApiKey, true);
    });

    test('treats whitespace-only key as null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setApiKey('   ');

      expect(container.read(localServerProvider).apiKey, null);
      expect(container.read(localServerProvider).hasApiKey, false);
    });

    test('clears key when null is passed', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setApiKey('key');
      await container.read(localServerProvider.notifier).setApiKey(null);

      expect(container.read(localServerProvider).apiKey, null);
    });
  });

  group('LocalServerNotifier.setAutoStart', () {
    test('toggles autoStart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setAutoStart(true);
      expect(container.read(localServerProvider).autoStart, true);

      await container.read(localServerProvider.notifier).setAutoStart(false);
      expect(container.read(localServerProvider).autoStart, false);
    });
  });

  group('LocalServerNotifier.migrateApiKey', () {
    test('sets key if none exists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).migrateApiKey('migrated-key');

      expect(container.read(localServerProvider).apiKey, 'migrated-key');
      expect(container.read(localServerProvider).autoStart, true);
    });

    test('does nothing if a key already exists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      await container.read(localServerProvider.notifier).setApiKey('existing-key');
      await container.read(localServerProvider.notifier).migrateApiKey('new-key');

      expect(container.read(localServerProvider).apiKey, 'existing-key');
    });
  });
}
