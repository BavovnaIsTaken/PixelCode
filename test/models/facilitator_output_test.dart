import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';

void main() {
  group('OutputFormat enum', () {
    test('exposes the five expected facilitator shapes', () {
      expect(OutputFormat.values.length, 5);
      expect(OutputFormat.values, containsAll(<OutputFormat>[
        OutputFormat.questLine,
        OutputFormat.missionBriefing,
        OutputFormat.milestoneTree,
        OutputFormat.sprintBacklog,
        OutputFormat.koanEntry,
      ]));
    });

    test('key uses snake_case persistence-stable identifiers', () {
      expect(OutputFormat.questLine.key, 'quest_line');
      expect(OutputFormat.missionBriefing.key, 'mission_briefing');
      expect(OutputFormat.milestoneTree.key, 'milestone_tree');
      expect(OutputFormat.sprintBacklog.key, 'sprint_backlog');
      expect(OutputFormat.koanEntry.key, 'koan_entry');
    });

    test('every value roundtrips through key/fromKey', () {
      for (final v in OutputFormat.values) {
        expect(OutputFormat.fromKey(v.key), v,
            reason: '${v.key} should roundtrip');
      }
    });

    test('fromKey falls back to questLine for unknown keys', () {
      expect(OutputFormat.fromKey('unknown'), OutputFormat.questLine);
      expect(OutputFormat.fromKey(''), OutputFormat.questLine);
      // Legacy quest_line key (a key absent from fromKey switch arms) also
      // resolves to questLine via the wildcard arm — pin that behavior.
      expect(OutputFormat.fromKey('quest_line'), OutputFormat.questLine);
    });
  });

  group('ProgressView', () {
    test('stores all five fields verbatim', () {
      const p = ProgressView(
        fraction: 0.5,
        earnedXp: 50,
        totalXp: 100,
        isComplete: false,
        label: '1 of 2 quests forged',
      );
      expect(p.fraction, 0.5);
      expect(p.earnedXp, 50);
      expect(p.totalXp, 100);
      expect(p.isComplete, false);
      expect(p.label, '1 of 2 quests forged');
    });

    test('zero-progress state is representable', () {
      const p = ProgressView(
        fraction: 0.0,
        earnedXp: 0,
        totalXp: 100,
        isComplete: false,
        label: '',
      );
      expect(p.fraction, 0.0);
      expect(p.isComplete, isFalse);
    });

    test('completed state is representable', () {
      const p = ProgressView(
        fraction: 1.0,
        earnedXp: 100,
        totalXp: 100,
        isComplete: true,
        label: 'all done',
      );
      expect(p.fraction, 1.0);
      expect(p.isComplete, isTrue);
    });

    test('is a const constructor (compile-time constant)', () {
      const a = ProgressView(
        fraction: 0.0,
        earnedXp: 0,
        totalXp: 0,
        isComplete: false,
        label: '',
      );
      const b = ProgressView(
        fraction: 0.0,
        earnedXp: 0,
        totalXp: 0,
        isComplete: false,
        label: '',
      );
      expect(identical(a, b), isTrue);
    });
  });
}
