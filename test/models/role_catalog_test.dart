import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/character_skins.dart';

void main() {
  group('roleCatalog — character-artist registration', () {
    test('character-artist exists in roleCatalog', () {
      final entry = roleCatalogFor('character-artist');
      expect(entry, isNotNull);
      expect(entry!.roleType, 'character-artist');
      expect(entry.role, 'Художник');
      expect(entry.baseName, 'Піксельмейстер');
    });

    test('character-artist hireCost and salary land in middle tier', () {
      final entry = roleCatalogFor('character-artist')!;
      expect(entry.hireCost, 500);
      expect(entry.salary, 55);
    });

    test('character-artist has Color Soul passive', () {
      final entry = roleCatalogFor('character-artist')!;
      expect(entry.passive.name, 'Color Soul');
      expect(entry.passive.nameUk, 'Кольорова душа');
      expect(entry.passive.icon, '🎨');
    });

    test('character-artist is not a singleton', () {
      final entry = roleCatalogFor('character-artist')!;
      expect(entry.singleton, isFalse);
    });
  });

  group('initialSkillsForRole — character-artist', () {
    test('starter skill bias is 1/4/6/1/1 (creative-heavy, low reliability)', () {
      final skills = initialSkillsForRole('character-artist');
      expect(skills[SkillType.speed], 1);
      expect(skills[SkillType.precision], 4);
      expect(skills[SkillType.creativity], 6);
      expect(skills[SkillType.insight], 1);
      expect(skills[SkillType.reliability], 1);
    });

    test('starter creativity is the highest among all 11 roles', () {
      final artistCreativity = initialSkillsForRole('character-artist')[SkillType.creativity]!;
      for (final role in roleCatalog) {
        if (role.roleType == 'character-artist') continue;
        final c = initialSkillsForRole(role.roleType)[SkillType.creativity]!;
        expect(
          artistCreativity,
          greaterThanOrEqualTo(c),
          reason: 'character-artist creativity ($artistCreativity) must be ≥ '
              '${role.roleType} creativity ($c) — core fantasy invariant',
        );
      }
    });
  });

  group('character_skins: every skin has a palette for character-artist', () {
    test('all 8 skins include character-artist in palettes map', () {
      for (final skin in allCharacterSkins) {
        expect(
          skin.palettes.containsKey('character-artist'),
          isTrue,
          reason: 'skin "${skin.id}" missing character-artist palette',
        );
      }
    });

    test('every character-artist palette has all 7 color slots populated', () {
      for (final skin in allCharacterSkins) {
        final palette = skin.palettes['character-artist'];
        expect(palette, isNotNull, reason: 'skin "${skin.id}" missing palette');
        for (final key in const ['h', 's', 'f', 'e', 'c', 'p', 'b']) {
          final color = palette!.resolve(key);
          expect(
            color.a,
            1.0,
            reason: 'skin "${skin.id}" / character-artist / "$key": '
                'expected opaque color, got alpha=${color.a}',
          );
        }
      }
    });
  });
}
