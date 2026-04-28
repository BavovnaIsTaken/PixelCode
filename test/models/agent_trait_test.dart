import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_trait.dart';

void main() {
  group('AgentTrait', () {
    final now = DateTime.now();
    final pastDate = now.subtract(const Duration(days: 7));

    test('emphasis is note when frequency < 3', () {
      final trait = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'precision',
        lesson: 'Catches edge cases',
        frequency: 1,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait.emphasis, TraitEmphasis.note);
    });

    test('emphasis is important when frequency is 3–4', () {
      final trait = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'async',
        lesson: 'Handles concurrency',
        frequency: 3,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait.emphasis, TraitEmphasis.important);
    });

    test('emphasis is critical when frequency >= 5', () {
      final trait = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'testing',
        lesson: 'Writes comprehensive tests',
        frequency: 5,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait.emphasis, TraitEmphasis.critical);
    });

    test('emphasis scales with very high frequency', () {
      final trait = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'refactoring',
        lesson: 'Improves code quality',
        frequency: 42,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait.emphasis, TraitEmphasis.critical);
    });

    test('can create weakness trait', () {
      final trait = AgentTrait(
        id: 'weak-1',
        agentId: 'agent-1',
        type: TraitType.weakness,
        category: 'debugging',
        tag: 'null-checks',
        lesson: 'Often misses null safety',
        frequency: 2,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait.type, TraitType.weakness);
      expect(trait.emphasis, TraitEmphasis.note);
    });

    test('fromJson parses strength trait correctly', () {
      final json = {
        'id': 'trait-1',
        'agentId': 'agent-1',
        'type': 'strength',
        'category': 'coding',
        'tag': 'precision',
        'lesson': 'Catches edge cases',
        'frequency': 3,
        'firstSeen': pastDate.toIso8601String(),
        'lastSeen': now.toIso8601String(),
      };
      final trait = AgentTrait.fromJson(json);
      expect(trait.id, 'trait-1');
      expect(trait.agentId, 'agent-1');
      expect(trait.type, TraitType.strength);
      expect(trait.frequency, 3);
      expect(trait.emphasis, TraitEmphasis.important);
    });

    test('fromJson parses weakness trait correctly', () {
      final json = {
        'id': 'weak-1',
        'agentId': 'agent-1',
        'type': 'weakness',
        'category': 'debugging',
        'tag': 'error-handling',
        'lesson': 'Prone to race conditions',
        'frequency': 2,
        'firstSeen': pastDate.toIso8601String(),
        'lastSeen': now.toIso8601String(),
      };
      final trait = AgentTrait.fromJson(json);
      expect(trait.type, TraitType.weakness);
    });

    test('fromJson defaults frequency to 1 if missing', () {
      final json = {
        'id': 'trait-1',
        'agentId': 'agent-1',
        'type': 'strength',
        'category': 'coding',
        'tag': 'precision',
        'lesson': 'Catches edge cases',
        'firstSeen': pastDate.toIso8601String(),
        'lastSeen': now.toIso8601String(),
      };
      final trait = AgentTrait.fromJson(json);
      expect(trait.frequency, 1);
      expect(trait.emphasis, TraitEmphasis.note);
    });

    test('two traits with same fields are equal (const)', () {
      final trait1 = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'precision',
        lesson: 'Catches edge cases',
        frequency: 3,
        firstSeen: pastDate,
        lastSeen: now,
      );
      final trait2 = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'precision',
        lesson: 'Catches edge cases',
        frequency: 3,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(trait1 == trait2, isTrue);
    });

    test('traits with different frequency have different emphasis', () {
      final low = AgentTrait(
        id: 'trait-1',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'precision',
        lesson: 'Catches edge cases',
        frequency: 1,
        firstSeen: pastDate,
        lastSeen: now,
      );
      final high = AgentTrait(
        id: 'trait-2',
        agentId: 'agent-1',
        type: TraitType.strength,
        category: 'coding',
        tag: 'precision',
        lesson: 'Catches edge cases',
        frequency: 6,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(low.emphasis, TraitEmphasis.note);
      expect(high.emphasis, TraitEmphasis.critical);
      expect(low.emphasis != high.emphasis, isTrue);
    });

    test('equal traits have equal hashCodes', () {
      final t1 = AgentTrait(
        id: 'x',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'code',
        tag: 'clean',
        lesson: 'Writes clean code',
        frequency: 2,
        firstSeen: pastDate,
        lastSeen: now,
      );
      final t2 = AgentTrait(
        id: 'x',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'code',
        tag: 'clean',
        lesson: 'Writes clean code',
        frequency: 2,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(t1 == t2, isTrue);
      expect(t1.hashCode, t2.hashCode);
    });

    test('traits with different id have different hashCodes', () {
      final t1 = AgentTrait(
        id: 'a',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'code',
        tag: 'clean',
        lesson: 'Lesson',
        frequency: 1,
        firstSeen: pastDate,
        lastSeen: now,
      );
      final t2 = AgentTrait(
        id: 'b',
        agentId: 'coder#1',
        type: TraitType.strength,
        category: 'code',
        tag: 'clean',
        lesson: 'Lesson',
        frequency: 1,
        firstSeen: pastDate,
        lastSeen: now,
      );
      expect(t1 == t2, isFalse);
    });
  });
}
