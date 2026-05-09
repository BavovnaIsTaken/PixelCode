/// Pin the exponential-backoff formula in `AgentWsService.backoffDelay`.
///
/// The reconnect window matters for the offline outbox: messages queued in
/// `WsOutbox` survive until the next connect, so a short initial delay (1 s)
/// keeps the happy path snappy while the cap (30 s) prevents hammering a
/// downed server. Jitter (±20 %) desynchronises simultaneous reconnects from
/// multiple devices.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

void main() {
  Duration delay(int attempt, double jitter) =>
      AgentWsService.backoffDelay(attempt, jitter);

  group('AgentWsService.backoffDelay', () {
    test('attempt 0 → ~1 s base (0.8–1.2 s with full jitter range)', () {
      expect(delay(0, 0.0).inMilliseconds, 800);   // min jitter
      expect(delay(0, 1.0).inMilliseconds, 1200);  // max jitter
    });

    test('attempt 1 → ~2 s base', () {
      expect(delay(1, 0.0).inMilliseconds, 1600);
      expect(delay(1, 1.0).inMilliseconds, 2400);
    });

    test('attempt 2 → ~4 s base', () {
      expect(delay(2, 0.0).inMilliseconds, 3200);
      expect(delay(2, 1.0).inMilliseconds, 4800);
    });

    test('attempt 4 → ~16 s base', () {
      expect(delay(4, 0.0).inMilliseconds, 12800);
      expect(delay(4, 1.0).inMilliseconds, 19200);
    });

    test('caps at 30 s base for attempt ≥ 5', () {
      // 1 << 5 = 32 > 30, so clamps to 30
      expect(delay(5, 0.0).inMilliseconds, 24000);
      expect(delay(5, 1.0).inMilliseconds, 36000);
      // Large attempt still 30 s base
      expect(delay(20, 0.0).inMilliseconds, 24000);
      expect(delay(20, 1.0).inMilliseconds, 36000);
    });

    test('mid-range jitter (0.5) lands inside [min, max]', () {
      final ms = delay(3, 0.5).inMilliseconds; // base = 8 s
      expect(ms, greaterThanOrEqualTo(6400));
      expect(ms, lessThanOrEqualTo(9600));
    });
  });
}
