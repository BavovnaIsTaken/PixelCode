/// Tests for Kimi auth Riverpod provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/kimi_auth_provider.dart';

void main() {
  group('KimiAuthProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('builds with notLinked when no key stored', () async {
      final container = ProviderContainer();

      final status =
          await container.read(kimiAuthProvider.future);

      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('builds with linked state when key exists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-test-key');

      final container = ProviderContainer();

      final status =
          await container.read(kimiAuthProvider.future);

      expect(status.linked, true);
      expect(status.apiKey, 'sk-test-key');
    });
  });

  group('KimiAuthNotifier.saveKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves key and updates provider state', () async {
      final container = ProviderContainer();
      final notifier = container.read(kimiAuthProvider.notifier);

      await notifier.saveKey('sk-new-key');

      final status =
          await container.read(kimiAuthProvider.future);
      expect(status.linked, true);
      expect(status.apiKey, 'sk-new-key');
    });

    test('persists key to SharedPreferences', () async {
      final container = ProviderContainer();
      final notifier = container.read(kimiAuthProvider.notifier);

      await notifier.saveKey('sk-persist-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('kimi_api_key'), 'sk-persist-key');
    });
  });

  group('KimiAuthNotifier.clearKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('clears key and updates provider state', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-test-key');

      final container = ProviderContainer();
      final notifier = container.read(kimiAuthProvider.notifier);

      await notifier.clearKey();

      final status =
          await container.read(kimiAuthProvider.future);
      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('removes key from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-test-key');

      final container = ProviderContainer();
      final notifier = container.read(kimiAuthProvider.notifier);

      await notifier.clearKey();

      expect(prefs.getString('kimi_api_key'), null);
    });
  });

  group('KimiAuthNotifier.refresh', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('reloads state from service', () async {
      final container = ProviderContainer();
      final notifier = container.read(kimiAuthProvider.notifier);

      // Initial state: not linked
      var status = await container.read(kimiAuthProvider.future);
      expect(status.linked, false);

      // Save key via SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-added-key');

      // Refresh and verify provider updates
      await notifier.refresh();
      status = await container.read(kimiAuthProvider.future);
      expect(status.linked, true);
      expect(status.apiKey, 'sk-added-key');
    });
  });
}
