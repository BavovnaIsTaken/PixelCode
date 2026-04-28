import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/project_memory.dart';

void main() {
  // ─── Helpers ──────────────────────────────────────────────────────────

  ProjectMemoryEntry freshEntry({String summary = 'Fresh memory'}) {
    return ProjectMemoryEntry(
      summary: summary,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    );
  }

  ProjectMemoryEntry recentEntry({String summary = 'Recent memory'}) {
    return ProjectMemoryEntry(
      summary: summary,
      timestamp: DateTime.now().subtract(const Duration(days: 3)),
    );
  }

  ProjectMemoryEntry oldEntry({String summary = 'Old memory'}) {
    return ProjectMemoryEntry(
      summary: summary,
      timestamp: DateTime.now().subtract(const Duration(days: 15)),
    );
  }

  ProjectMemoryEntry ancientEntry({String summary = 'Ancient memory'}) {
    return ProjectMemoryEntry(
      summary: summary,
      timestamp: DateTime.now().subtract(const Duration(days: 35)),
    );
  }

  // ─── MemoryTier ───────────────────────────────────────────────────────

  group('MemoryTier', () {
    test('fresh: entries less than 24 hours old', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now().subtract(const Duration(hours: 12)),
      );
      expect(entry.tier, MemoryTier.fresh);
    });

    test('fresh: entries created just now', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now(),
      );
      expect(entry.tier, MemoryTier.fresh);
    });

    test('recent: entries 1–6 days old', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now().subtract(const Duration(days: 4)),
      );
      expect(entry.tier, MemoryTier.recent);
    });

    test('old: entries 7+ days old', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(entry.tier, MemoryTier.old);
    });

    test('old: entries exactly 7 days old', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now().subtract(const Duration(days: 7)),
      );
      expect(entry.tier, MemoryTier.old);
    });
  });

  // ─── fromJson / toJson ────────────────────────────────────────────────

  group('fromJson / toJson', () {
    test('round-trip preserves summary and timestamp', () {
      final ts = DateTime.parse('2026-01-15T10:00:00.000Z');
      final entry = ProjectMemoryEntry(
        summary: 'Fixed the login bug',
        timestamp: ts,
        sessionId: 'session-42',
      );

      final json = entry.toJson();
      final restored = ProjectMemoryEntry.fromJson(json);

      expect(restored.summary, entry.summary);
      expect(restored.timestamp.toIso8601String(), ts.toIso8601String());
      expect(restored.sessionId, 'session-42');
    });

    test('toJson omits sessionId when null', () {
      final entry = ProjectMemoryEntry(
        summary: 'test',
        timestamp: DateTime.now(),
      );
      final json = entry.toJson();
      expect(json.containsKey('sessionId'), isFalse);
    });

    test('fromJson handles missing sessionId', () {
      final json = {
        'summary': 'test',
        'timestamp': '2026-01-01T00:00:00.000Z',
      };
      final entry = ProjectMemoryEntry.fromJson(json);
      expect(entry.sessionId, isNull);
    });
  });

  // ─── listFromJson / listToJson ────────────────────────────────────────

  group('listFromJson / listToJson', () {
    test('empty list round-trips', () {
      final encoded = ProjectMemoryEntry.listToJson([]);
      final decoded = ProjectMemoryEntry.listFromJson(encoded);
      expect(decoded, isEmpty);
    });

    test('multiple entries round-trip', () {
      final entries = [
        freshEntry(summary: 'Entry 1'),
        recentEntry(summary: 'Entry 2'),
      ];

      final encoded = ProjectMemoryEntry.listToJson(entries);
      final decoded = ProjectMemoryEntry.listFromJson(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].summary, 'Entry 1');
      expect(decoded[1].summary, 'Entry 2');
    });
  });

  // ─── applyDecay ───────────────────────────────────────────────────────

  group('applyDecay', () {
    test('empty list returns empty list', () {
      final result = ProjectMemoryEntry.applyDecay([]);
      expect(result, isEmpty);
    });

    test('drops entries older than 30 days', () {
      final entries = [
        freshEntry(summary: 'Keep this'),
        ancientEntry(summary: 'Drop this — too old'),
      ];

      final result = ProjectMemoryEntry.applyDecay(entries);

      expect(result.length, 1);
      expect(result[0].summary, 'Keep this');
    });

    test('keeps entries younger than 30 days', () {
      final entries = [
        freshEntry(summary: 'Fresh'),
        recentEntry(summary: 'Recent'),
        oldEntry(summary: 'Old but within 30d'),
      ];

      final result = ProjectMemoryEntry.applyDecay(entries);

      expect(result.length, 3);
    });

    test('truncates old entries to ~20 words', () {
      final longSummary = List.generate(50, (i) => 'word$i').join(' ');
      final entries = [oldEntry(summary: longSummary)];

      final result = ProjectMemoryEntry.applyDecay(entries);

      // Old entries are truncated to ~20 words
      final wordCount = result[0].summary.split(RegExp(r'\s+')).length;
      expect(wordCount, lessThanOrEqualTo(22), // 20 words + "..." may count as a "word"
          reason: 'Old entries should be truncated to ~20 words');
    });

    test('truncates recent entries to ~50 words', () {
      final longSummary = List.generate(100, (i) => 'word$i').join(' ');
      final entries = [recentEntry(summary: longSummary)];

      final result = ProjectMemoryEntry.applyDecay(entries);

      final wordCount = result[0].summary.split(RegExp(r'\s+')).length;
      expect(wordCount, lessThanOrEqualTo(52));
    });

    test('does not truncate fresh entries with short summaries', () {
      final summary = 'This is a short fresh memory.';
      final entries = [freshEntry(summary: summary)];

      final result = ProjectMemoryEntry.applyDecay(entries);

      expect(result[0].summary, summary);
    });

    test('sorts entries newest first in output', () {
      final entries = [
        oldEntry(summary: 'Old'),
        freshEntry(summary: 'Fresh'),
        recentEntry(summary: 'Recent'),
      ];

      final result = ProjectMemoryEntry.applyDecay(entries);

      // Newest (fresh) should be first
      expect(result.first.summary, 'Fresh');
    });

    test('respects 2400 character budget', () {
      final longText = 'x' * 500;
      final entries = List.generate(10, (i) => freshEntry(summary: longText));

      final result = ProjectMemoryEntry.applyDecay(entries);

      final totalChars = result.fold(0, (sum, e) => sum + e.summary.length);
      expect(totalChars, lessThanOrEqualTo(2400));
    });
  });

  // ─── formatForPrompt ──────────────────────────────────────────────────

  group('formatForPrompt', () {
    test('empty list returns empty string', () {
      final result = ProjectMemoryEntry.formatForPrompt([]);
      expect(result, '');
    });

    test('single entry includes summary in output', () {
      final entry = freshEntry(summary: 'We fixed the auth bug');
      final result = ProjectMemoryEntry.formatForPrompt([entry]);

      expect(result, contains('We fixed the auth bug'));
    });

    test('each entry is on its own line starting with -', () {
      final entries = [
        freshEntry(summary: 'First memory'),
        freshEntry(summary: 'Second memory'),
      ];
      final result = ProjectMemoryEntry.formatForPrompt(entries);

      final lines = result.split('\n');
      expect(lines.every((l) => l.isEmpty || l.startsWith('- ')), isTrue);
    });

    test('each entry includes time-ago prefix', () {
      final entry = freshEntry(summary: 'Test memory');
      final result = ProjectMemoryEntry.formatForPrompt([entry]);

      // Should contain "[Xh ago]" or "[just now]" prefix
      expect(result, matches(r'\[.+\]'));
    });

    test('multiple entries are all included', () {
      final entries = [
        freshEntry(summary: 'Alpha'),
        recentEntry(summary: 'Beta'),
      ];
      final result = ProjectMemoryEntry.formatForPrompt(entries);

      expect(result, contains('Alpha'));
      expect(result, contains('Beta'));
    });
  });

  // ─── _humanizeAge branches via formatForPrompt ───────────────────────────

  group('formatForPrompt age labels', () {
    ProjectMemoryEntry aged(Duration age) => ProjectMemoryEntry(
          summary: 'note',
          timestamp: DateTime.now().subtract(age),
        );

    test('2 days old shows Nd ago', () {
      final result =
          ProjectMemoryEntry.formatForPrompt([aged(const Duration(days: 2))]);
      expect(result, contains('2d ago'));
    });

    test('6 days old shows 6d ago', () {
      final result =
          ProjectMemoryEntry.formatForPrompt([aged(const Duration(days: 6))]);
      expect(result, contains('6d ago'));
    });

    test('7 days old shows 1w ago', () {
      final result =
          ProjectMemoryEntry.formatForPrompt([aged(const Duration(days: 7))]);
      expect(result, contains('1w ago'));
    });

    test('14 days old shows 2w ago', () {
      final result =
          ProjectMemoryEntry.formatForPrompt([aged(const Duration(days: 14))]);
      expect(result, contains('2w ago'));
    });
  });
}
