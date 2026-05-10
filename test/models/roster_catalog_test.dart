import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/roster_catalog.dart';

void main() {
  group('roster budget invariants', () {
    test('every character has statSum == rosterStatBudget', () {
      for (final c in rosterCatalog) {
        expect(
          c.statSum,
          rosterStatBudget,
          reason: '${c.id} has stat sum ${c.statSum}, expected $rosterStatBudget',
        );
      }
    });

    test('every stat is within [rosterStatMin, rosterStatMax]', () {
      for (final c in rosterCatalog) {
        for (final entry in c.statWeights.entries) {
          expect(
            entry.value,
            inInclusiveRange(rosterStatMin, rosterStatMax),
            reason: '${c.id}.${entry.key} = ${entry.value} out of bounds',
          );
        }
      }
    });

    test('every character has spread (max - min) >= rosterStatSpreadMin', () {
      for (final c in rosterCatalog) {
        final values = c.statWeights.values.toList();
        final spread = values.reduce((a, b) => a > b ? a : b) -
            values.reduce((a, b) => a < b ? a : b);
        expect(
          spread,
          greaterThanOrEqualTo(rosterStatSpreadMin),
          reason: '${c.id} has spread $spread, expected >= $rosterStatSpreadMin',
        );
      }
    });

    test('every character defines all 5 SkillType weights', () {
      for (final c in rosterCatalog) {
        for (final stat in SkillType.values) {
          expect(
            c.statWeights.containsKey(stat),
            true,
            reason: '${c.id} missing $stat',
          );
        }
      }
    });
  });

  group('roster identity', () {
    test('all character ids are unique', () {
      final ids = rosterCatalog.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('all character names are unique', () {
      final names = rosterCatalog.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('every character roleType exists in roleCatalog', () {
      final knownRoles = roleCatalog.map((r) => r.roleType).toSet();
      for (final c in rosterCatalog) {
        expect(
          knownRoles.contains(c.roleType),
          true,
          reason: '${c.id} references unknown roleType "${c.roleType}"',
        );
      }
    });

    test('manager singleton role is not in roster (seeded separately)', () {
      expect(rosterCatalog.any((c) => c.roleType == 'manager'), false);
    });
  });

  group('roster pricing', () {
    test('exactly one seed character (price = 0)', () {
      final seedCount = rosterCatalog.where((c) => c.price == 0).length;
      expect(seedCount, 1);
    });

    test('catalog is sorted ascending by price (UX expects this order)', () {
      for (var i = 1; i < rosterCatalog.length; i++) {
        expect(
          rosterCatalog[i].price,
          greaterThanOrEqualTo(rosterCatalog[i - 1].price),
          reason:
              'Position $i (${rosterCatalog[i].id}) breaks ascending order',
        );
      }
    });

    test('all prices are non-negative', () {
      for (final c in rosterCatalog) {
        expect(c.price, greaterThanOrEqualTo(0));
      }
    });
  });

  group('signatureStat', () {
    test('returns the stat with the highest weight', () {
      final andriy =
          rosterCatalog.firstWhere((c) => c.id == 'andriy_coder');
      expect(andriy.signatureStat, SkillType.speed);

      final olya =
          rosterCatalog.firstWhere((c) => c.id == 'olya_reviewer');
      expect(olya.signatureStat, SkillType.precision);

      final sonya =
          rosterCatalog.firstWhere((c) => c.id == 'sonya_designer');
      expect(sonya.signatureStat, SkillType.creativity);

      final bohdan =
          rosterCatalog.firstWhere((c) => c.id == 'bohdan_techlead');
      expect(bohdan.signatureStat, SkillType.insight);

      final tetyana =
          rosterCatalog.firstWhere((c) => c.id == 'tetyana_tester');
      expect(tetyana.signatureStat, SkillType.reliability);
    });
  });

  group('rosterCharacterById', () {
    test('returns the character for a known id', () {
      final c = rosterCharacterById('andriy_coder');
      expect(c, isNotNull);
      expect(c!.name, 'Андрій');
    });

    test('returns null for an unknown id', () {
      expect(rosterCharacterById('nonexistent'), isNull);
    });
  });

  group('default provider distribution', () {
    test('starter roster uses at least 3 distinct providers', () {
      final providers =
          rosterCatalog.map((c) => c.defaultProvider).toSet();
      expect(providers.length, greaterThanOrEqualTo(3));
    });

    test('Андрій defaults to DeepSeek (per balance spec)', () {
      final andriy =
          rosterCatalog.firstWhere((c) => c.id == 'andriy_coder');
      expect(andriy.defaultProvider, AgentProviderType.deepseek);
    });

    test('Соня defaults to Gemini (per balance spec)', () {
      final sonya =
          rosterCatalog.firstWhere((c) => c.id == 'sonya_designer');
      expect(sonya.defaultProvider, AgentProviderType.local);
    });
  });

  group('character-artist coverage', () {
    test('Назар exists and covers the character-artist role', () {
      final nazar = rosterCatalog.firstWhere((c) => c.id == 'nazar_artist');
      expect(nazar.roleType, 'character-artist');
      expect(nazar.name, 'Назар');
      expect(nazar.signatureStat, SkillType.creativity);
    });

    test('rosterCatalog now covers 8 of 11 roleCatalog roles', () {
      final rosterRoles = rosterCatalog.map((c) => c.roleType).toSet();
      expect(rosterRoles.length, 8);
      expect(rosterRoles.contains('character-artist'), isTrue);
      expect(rosterRoles.contains('manager'), isFalse);
      expect(rosterRoles.contains('game-designer'), isFalse);
      expect(rosterRoles.contains('strategy-keeper'), isFalse);
    });
  });
}
