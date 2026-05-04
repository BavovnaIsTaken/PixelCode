import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/work_log_entry.dart';

void main() {
  group('WorkLogEntry', () {
    test('stores the constructor fields verbatim', () {
      final startedAt = DateTime.utc(2026, 5, 1, 12, 30);
      final entry = WorkLogEntry(
        agentId: 'agent_andriy',
        startedAt: startedAt,
        durationSeconds: 1200,
      );

      expect(entry.agentId, 'agent_andriy');
      expect(entry.startedAt, startedAt);
      expect(entry.durationSeconds, 1200);
    });

    test('treats two entries with identical fields as distinct instances', () {
      final startedAt = DateTime.utc(2026, 5, 1);
      final a = WorkLogEntry(
        agentId: 'a',
        startedAt: startedAt,
        durationSeconds: 60,
      );
      final b = WorkLogEntry(
        agentId: 'a',
        startedAt: startedAt,
        durationSeconds: 60,
      );

      expect(identical(a, b), isFalse);
      expect(a.agentId, b.agentId);
      expect(a.startedAt, b.startedAt);
      expect(a.durationSeconds, b.durationSeconds);
    });

    test('zero duration is allowed (interrupted session)', () {
      final entry = WorkLogEntry(
        agentId: 'x',
        startedAt: DateTime(2026),
        durationSeconds: 0,
      );
      expect(entry.durationSeconds, 0);
    });
  });
}
