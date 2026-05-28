/// Tests for DeepSeek authentication service.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/services/deepseek_auth_service.dart';

void main() {
  group('DeepSeekAuthStatus', () {
    test('constructor creates correct state', () {
      const status = DeepSeekAuthStatus(
        linked: true,
        apiKey: 'sk-abc123',
        maskedKey: 'sk-a••••123',
      );

      expect(status.linked, true);
      expect(status.apiKey, 'sk-abc123');
      expect(status.maskedKey, 'sk-a••••123');
    });

    test('notLinked is correctly initialized', () {
      const status = DeepSeekAuthStatus.notLinked;

      expect(status.linked, false);
      expect(status.apiKey, null);
      expect(status.maskedKey, null);
    });
  });

  group('DeepSeekAuthService.checkStatus', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns notLinked when no key stored', () async {
      final status = await DeepSeekAuthService.checkStatus();

      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('returns linked with key when key stored', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-test-key');

      final status = await DeepSeekAuthService.checkStatus();

      expect(status.linked, true);
      expect(status.apiKey, 'sk-test-key');
    });

    test('returns notLinked when stored key is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', '');

      final status = await DeepSeekAuthService.checkStatus();

      expect(status.linked, false);
    });

    test('returns masked key for long keys', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-abcdefgh1234');

      final status = await DeepSeekAuthService.checkStatus();

      expect(status.maskedKey, isNotNull);
      expect(status.maskedKey, contains('••••'));
      expect(status.maskedKey!.startsWith('sk-a'), true);
      expect(status.maskedKey!.endsWith('1234'), true);
    });

    test('masks short keys with placeholder', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'short');

      final status = await DeepSeekAuthService.checkStatus();

      expect(status.maskedKey, '••••••••');
    });
  });

  group('DeepSeekAuthService.saveKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves key to SharedPreferences', () async {
      await DeepSeekAuthService.saveKey('sk-new-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('deepseek_api_key'), 'sk-new-key');
    });

    test('trims whitespace when saving', () async {
      await DeepSeekAuthService.saveKey('  sk-trimmed  ');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('deepseek_api_key'), 'sk-trimmed');
    });
  });

  group('DeepSeekAuthService.clearKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('removes key from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deepseek_api_key', 'sk-test-key');

      await DeepSeekAuthService.clearKey();

      expect(prefs.getString('deepseek_api_key'), null);
    });

    test('is safe to call when no key stored', () async {
      await expectLater(DeepSeekAuthService.clearKey(), completes);
    });
  });
}
