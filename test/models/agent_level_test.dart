import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_level.dart';

void main() {
  group('xpToNextLevel', () {
    test('Lv 1 needs 50 XP', () {
      expect(xpToNextLevel(1), 50);
    });

    test('matches 50 * level^1.6 formula at higher levels', () {
      // 50 * 2^1.6 = 151.57...
      expect(xpToNextLevel(2), 151);
      // 50 * 10^1.6 ≈ 1990.99 (double precision) → floor → 1990
      expect(xpToNextLevel(10), 1990);
    });

    test('clamps at maxAgentLevel', () {
      expect(xpToNextLevel(100), xpToNextLevel(maxAgentLevel));
    });

    test('treats levels below 1 as Lv 1', () {
      expect(xpToNextLevel(0), 50);
      expect(xpToNextLevel(-5), 50);
    });
  });

  group('skillCap', () {
    test('formula is 10 + 2*level', () {
      expect(skillCap(1), 12);
      expect(skillCap(5), 20);
      expect(skillCap(10), 30);
      expect(skillCap(20), 50);
    });

    test('clamps input to [1, maxAgentLevel]', () {
      expect(skillCap(0), 12);
      expect(skillCap(999), 50);
    });
  });

  group('xpForTask', () {
    test('difficulty squared times quality', () {
      expect(xpForTask(difficulty: 1, quality: 1.0, agentLevel: 1), 1);
      expect(xpForTask(difficulty: 3, quality: 1.0, agentLevel: 1), 9);
      expect(xpForTask(difficulty: 5, quality: 1.5, agentLevel: 1), 37);
    });

    test('applies 0.25 diminishing when agent is far overqualified', () {
      // difficulty 1, lvl 10: 1 + 3 = 4 < 10 ⇒ diminish
      // base 1 * 0.25 = 0.25 → floor → 0
      expect(xpForTask(difficulty: 1, quality: 1.0, agentLevel: 10), 0);
      // 4 * 0.25 = 1
      expect(xpForTask(difficulty: 2, quality: 1.0, agentLevel: 10), 1);
    });

    test('does not diminish when within 3 levels', () {
      // difficulty 5, lvl 7: 5 + 3 = 8 ≥ 7 ⇒ no diminishing
      expect(xpForTask(difficulty: 5, quality: 1.0, agentLevel: 7), 25);
    });

    test('recoveredFromFailure adds 20%', () {
      // 9 * 1.2 = 10.8 → floor → 10
      expect(
        xpForTask(
          difficulty: 3,
          quality: 1.0,
          agentLevel: 3,
          recoveredFromFailure: true,
        ),
        10,
      );
    });

    test('clamps difficulty out of range', () {
      expect(xpForTask(difficulty: 0, quality: 1.0, agentLevel: 1), 1); // as 1
      expect(xpForTask(difficulty: 99, quality: 1.0, agentLevel: 1), 25); // as 5
    });
  });
}
