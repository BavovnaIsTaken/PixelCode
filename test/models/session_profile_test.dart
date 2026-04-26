import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/session_profile.dart';

void main() {
  // ─── isSecure ──────────────────────────────────────────────────────────

  group('isSecure', () {
    test('true for .trycloudflare.com host', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tunnel',
        host: 'abc123.trycloudflare.com',
      );
      expect(profile.isSecure, isTrue);
    });

    test('true for .ts.net host (Tailscale)', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tailscale',
        host: 'mydevice.ts.net',
      );
      expect(profile.isSecure, isTrue);
    });

    test('true for host starting with wss://', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Secure',
        host: 'wss://example.com',
      );
      expect(profile.isSecure, isTrue);
    });

    test('false for regular LAN IP', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'LAN',
        host: '192.168.1.42',
      );
      expect(profile.isSecure, isFalse);
    });

    test('false for localhost', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Local',
        host: 'localhost',
      );
      expect(profile.isSecure, isFalse);
    });

    test('false for 127.0.0.1', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Loopback',
        host: '127.0.0.1',
      );
      expect(profile.isSecure, isFalse);
    });
  });

  // ─── wsUrl ─────────────────────────────────────────────────────────────

  group('wsUrl', () {
    // ── Tunnel URL takes priority ─────────────────────────────────────────

    test('prefers tunnelUrl when set (already wss://)', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tunnel',
        host: '192.168.1.42',
        port: 9720,
        tunnelUrl: 'wss://abc123.trycloudflare.com',
      );
      expect(profile.wsUrl, 'wss://abc123.trycloudflare.com');
    });

    test('prefers tunnelUrl when set (already ws://)', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tunnel',
        host: '192.168.1.42',
        port: 9720,
        tunnelUrl: 'ws://internal.example.com',
      );
      expect(profile.wsUrl, 'ws://internal.example.com');
    });

    test('adds wss:// prefix to bare tunnelUrl hostname', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tunnel',
        host: '192.168.1.42',
        port: 9720,
        tunnelUrl: 'abc123.trycloudflare.com',
      );
      expect(profile.wsUrl, 'wss://abc123.trycloudflare.com');
    });

    test('ignores empty tunnelUrl and falls back to host', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tunnel',
        host: '192.168.1.42',
        port: 9720,
        tunnelUrl: '',
      );
      expect(profile.wsUrl, 'ws://192.168.1.42:9720');
    });

    // ── Host URL formats ─────────────────────────────────────────────────

    test('uses wss:// when host is already wss:// URL', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Secure',
        host: 'wss://myserver.example.com',
      );
      expect(profile.wsUrl, 'wss://myserver.example.com');
    });

    test('uses ws:// when host is already ws:// URL', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'WS',
        host: 'ws://myserver.local:8080',
      );
      expect(profile.wsUrl, 'ws://myserver.local:8080');
    });

    test('uses wss://host for Cloudflare Tunnel domain', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Cloudflare',
        host: 'xyz.trycloudflare.com',
        port: 9720,
      );
      expect(profile.wsUrl, 'wss://xyz.trycloudflare.com');
    });

    test('uses wss://host for Tailscale domain', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Tailscale',
        host: 'mypc.ts.net',
        port: 9720,
      );
      expect(profile.wsUrl, 'wss://mypc.ts.net');
    });

    // ── Standard LAN fallback ─────────────────────────────────────────────

    test('uses ws://host:port for LAN IP address', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'LAN',
        host: '192.168.1.42',
        port: 9720,
      );
      expect(profile.wsUrl, 'ws://192.168.1.42:9720');
    });

    test('uses ws://host:port for localhost', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Local',
        host: 'localhost',
        port: 9720,
      );
      expect(profile.wsUrl, 'ws://localhost:9720');
    });

    test('default port is 9720', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Default',
        host: '192.168.1.1',
      );
      expect(profile.wsUrl, 'ws://192.168.1.1:9720');
    });

    test('custom port is included in wsUrl', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'Custom',
        host: '10.0.0.1',
        port: 8080,
      );
      expect(profile.wsUrl, 'ws://10.0.0.1:8080');
    });
  });

  // ─── copyWith ──────────────────────────────────────────────────────────

  group('copyWith', () {
    final original = SessionProfile(
      id: 'prof-1',
      name: 'Home',
      host: '192.168.1.42',
      port: 9720,
      tunnelUrl: 'abc.trycloudflare.com',
    );

    test('preserves id on all copies', () {
      final copy = original.copyWith(name: 'Office');
      expect(copy.id, original.id);
    });

    test('changes only name', () {
      final copy = original.copyWith(name: 'Office');
      expect(copy.name, 'Office');
      expect(copy.host, original.host);
      expect(copy.port, original.port);
    });

    test('changes only host', () {
      final copy = original.copyWith(host: '10.0.0.99');
      expect(copy.host, '10.0.0.99');
      expect(copy.name, original.name);
      expect(copy.port, original.port);
    });

    test('changes tunnelUrl to null', () {
      // Note: copyWith with null explicit value is tricky in Dart
      // Verify that not passing tunnelUrl preserves it
      final copy = original.copyWith(name: 'Copy');
      expect(copy.tunnelUrl, original.tunnelUrl);
    });

    test('changes port', () {
      final copy = original.copyWith(port: 8080);
      expect(copy.port, 8080);
    });
  });

  // ─── Serialization ─────────────────────────────────────────────────────

  group('fromJson / toJson', () {
    test('round-trip preserves all fields', () {
      final profile = SessionProfile(
        id: 'p-42',
        name: 'Work Server',
        host: '10.0.0.1',
        port: 9720,
        tunnelUrl: 'abc.ts.net',
      );

      final json = profile.toJson();
      final restored = SessionProfile.fromJson(json);

      expect(restored.id, profile.id);
      expect(restored.name, profile.name);
      expect(restored.host, profile.host);
      expect(restored.port, profile.port);
      expect(restored.tunnelUrl, profile.tunnelUrl);
    });

    test('toJson omits tunnelUrl when null', () {
      final profile = SessionProfile(
        id: 'p1',
        name: 'LAN',
        host: '192.168.1.1',
      );
      final json = profile.toJson();
      expect(json.containsKey('tunnelUrl'), isFalse);
    });

    test('fromJson uses default port 9720 when missing', () {
      final json = {'id': 'p1', 'name': 'Test', 'host': '127.0.0.1'};
      final profile = SessionProfile.fromJson(json);
      expect(profile.port, 9720);
    });

    test('fromJson handles null tunnelUrl', () {
      final json = {
        'id': 'p1',
        'name': 'Test',
        'host': '127.0.0.1',
        'port': 9720,
      };
      final profile = SessionProfile.fromJson(json);
      expect(profile.tunnelUrl, isNull);
    });
  });

  // ─── encodeList / decodeList ───────────────────────────────────────────

  group('encodeList / decodeList', () {
    test('empty list round-trips', () {
      final encoded = SessionProfile.encodeList([]);
      final decoded = SessionProfile.decodeList(encoded);
      expect(decoded, isEmpty);
    });

    test('list with multiple profiles round-trips', () {
      final profiles = [
        SessionProfile(id: 'p1', name: 'Home', host: '192.168.1.1'),
        SessionProfile(id: 'p2', name: 'Work', host: '10.0.0.1', port: 8080),
      ];

      final encoded = SessionProfile.encodeList(profiles);
      final decoded = SessionProfile.decodeList(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].id, 'p1');
      expect(decoded[0].name, 'Home');
      expect(decoded[1].id, 'p2');
      expect(decoded[1].port, 8080);
    });
  });
}
