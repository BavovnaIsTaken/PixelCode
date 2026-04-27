/// Tests for Kimi authentication service.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/services/kimi_auth_service.dart';

void main() {
  group('KimiAuthStatus', () {
    test('linked=true with key and masked key', () {
      const status = KimiAuthStatus(
        linked: true,
        apiKey: 'sk-abc123',
        maskedKey: 'sk••••23',
      );

      expect(status.linked, true);
      expect(status.apiKey, 'sk-abc123');
      expect(status.maskedKey, 'sk••••23');
    });

    test('notLinked is correctly initialized', () {
      const status = KimiAuthStatus.notLinked;

      expect(status.linked, false);
      expect(status.apiKey, null);
      expect(status.maskedKey, null);
    });
  });

  group('KimiAuthService.checkStatus', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns notLinked when no key stored', () async {
      final status = await KimiAuthService.checkStatus();
      expect(status.linked, false);
      expect(status.apiKey, null);
    });

    test('returns linked=true when key exists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-test-key');

      final status = await KimiAuthService.checkStatus();
      expect(status.linked, true);
      expect(status.apiKey, 'sk-test-key');
    });

    test('returns masked key when key exists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-0123456789');

      final status = await KimiAuthService.checkStatus();
      expect(status.maskedKey, 'sk-0••••6789');
    });

    test('returns notLinked when key is empty string', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', '');

      final status = await KimiAuthService.checkStatus();
      expect(status.linked, false);
    });
  });

  group('KimiAuthService.saveKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves key to SharedPreferences', () async {
      await KimiAuthService.saveKey('sk-my-key');

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('kimi_api_key');
      expect(saved, 'sk-my-key');
    });

    test('trims whitespace from key', () async {
      await KimiAuthService.saveKey('  sk-my-key  ');

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('kimi_api_key');
      expect(saved, 'sk-my-key');
    });
  });

  group('KimiAuthService.clearKey', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('removes key from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-test-key');
      expect(prefs.getString('kimi_api_key'), 'sk-test-key');

      await KimiAuthService.clearKey();

      expect(prefs.getString('kimi_api_key'), null);
    });

    test('succeeds even if key was not set', () async {
      // Should not throw.
      await KimiAuthService.clearKey();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('kimi_api_key'), null);
    });
  });

  group('Key masking', () {
    test('masks keys shorter than 8 chars as all dots', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'short');

      final status = await KimiAuthService.checkStatus();
      expect(status.maskedKey, '••••••••');
    });

    test('masks keys exactly 8 chars as all dots', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', '12345678');

      final status = await KimiAuthService.checkStatus();
      expect(status.maskedKey, '••••••••');
    });

    test('shows first 4 and last 4 for longer keys', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'sk-0123456789abc');

      final status = await KimiAuthService.checkStatus();
      expect(status.maskedKey, 'sk-0••••9abc');
    });

    test('shows first 4 and last 4 for minimum maskable length (9 chars)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kimi_api_key', 'abcdefghi');

      final status = await KimiAuthService.checkStatus();
      expect(status.maskedKey, 'abcd••••fghi');
    });
  });
}
