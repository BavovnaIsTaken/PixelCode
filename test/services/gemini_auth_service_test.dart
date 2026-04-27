/// Tests for Gemini authentication service.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/gemini_auth_service.dart';

void main() {
  group('GeminiAuthStatus', () {
    test('constructor creates correct state', () {
      const status = GeminiAuthStatus(
        loggedIn: true,
        email: 'user@gmail.com',
        projectId: 'my-project-123',
      );

      expect(status.loggedIn, true);
      expect(status.email, 'user@gmail.com');
      expect(status.projectId, 'my-project-123');
    });

    test('notLoggedIn is correctly initialized', () {
      const status = GeminiAuthStatus.notLoggedIn;

      expect(status.loggedIn, false);
      expect(status.email, null);
      expect(status.projectId, null);
    });
  });

  group('GeminiAuthService.checkStatus', () {
    late Directory fakeHome;

    setUp(() {
      fakeHome = Directory.systemTemp.createTempSync('gemini_test_');
      GeminiAuthService.geminiHomeOverride = fakeHome.path;
    });

    tearDown(() {
      GeminiAuthService.geminiHomeOverride = null;
      if (fakeHome.existsSync()) fakeHome.deleteSync(recursive: true);
    });

    test('returns notLoggedIn when oauth_creds.json missing', () async {
      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, false);
    });

    test('returns notLoggedIn when oauth_creds.json has no tokens', () async {
      File('${fakeHome.path}/oauth_creds.json').writeAsStringSync('{}');
      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, false);
    });

    test('returns loggedIn with email when refresh_token present', () async {
      File('${fakeHome.path}/oauth_creds.json').writeAsStringSync(jsonEncode({
        'refresh_token': '1//abc',
        'access_token': 'ya29.test',
        'expiry_date': 0, // expired access_token still counts
      }));
      File('${fakeHome.path}/google_accounts.json').writeAsStringSync(jsonEncode({
        'active': 'user@gmail.com',
        'old': <String>[],
      }));

      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, true);
      expect(status.email, 'user@gmail.com');
    });

    test('returns loggedIn even with malformed accounts file', () async {
      File('${fakeHome.path}/oauth_creds.json').writeAsStringSync(jsonEncode({
        'refresh_token': '1//abc',
      }));
      File('${fakeHome.path}/google_accounts.json').writeAsStringSync('not json');

      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, true);
      expect(status.email, null);
    });

    test('extracts projectId from projects.json', () async {
      File('${fakeHome.path}/oauth_creds.json').writeAsStringSync(jsonEncode({
        'refresh_token': '1//abc',
      }));
      File('${fakeHome.path}/projects.json').writeAsStringSync(jsonEncode({
        'projects': {'/some/path': 'pixelcode-proj'},
      }));

      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, true);
      expect(status.projectId, 'pixelcode-proj');
    });

    test('returns notLoggedIn when oauth_creds.json is corrupt', () async {
      File('${fakeHome.path}/oauth_creds.json').writeAsStringSync('not json');
      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, false);
    });
  });

  group('GeminiAuthService.logout', () {
    late Directory fakeHome;

    setUp(() {
      fakeHome = Directory.systemTemp.createTempSync('gemini_logout_');
      GeminiAuthService.geminiHomeOverride = fakeHome.path;
    });

    tearDown(() {
      GeminiAuthService.geminiHomeOverride = null;
      if (fakeHome.existsSync()) fakeHome.deleteSync(recursive: true);
    });

    test('removes oauth_creds.json and google_accounts.json', () async {
      final creds = File('${fakeHome.path}/oauth_creds.json');
      final accounts = File('${fakeHome.path}/google_accounts.json');
      creds.writeAsStringSync('{"refresh_token":"x"}');
      accounts.writeAsStringSync('{"active":"u@g.com"}');

      final ok = await GeminiAuthService.logout();

      expect(ok, true);
      expect(creds.existsSync(), false);
      expect(accounts.existsSync(), false);

      final status = await GeminiAuthService.checkStatus();
      expect(status.loggedIn, false);
    });

    test('returns false when nothing to remove', () async {
      final ok = await GeminiAuthService.logout();
      expect(ok, false);
    });
  });
}
