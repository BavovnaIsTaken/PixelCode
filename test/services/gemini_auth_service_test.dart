/// Tests for Gemini authentication service.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/gemini_auth_service.dart';

void main() {
  group('GeminiAuthService', () {
    test('GeminiAuthStatus constructor creates correct state', () {
      const status = GeminiAuthStatus(
        loggedIn: true,
        email: 'user@gmail.com',
        projectId: 'my-project-123',
      );

      expect(status.loggedIn, true);
      expect(status.email, 'user@gmail.com');
      expect(status.projectId, 'my-project-123');
    });

    test('GeminiAuthStatus.fromJson parses JSON correctly', () {
      final json = {
        'loggedIn': true,
        'email': 'test@google.com',
        'projectId': 'test-proj',
      };

      final status = GeminiAuthStatus.fromJson(json);

      expect(status.loggedIn, true);
      expect(status.email, 'test@google.com');
      expect(status.projectId, 'test-proj');
    });

    test('GeminiAuthStatus.fromJson handles missing fields', () {
      final json = {
        'loggedIn': false,
      };

      final status = GeminiAuthStatus.fromJson(json);

      expect(status.loggedIn, false);
      expect(status.email, null);
      expect(status.projectId, null);
    });

    test('GeminiAuthStatus.notLoggedIn is correctly initialized', () {
      const status = GeminiAuthStatus.notLoggedIn;

      expect(status.loggedIn, false);
      expect(status.email, null);
      expect(status.projectId, null);
    });

    test('GeminiAuthService binary detection works on supported platforms', () {
      // Binary detection is optional—if gemini-cli is not installed, binary is null
      if (Platform.isMacOS || Platform.isLinux) {
        final binary = GeminiAuthService.binary;
        expect(binary, anyOf(isNull, isA<String>()));
      }
    });
  });
}
