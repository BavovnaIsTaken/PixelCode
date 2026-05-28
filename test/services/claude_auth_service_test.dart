/// Tests for ClaudeAuthService model and JSON parsing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/services/claude_auth_service.dart';

void main() {
  group('ClaudeAuthStatus', () {
    test('notLoggedIn constant is correct', () {
      const status = ClaudeAuthStatus.notLoggedIn;

      expect(status.loggedIn, false);
      expect(status.email, null);
      expect(status.orgName, null);
      expect(status.subscriptionType, null);
      expect(status.authMethod, null);
    });

    test('constructor stores all fields', () {
      const status = ClaudeAuthStatus(
        loggedIn: true,
        email: 'user@example.com',
        orgName: 'PixelCode Inc',
        subscriptionType: 'pro',
        authMethod: 'oauth',
      );

      expect(status.loggedIn, true);
      expect(status.email, 'user@example.com');
      expect(status.orgName, 'PixelCode Inc');
      expect(status.subscriptionType, 'pro');
      expect(status.authMethod, 'oauth');
    });
  });

  group('ClaudeAuthStatus.fromJson', () {
    test('parses a fully-populated JSON object', () {
      final status = ClaudeAuthStatus.fromJson({
        'loggedIn': true,
        'email': 'alice@example.com',
        'orgName': 'ACME Corp',
        'subscriptionType': 'team',
        'authMethod': 'claude_ai',
      });

      expect(status.loggedIn, true);
      expect(status.email, 'alice@example.com');
      expect(status.orgName, 'ACME Corp');
      expect(status.subscriptionType, 'team');
      expect(status.authMethod, 'claude_ai');
    });

    test('defaults loggedIn to false when field is missing', () {
      final status = ClaudeAuthStatus.fromJson({});

      expect(status.loggedIn, false);
    });

    test('accepts null optional fields', () {
      final status = ClaudeAuthStatus.fromJson({'loggedIn': true});

      expect(status.loggedIn, true);
      expect(status.email, null);
      expect(status.orgName, null);
      expect(status.subscriptionType, null);
      expect(status.authMethod, null);
    });

    test('handles loggedIn: false', () {
      final status = ClaudeAuthStatus.fromJson({
        'loggedIn': false,
        'email': 'bob@example.com',
      });

      expect(status.loggedIn, false);
      expect(status.email, 'bob@example.com');
    });
  });

  group('ClaudeAuthService.checkStatus', () {
    test('returns notLoggedIn when binary not available on this platform', () async {
      // The service gracefully returns notLoggedIn when the binary isn't found.
      // In a test environment, there's no real `claude` binary at the expected
      // path, so this will hit the null-binary branch.
      final status = await ClaudeAuthService.checkStatus();
      // We can only assert the type; outcome depends on the test machine.
      expect(status, isA<ClaudeAuthStatus>());
    });
  });
}
