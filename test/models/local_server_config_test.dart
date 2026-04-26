import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/local_server_config.dart';

void main() {
  // ─── hasApiKey ────────────────────────────────────────────────────────

  group('hasApiKey', () {
    test('false when apiKey is null', () {
      const config = LocalServerConfig();
      expect(config.hasApiKey, isFalse);
    });

    test('false when apiKey is empty string', () {
      const config = LocalServerConfig(apiKey: '');
      expect(config.hasApiKey, isFalse);
    });

    test('true when apiKey is set', () {
      const config = LocalServerConfig(apiKey: 'sk-ant-abc123');
      expect(config.hasApiKey, isTrue);
    });

    test('true for minimal non-empty key', () {
      const config = LocalServerConfig(apiKey: 'x');
      expect(config.hasApiKey, isTrue);
    });
  });

  // ─── Default values ───────────────────────────────────────────────────

  group('defaults', () {
    test('apiKey defaults to null', () {
      const config = LocalServerConfig();
      expect(config.apiKey, isNull);
    });

    test('port defaults to 9720', () {
      const config = LocalServerConfig();
      expect(config.port, 9720);
    });

    test('autoStart defaults to false', () {
      const config = LocalServerConfig();
      expect(config.autoStart, isFalse);
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────

  group('copyWith', () {
    const base = LocalServerConfig(
      apiKey: 'original-key',
      port: 9720,
      autoStart: false,
    );

    test('preserves unchanged fields', () {
      final copy = base.copyWith(port: 8080);
      expect(copy.apiKey, base.apiKey);
      expect(copy.autoStart, base.autoStart);
    });

    test('changes port', () {
      final copy = base.copyWith(port: 8080);
      expect(copy.port, 8080);
    });

    test('changes autoStart', () {
      final copy = base.copyWith(autoStart: true);
      expect(copy.autoStart, isTrue);
    });

    test('updates apiKey via function', () {
      final copy = base.copyWith(apiKey: () => 'new-key');
      expect(copy.apiKey, 'new-key');
    });

    test('clears apiKey by passing () => null', () {
      final copy = base.copyWith(apiKey: () => null);
      expect(copy.apiKey, isNull);
    });

    test('preserves apiKey when not specified (null function)', () {
      final copy = base.copyWith(port: 5000);
      expect(copy.apiKey, base.apiKey);
    });
  });

  // ─── fromJson / toJson ────────────────────────────────────────────────

  group('fromJson / toJson', () {
    test('round-trip with all fields', () {
      const config = LocalServerConfig(
        apiKey: 'sk-ant-test',
        port: 8080,
        autoStart: true,
      );

      final json = config.toJson();
      final restored = LocalServerConfig.fromJson(json);

      expect(restored.apiKey, config.apiKey);
      expect(restored.port, config.port);
      expect(restored.autoStart, config.autoStart);
    });

    test('toJson omits apiKey when null', () {
      const config = LocalServerConfig(port: 9720);
      final json = config.toJson();
      expect(json.containsKey('apiKey'), isFalse);
    });

    test('fromJson uses default port 9720 when missing', () {
      final json = <String, dynamic>{'autoStart': false};
      final config = LocalServerConfig.fromJson(json);
      expect(config.port, 9720);
    });

    test('fromJson uses default autoStart=false when missing', () {
      final json = <String, dynamic>{'port': 9720};
      final config = LocalServerConfig.fromJson(json);
      expect(config.autoStart, isFalse);
    });

    test('fromJson handles null apiKey', () {
      final json = <String, dynamic>{'port': 9720, 'autoStart': false};
      final config = LocalServerConfig.fromJson(json);
      expect(config.apiKey, isNull);
      expect(config.hasApiKey, isFalse);
    });
  });

  // ─── encode / decode ──────────────────────────────────────────────────

  group('encode / decode', () {
    test('round-trip preserves all fields', () {
      const config = LocalServerConfig(
        apiKey: 'sk-ant-xyz',
        port: 9720,
        autoStart: true,
      );

      final encoded = config.encode();
      final decoded = LocalServerConfig.decode(encoded);

      expect(decoded.apiKey, config.apiKey);
      expect(decoded.port, config.port);
      expect(decoded.autoStart, config.autoStart);
    });

    test('encoded value is valid JSON string', () {
      const config = LocalServerConfig(port: 9720);
      final encoded = config.encode();
      expect(() => LocalServerConfig.decode(encoded), returnsNormally);
    });

    test('empty config round-trips', () {
      const config = LocalServerConfig();
      final decoded = LocalServerConfig.decode(config.encode());
      expect(decoded.apiKey, isNull);
      expect(decoded.port, 9720);
      expect(decoded.autoStart, isFalse);
    });
  });
}
