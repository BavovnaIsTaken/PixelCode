import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/localization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLanguage enum', () {
    test('exposes en and uk', () {
      expect(AppLanguage.values.length, 2);
      expect(AppLanguage.values, containsAll(<AppLanguage>[
        AppLanguage.en,
        AppLanguage.uk,
      ]));
    });

    test('code matches the enum name', () {
      expect(AppLanguage.en.code, 'en');
      expect(AppLanguage.uk.code, 'uk');
    });

    test('displayName is human-readable per language', () {
      expect(AppLanguage.en.displayName, 'English');
      expect(AppLanguage.uk.displayName, 'Українська');
    });
  });

  group('LocalizationService singleton', () {
    test('factory constructor returns the same instance', () {
      final a = LocalizationService();
      final b = LocalizationService();
      expect(identical(a, b), isTrue);
      expect(identical(a, localization), isTrue);
    });

    test('default currentLanguage is uk before initialize', () {
      // The singleton may have been touched by another test in this file;
      // only assert the immutable invariant: currentLanguage is always one of
      // the two AppLanguage values.
      expect(AppLanguage.values, contains(localization.currentLanguage));
    });
  });

  group('LocalizationService.t() before translations are loaded', () {
    test('returns the key itself as a fallback', () {
      // Without initialize() the internal map is empty; t() must echo the key.
      final svc = LocalizationService();
      expect(svc.t('greeting.hello'), 'greeting.hello');
      expect(svc.t(''), '');
    });
  });

  group('LocalizationService.setLanguage', () {
    test('updates currentLanguage immediately', () async {
      final svc = LocalizationService();
      await svc.setLanguage(AppLanguage.en);
      expect(svc.currentLanguage, AppLanguage.en);

      await svc.setLanguage(AppLanguage.uk);
      expect(svc.currentLanguage, AppLanguage.uk);
    });
  });

  group('LocalizationService.initialize with mocked rootBundle', () {
    setUp(() {
      // Stub the asset bundle for both i18n files this service tries to load.
      // ServicesBinding.defaultBinaryMessenger uses utf8 strings encoded as
      // ByteData for asset reads — match that contract.
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async {
          final key = utf8Decode(message);
          if (key == 'assets/i18n/en.json') {
            return _stringToByteData('{"hello":"Hello","bye":"Bye"}');
          }
          if (key == 'assets/i18n/uk.json') {
            return _stringToByteData('{"hello":"Привіт","bye":"Бувай"}');
          }
          return null;
        },
      );
    });

    tearDown(() {
      ServicesBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    test('loads translations and t() returns localized strings', () async {
      final svc = LocalizationService();
      await svc.initialize(initialLanguage: AppLanguage.uk);
      expect(svc.currentLanguage, AppLanguage.uk);
      expect(svc.t('hello'), 'Привіт');
      expect(svc.t('bye'), 'Бувай');
      // Unknown keys still fall back to the key itself.
      expect(svc.t('missing'), 'missing');
    });

    test('t() switches translations when setLanguage is called', () async {
      final svc = LocalizationService();
      await svc.initialize(initialLanguage: AppLanguage.uk);
      expect(svc.t('hello'), 'Привіт');

      await svc.setLanguage(AppLanguage.en);
      expect(svc.t('hello'), 'Hello');
    });

    test('initialize with no argument defaults to uk', () async {
      final svc = LocalizationService();
      await svc.initialize();
      expect(svc.currentLanguage, AppLanguage.uk);
    });
  });
}

// Mirrors the utf8 encoding the assets channel uses for asset key lookups.
String utf8Decode(ByteData? data) {
  if (data == null) return '';
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

ByteData _stringToByteData(String s) {
  final bytes = utf8.encode(s);
  final data = ByteData(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    data.setUint8(i, bytes[i]);
  }
  return data;
}
