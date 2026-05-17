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

  group('capabilityModelForSkills', () {
    test('default profile — starter analytical agent → haiku', () {
      // capability = 0.4*3 + 0.3*3 + 0.2*2 + 0.1*2 = 2.7
      expect(
        capabilityModelForSkills(
          precision: 3,
          creativity: 2,
          insight: 3,
          reliability: 2,
        ),
        'haiku',
      );
    });

    test('default profile — upgraded mid-tier → sonnet', () {
      // capability = 0.4*14 + 0.3*10 + 0.2*8 + 0.1*4 = 10.6
      expect(
        capabilityModelForSkills(
          precision: 10,
          creativity: 4,
          insight: 14,
          reliability: 8,
        ),
        'sonnet',
      );
    });

    test('default profile — elite insight-max → opus', () {
      // capability = 0.4*20 + 0.3*15 + 0.2*15 + 0.1*10 = 16.5
      expect(
        capabilityModelForSkills(
          precision: 15,
          creativity: 10,
          insight: 20,
          reliability: 15,
        ),
        'opus',
      );
    });

    test('creative profile — designer Lv1 starter → haiku', () {
      // creative cap = 0.25*2 + 0.2*2 + 0.2*4 + 0.35*7 = 4.15
      expect(
        capabilityModelForSkills(
          precision: 2,
          creativity: 7,
          insight: 2,
          reliability: 4,
          roleType: 'ui-ux-designer',
        ),
        'haiku',
      );
    });

    test('creative profile — designer with creative-bias upgrades → sonnet', () {
      // creative cap = 0.25*8 + 0.2*8 + 0.2*8 + 0.35*12 = 9.4
      expect(
        capabilityModelForSkills(
          precision: 8,
          creativity: 12,
          insight: 8,
          reliability: 8,
          roleType: 'ui-ux-designer',
        ),
        'sonnet',
      );
    });

    test('creative profile — designer endgame maxed → opus', () {
      // creative cap = 0.25*18 + 0.2*18 + 0.2*20 + 0.35*20 = 19.1
      expect(
        capabilityModelForSkills(
          precision: 18,
          creativity: 20,
          insight: 18,
          reliability: 20,
          roleType: 'ui-ux-designer',
        ),
        'opus',
      );
    });

    test('creative profile — game-designer also uses creative weights', () {
      // creative cap = 0.25*8 + 0.2*8 + 0.2*8 + 0.35*12 = 9.4 → sonnet
      expect(
        capabilityModelForSkills(
          precision: 8,
          creativity: 12,
          insight: 8,
          reliability: 8,
          roleType: 'game-designer',
        ),
        'sonnet',
      );
    });

    test('creative profile — character-artist also uses creative weights', () {
      // creative cap = 0.25*8 + 0.2*8 + 0.2*8 + 0.35*12 = 9.4 → sonnet
      // (default profile would give 0.4*8 + 0.3*8 + 0.2*8 + 0.1*12 = 8.4 — same tier
      // but the formula must match the creative one to stay in sync with server)
      expect(
        capabilityModelForSkills(
          precision: 8,
          creativity: 12,
          insight: 8,
          reliability: 8,
          roleType: 'character-artist',
        ),
        'sonnet',
      );
    });

    test('character-artist Lv1 starter (1/4/6/1/1) → haiku', () {
      // creative cap = 0.25*1 + 0.2*4 + 0.2*1 + 0.35*6 = 3.35
      expect(
        capabilityModelForSkills(
          precision: 4,
          creativity: 6,
          insight: 1,
          reliability: 1,
          roleType: 'character-artist',
        ),
        'haiku',
      );
    });

    test('default profile applied for unknown roleType', () {
      // capability = 0.4*8 + 0.3*8 + 0.2*8 + 0.1*12 = 8.4 → sonnet
      expect(
        capabilityModelForSkills(
          precision: 8,
          creativity: 12,
          insight: 8,
          reliability: 8,
          roleType: 'coder',
        ),
        'sonnet',
      );
    });
  });
}
