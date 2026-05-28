/// Tests for network discovery service — model parsing and metadata fetch logic.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/services/network_discovery_service.dart';

void main() {
  group('ServerMetadata.fromJson', () {
    test('parses a fully-populated object', () {
      final meta = ServerMetadata.fromJson({
        'hostname': 'macbook-pro.local',
        'localIps': ['192.168.1.10', '10.0.0.2'],
        'port': 9720,
        'tunnelUrl': 'https://pixelcode.funnel.example',
      });

      expect(meta.hostname, 'macbook-pro.local');
      expect(meta.localIps, ['192.168.1.10', '10.0.0.2']);
      expect(meta.port, 9720);
      expect(meta.tunnelUrl, 'https://pixelcode.funnel.example');
    });

    test('defaults to empty values when fields are absent', () {
      final meta = ServerMetadata.fromJson({});

      expect(meta.hostname, '');
      expect(meta.localIps, isEmpty);
      expect(meta.port, 9720);
      expect(meta.tunnelUrl, null);
    });

    test('returns null tunnelUrl when field is whitespace-only', () {
      final meta = ServerMetadata.fromJson({
        'hostname': 'host',
        'localIps': <dynamic>[],
        'port': 9720,
        'tunnelUrl': '   ',
      });

      expect(meta.tunnelUrl, null);
    });

    test('returns null tunnelUrl when field is empty string', () {
      final meta = ServerMetadata.fromJson({
        'tunnelUrl': '',
      });

      expect(meta.tunnelUrl, null);
    });

    test('accepts list of IPs with mixed types coerced to string', () {
      final meta = ServerMetadata.fromJson({
        'localIps': ['192.168.0.1', '10.0.0.1'],
      });

      expect(meta.localIps, hasLength(2));
      expect(meta.localIps.first, '192.168.0.1');
    });
  });

  group('DiscoveredServer', () {
    test('equality is based on host and port', () {
      const a = DiscoveredServer(name: 'Alpha', host: '192.168.1.1', port: 9720);
      const b = DiscoveredServer(name: 'Beta', host: '192.168.1.1', port: 9720);
      const c = DiscoveredServer(name: 'Alpha', host: '192.168.1.2', port: 9720);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      const a = DiscoveredServer(name: 'A', host: '10.0.0.1', port: 9720);
      const b = DiscoveredServer(name: 'B', host: '10.0.0.1', port: 9720);

      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes name, host, port', () {
      const s = DiscoveredServer(name: 'MyServer', host: 'host.local', port: 9720);

      expect(s.toString(), contains('MyServer'));
      expect(s.toString(), contains('host.local'));
      expect(s.toString(), contains('9720'));
    });
  });
}
