import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/shop/shop_panel_helpers.dart';

void main() {
  group('formatGrymni', () {
    test('renders sub-thousand values verbatim', () {
      expect(formatGrymni(0), '0');
      expect(formatGrymni(1), '1');
      expect(formatGrymni(42), '42');
      expect(formatGrymni(999), '999');
    });

    test('renders even thousands without a decimal', () {
      expect(formatGrymni(1000), '1K');
      expect(formatGrymni(2000), '2K');
      expect(formatGrymni(15000), '15K');
    });

    test('renders fractional thousands with one decimal', () {
      expect(formatGrymni(1500), '1.5K');
      expect(formatGrymni(1999), '2.0K');
      expect(formatGrymni(12345), '12.3K');
    });

    test('renders millions with one decimal', () {
      expect(formatGrymni(1000000), '1.0M');
      expect(formatGrymni(2500000), '2.5M');
    });

    test('handles negative values with a leading sign', () {
      expect(formatGrymni(-500), '-500');
      expect(formatGrymni(-1500), '-1.5K');
      expect(formatGrymni(-1000000), '-1.0M');
    });
  });

  group('grymniLabel (Ukrainian plurals)', () {
    test('singular form for 1, 21, 101', () {
      expect(grymniLabel(1), 'гримня');
      expect(grymniLabel(21), 'гримня');
      expect(grymniLabel(101), 'гримня');
    });

    test('paucal form for 2-4 and 22-24', () {
      expect(grymniLabel(2), 'гримні');
      expect(grymniLabel(3), 'гримні');
      expect(grymniLabel(4), 'гримні');
      expect(grymniLabel(22), 'гримні');
      expect(grymniLabel(24), 'гримні');
    });

    test('plural form for 5-20', () {
      expect(grymniLabel(5), 'гримнів');
      expect(grymniLabel(11), 'гримнів');
      expect(grymniLabel(12), 'гримнів');
      expect(grymniLabel(14), 'гримнів');
      expect(grymniLabel(20), 'гримнів');
    });

    test('plural form for 25-30, 100, 0', () {
      expect(grymniLabel(0), 'гримнів');
      expect(grymniLabel(25), 'гримнів');
      expect(grymniLabel(30), 'гримнів');
      expect(grymniLabel(100), 'гримнів');
    });

    test('handles negative values via abs()', () {
      expect(grymniLabel(-1), 'гримня');
      expect(grymniLabel(-3), 'гримні');
      expect(grymniLabel(-7), 'гримнів');
    });
  });

  group('avatarFrameColor', () {
    test('returns null for null input', () {
      expect(avatarFrameColor(null), isNull);
    });

    test('returns null for unknown frame ids', () {
      expect(avatarFrameColor('frame_unknown'), isNull);
      expect(avatarFrameColor(''), isNull);
    });

    test('returns expected colours for known frames', () {
      expect(avatarFrameColor('frame_neon'), const Color(0xFF00C0D1));
      expect(avatarFrameColor('frame_gold'), const Color(0xFFFFD700));
      expect(avatarFrameColor('frame_fire'), const Color(0xFFFF6B35));
      expect(avatarFrameColor('frame_glitch'), const Color(0xFF9B59B6));
      expect(avatarFrameColor('frame_pixel'), const Color(0xFF22C55E));
      expect(avatarFrameColor('frame_matrix'), const Color(0xFF00FF41));
    });
  });

  group('cosmeticPreviewGlyph', () {
    test('returns full preview for short emoji items', () {
      const item = CosmeticItem(
        id: 'frame_neon',
        type: CosmeticType.avatarFrame,
        name: 'Неон',
        cost: 300,
        preview: '💠',
      );
      expect(cosmeticPreviewGlyph(item), '💠');
    });

    test('returns first grapheme cluster for long template previews', () {
      const item = CosmeticItem(
        id: 'decor_fire',
        type: CosmeticType.nicknameDecor,
        name: 'Вогонь',
        cost: 300,
        preview: '🔥 {n} 🔥',
      );
      // Preview is longer than 4 graphemes → truncate to first user-visible
      // character. Surrogate pair emoji must stay whole (no broken UTF-16).
      expect(cosmeticPreviewGlyph(item), '🔥');
    });

    test('returns full preview when grapheme length is exactly 4', () {
      const item = CosmeticItem(
        id: 'edge',
        type: CosmeticType.skin,
        name: 'Edge',
        cost: 0,
        preview: 'abcd',
      );
      expect(cosmeticPreviewGlyph(item), 'abcd');
    });

    test('emoji-padded long template still surfaces the leading emoji', () {
      const item = CosmeticItem(
        id: 'decor_skull',
        type: CosmeticType.nicknameDecor,
        name: 'Череп',
        cost: 350,
        preview: '☠ {n} ☠',
      );
      expect(cosmeticPreviewGlyph(item), '☠');
    });
  });

  group('showsTemplatePreview', () {
    test('true for nickname decor and title badge', () {
      const decor = CosmeticItem(
        id: 'decor_stars',
        type: CosmeticType.nicknameDecor,
        name: 'Stars',
        cost: 150,
        preview: '★ {n} ★',
      );
      const title = CosmeticItem(
        id: 'title_pro',
        type: CosmeticType.titleBadge,
        name: 'Pro',
        cost: 500,
        preview: '⭐ Pro',
      );
      expect(showsTemplatePreview(decor), isTrue);
      expect(showsTemplatePreview(title), isTrue);
    });

    test('false for skins, frames, send buttons', () {
      const skin = CosmeticItem(
        id: 'skin_casual',
        type: CosmeticType.skin,
        name: 'Кежуал',
        cost: 500,
        preview: '👕',
      );
      const frame = CosmeticItem(
        id: 'frame_neon',
        type: CosmeticType.avatarFrame,
        name: 'Неон',
        cost: 300,
        preview: '💠',
      );
      const sendBtn = CosmeticItem(
        id: 'send_classic',
        type: CosmeticType.sendButtonStyle,
        name: 'Класичний',
        cost: 0,
        preview: '➤',
      );
      expect(showsTemplatePreview(skin), isFalse);
      expect(showsTemplatePreview(frame), isFalse);
      expect(showsTemplatePreview(sendBtn), isFalse);
    });
  });

  group('cosmeticActionLabel', () {
    const paid = CosmeticItem(
      id: 'skin_hacker',
      type: CosmeticType.skin,
      name: 'Хакер',
      cost: 1200,
      preview: '🥷',
    );
    const free = CosmeticItem(
      id: 'title_rookie',
      type: CosmeticType.titleBadge,
      name: 'Новачок',
      cost: 0,
      preview: '🌱 Новачок',
    );

    test('owned + equipped → "Зняти"', () {
      expect(
        cosmeticActionLabel(item: paid, isOwned: true, isEquipped: true),
        'Зняти',
      );
    });

    test('owned + not equipped → "Одягнути"', () {
      expect(
        cosmeticActionLabel(item: paid, isOwned: true, isEquipped: false),
        'Одягнути',
      );
    });

    test('not owned + free → "Безкоштовно"', () {
      expect(
        cosmeticActionLabel(item: free, isOwned: false, isEquipped: false),
        'Безкоштовно',
      );
    });

    test('not owned + paid → formatted price with ₲', () {
      expect(
        cosmeticActionLabel(item: paid, isOwned: false, isEquipped: false),
        '1.2K₲',
      );
    });
  });

  group('canAffordNextHardware', () {
    test('false when current is the top tier', () {
      expect(canAffordNextHardware(HardwareTier.serverRack, 999999), isFalse);
    });

    test('false when player has less than next-tier cost', () {
      // basicLaptop costs 200₲
      expect(canAffordNextHardware(HardwareTier.oldLaptop, 199), isFalse);
    });

    test('true when player has exactly next-tier cost', () {
      expect(canAffordNextHardware(HardwareTier.oldLaptop, 200), isTrue);
    });

    test('true when player has more than next-tier cost', () {
      expect(canAffordNextHardware(HardwareTier.basicLaptop, 600), isTrue);
    });
  });

  group('canAffordNextOffice', () {
    test('false at the top tier (campus)', () {
      expect(canAffordNextOffice(OfficeLevel.campus, 9999999), isFalse);
    });

    test('false when next tier is gated as "В розробці"', () {
      // techHub → campus, but campus is `isWipComingSoon`.
      expect(canAffordNextOffice(OfficeLevel.techHub, 999999999), isFalse);
    });

    test('false when player cannot afford the next tier', () {
      // smallOffice costs 1000₲.
      expect(canAffordNextOffice(OfficeLevel.garage, 999), isFalse);
    });

    test('true with exact funds for the next tier', () {
      expect(canAffordNextOffice(OfficeLevel.garage, 1000), isTrue);
    });

    test('true with more than enough funds', () {
      expect(canAffordNextOffice(OfficeLevel.smallOffice, 50000), isTrue);
    });
  });

  group('nextExpansionCost / canAffordNextExpansion', () {
    test('returns null when all expansion steps are bought', () {
      final maxed = OfficeLevel.garage.expansions.length;
      expect(nextExpansionCost(OfficeLevel.garage, maxed), isNull);
    });

    test('returns the first step cost when none are bought', () {
      expect(
        nextExpansionCost(OfficeLevel.garage, 0),
        OfficeLevel.garage.expansions.first.cost,
      );
    });

    test('canAffordNextExpansion = false when none left', () {
      final maxed = OfficeLevel.garage.expansions.length;
      expect(
        canAffordNextExpansion(OfficeLevel.garage, maxed, 999999),
        isFalse,
      );
    });

    test('canAffordNextExpansion respects affordability', () {
      final firstCost = OfficeLevel.garage.expansions.first.cost;
      expect(canAffordNextExpansion(OfficeLevel.garage, 0, firstCost - 1),
          isFalse);
      expect(canAffordNextExpansion(OfficeLevel.garage, 0, firstCost), isTrue);
      expect(canAffordNextExpansion(OfficeLevel.garage, 0, firstCost + 1),
          isTrue);
    });
  });

  group('canAffordSkillUpgrade', () {
    test('false when at or above skill cap', () {
      expect(
        canAffordSkillUpgrade(
            currentLevel: 12, skillCap: 12, upgradeCost: 100, grymni: 9999),
        isFalse,
      );
    });

    test('false when grymni < cost', () {
      expect(
        canAffordSkillUpgrade(
            currentLevel: 1, skillCap: 12, upgradeCost: 200, grymni: 199),
        isFalse,
      );
    });

    test('true at exact funds and below cap', () {
      expect(
        canAffordSkillUpgrade(
            currentLevel: 5, skillCap: 12, upgradeCost: 200, grymni: 200),
        isTrue,
      );
    });
  });

  group('canPurchaseCosmeticItem', () {
    const item = CosmeticItem(
      id: 'skin_corporate',
      type: CosmeticType.skin,
      name: 'Корпоратив',
      cost: 800,
      preview: '👔',
    );
    const free = CosmeticItem(
      id: 'title_rookie',
      type: CosmeticType.titleBadge,
      name: 'Новачок',
      cost: 0,
      preview: '🌱 Новачок',
    );

    test('false if already owned', () {
      expect(
        canPurchaseCosmeticItem(item: item, isOwned: true, grymni: 99999),
        isFalse,
      );
    });

    test('false if not enough grymni', () {
      expect(
        canPurchaseCosmeticItem(item: item, isOwned: false, grymni: 799),
        isFalse,
      );
    });

    test('true at exact funds', () {
      expect(
        canPurchaseCosmeticItem(item: item, isOwned: false, grymni: 800),
        isTrue,
      );
    });

    test('free items are purchasable with zero grymni', () {
      expect(
        canPurchaseCosmeticItem(item: free, isOwned: false, grymni: 0),
        isTrue,
      );
    });
  });

  group('resolveOfficeCardCta', () {
    test('upgrade CTA when level == current.nextLevel', () {
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.smallOffice,
          current: OfficeLevel.garage,
          currentExpansions: 0,
        ),
        OfficeCardCta.upgrade,
      );
    });

    test('no upgrade CTA when next tier is "В розробці" (campus gating)', () {
      // techHub → campus, gated.
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.campus,
          current: OfficeLevel.techHub,
          currentExpansions: 0,
        ),
        OfficeCardCta.none,
      );
    });

    test('expansion CTA at current tier with steps left', () {
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.garage,
          current: OfficeLevel.garage,
          currentExpansions: 0,
        ),
        OfficeCardCta.expansion,
      );
    });

    test('no CTA at current tier when all expansions are bought', () {
      final maxed = OfficeLevel.garage.expansions.length;
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.garage,
          current: OfficeLevel.garage,
          currentExpansions: maxed,
        ),
        OfficeCardCta.none,
      );
    });

    test('owned-checkmark CTA for past tiers', () {
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.garage,
          current: OfficeLevel.modernOffice,
          currentExpansions: 0,
        ),
        OfficeCardCta.ownedCheckmark,
      );
    });

    test('no CTA for far-future locked tiers', () {
      // garage → next is smallOffice; modernOffice and techHub are out of reach.
      expect(
        resolveOfficeCardCta(
          level: OfficeLevel.modernOffice,
          current: OfficeLevel.garage,
          currentExpansions: 0,
        ),
        OfficeCardCta.none,
      );
    });
  });
}
