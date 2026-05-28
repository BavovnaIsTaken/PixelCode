/// Unit tests for the pure helpers extracted from `AgentWsService`.
///
/// These cover the parts of the connection lifecycle that don't talk to
/// `dart:io` — DoH response parsing, the Tailscale host predicate, the
/// client-id format, and the in-app log line format. The I/O paths
/// (`WebSocket.connect`, `InternetAddress.lookup`, `HttpClient`) stay
/// uncovered by design; those need a fake-socket harness, not unit tests.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_helpers.dart';

void main() {
  group('needsDohRoute', () {
    test('positive: *.ts.net hostnames route through DoH', () {
      expect(needsDohRoute('mac-mini.tail1234.ts.net'), isTrue);
      expect(needsDohRoute('a.b.c.ts.net'), isTrue);
    });

    test('negative: regular hostnames skip DoH', () {
      expect(needsDohRoute('example.com'), isFalse);
      expect(needsDohRoute('localhost'), isFalse);
      expect(needsDohRoute('192.168.1.10'), isFalse);
      expect(needsDohRoute(''), isFalse);
    });

    test('boundary: substring match in middle does not trigger', () {
      // ".ts.net" must be the suffix, not appear earlier.
      expect(needsDohRoute('host.ts.net.example.com'), isFalse);
    });
  });

  group('parseDohAnswer', () {
    test('positive: returns first A-record IP from Answer list', () {
      const body = '''
        { "Status": 0, "Answer": [
            { "name": "host.ts.net", "type": 1, "TTL": 60, "data": "100.64.0.1" },
            { "name": "host.ts.net", "type": 1, "TTL": 60, "data": "100.64.0.2" }
        ] }
      ''';
      expect(parseDohAnswer(body), '100.64.0.1');
    });

    test('negative: missing Answer section returns null', () {
      expect(parseDohAnswer('{"Status": 3}'), isNull);
    });

    test('negative: empty Answer list returns null', () {
      expect(parseDohAnswer('{"Answer": []}'), isNull);
    });

    test('negative: Answer present but entry has no data field returns null',
        () {
      expect(parseDohAnswer('{"Answer": [{"type": 1}]}'), isNull);
    });

    test('negative: data field non-string returns null', () {
      expect(parseDohAnswer('{"Answer": [{"data": 12345}]}'), isNull);
    });

    test('negative: malformed JSON does not throw', () {
      expect(parseDohAnswer('not json at all'), isNull);
      expect(parseDohAnswer(''), isNull);
      expect(parseDohAnswer('{'), isNull);
    });

    test('negative: top-level array (not Map) returns null', () {
      expect(parseDohAnswer('[]'), isNull);
    });

    test('negative: Answer is a non-list value', () {
      expect(parseDohAnswer('{"Answer": "nope"}'), isNull);
    });
  });

  group('generateClientId', () {
    test('always emits 32 lowercase hex characters', () {
      for (var i = 0; i < 20; i++) {
        final id = generateClientId();
        expect(id, hasLength(32));
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
    });

    test('positive: zero-byte stream produces all zeroes (padding works)', () {
      final id = generateClientId(_FixedRandom(0));
      expect(id, '00000000000000000000000000000000');
    });

    test('positive: 0xFF byte stream produces all 0xff (no overflow)', () {
      final id = generateClientId(_FixedRandom(255));
      expect(id, 'ffffffffffffffffffffffffffffffff');
    });

    test('different seeds produce different ids (no global state)', () {
      final a = generateClientId(Random(1));
      final b = generateClientId(Random(2));
      expect(a, isNot(b));
    });

    test('same seed produces same id (deterministic)', () {
      expect(generateClientId(Random(42)), generateClientId(Random(42)));
    });
  });

  group('formatConnectionLogLine', () {
    test('positive: extracts HH:MM:SS from ISO-8601 representation', () {
      final t = DateTime.utc(2026, 5, 17, 13, 7, 42);
      expect(formatConnectionLogLine(t, 'connected'), '[13:07:42] connected');
    });

    test('boundary: midnight renders as 00:00:00', () {
      final t = DateTime.utc(2026, 1, 1, 0, 0, 0);
      expect(formatConnectionLogLine(t, 'tick'), '[00:00:00] tick');
    });

    test('boundary: end-of-day renders as 23:59:59', () {
      final t = DateTime.utc(2026, 1, 1, 23, 59, 59);
      expect(formatConnectionLogLine(t, 'tick'), '[23:59:59] tick');
    });

    test('positive: empty message still produces well-formed line', () {
      final t = DateTime.utc(2026, 5, 17, 1, 2, 3);
      expect(formatConnectionLogLine(t, ''), '[01:02:03] ');
    });

    test('positive: multi-line messages are not split or trimmed', () {
      final t = DateTime.utc(2026, 5, 17, 12, 0, 0);
      expect(
        formatConnectionLogLine(t, 'line1\nline2'),
        '[12:00:00] line1\nline2',
      );
    });
  });
}

/// Random that always emits the same byte — lets us pin down the
/// padding/hex-formatting invariants in `generateClientId` without
/// relying on `Random.secure`.
class _FixedRandom implements Random {
  _FixedRandom(this._value);
  final int _value;

  @override
  int nextInt(int max) => _value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
