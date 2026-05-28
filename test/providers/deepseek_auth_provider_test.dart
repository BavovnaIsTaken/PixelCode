/// Tests for DeepSeek auth Riverpod provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/deepseek_auth_provider.dart';

void main() {
  group('DeepSeekAuthProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('builds with notLinked when no key stored', () async {
      final container = ProviderContainer();

      final status = await container.read(deepseekAuthProvider.future);

      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('builds with linked state when key exists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-test-key');

      final container = ProviderContainer();

      final status = await container.read(deepseekAuthProvider.future);

      expect(status.linked, true);
      expect(status.apiKey, 'sk-test-key');
    });
  });

  group('DeepSeekAuthNotifier.saveKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves key and updates provider state', () async {
      final container = ProviderContainer();
      final notifier = container.read(deepseekAuthProvider.notifier);

      await notifier.saveKey('sk-new-key');

      final status = await container.read(deepseekAuthProvider.future);
      expect(status.linked, true);
      expect(status.apiKey, 'sk-new-key');
    });

    test('persists key to SharedPreferences', () async {
      final container = ProviderContainer();
      final notifier = container.read(deepseekAuthProvider.notifier);

      await notifier.saveKey('sk-persist-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('deepseek_api_key'), 'sk-persist-key');
    });
  });

  group('DeepSeekAuthNotifier.clearKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('clears key and updates provider state', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-test-key');

      final container = ProviderContainer();
      final notifier = container.read(deepseekAuthProvider.notifier);

      await notifier.clearKey();

      final status = await container.read(deepseekAuthProvider.future);
      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('removes key from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-test-key');

      final container = ProviderContainer();
      final notifier = container.read(deepseekAuthProvider.notifier);

      await notifier.clearKey();

      expect(prefs.getString('deepseek_api_key'), null);
    });
  });

  group('DeepSeekAuthNotifier.refresh', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('reloads state from service', () async {
      final container = ProviderContainer();
      final notifier = container.read(deepseekAuthProvider.notifier);

      var status = await container.read(deepseekAuthProvider.future);
      expect(status.linked, false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-added-key');

      await notifier.refresh();
      status = await container.read(deepseekAuthProvider.future);
      expect(status.linked, true);
      expect(status.apiKey, 'sk-added-key');
    });
  });
}
