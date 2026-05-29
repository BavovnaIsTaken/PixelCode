/// Pure, side-effect-free helpers extracted from `shop_panel.dart`.
///
/// These power the Shop UI's number formatting, plural agreement,
/// cosmetic visuals, and "can purchase / can upgrade" predicates. Keeping
/// them in their own library lets us unit-test the logic without pumping
/// the entire 700-line panel widget.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../utils/grymni_format.dart';

export '../../utils/grymni_format.dart' show formatGrymni;

/// Ukrainian plural agreement for "гримня" — picks one of three forms based
/// on the last two digits of [n], which matches Slavic plural rules.
///
///   * 1, 21, 31 …  → "гримня"
///   * 2-4, 22-24 … → "гримні"
///   * 5-20, 25-30… → "гримнів"
String grymniLabel(int n) {
  final abs = n.abs();
  final mod10 = abs % 10;
  final mod100 = abs % 100;
  if (mod10 == 1 && mod100 != 11) return 'гримня';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'гримні';
  return 'гримнів';
}

// ─── Cosmetic helpers ───────────────────────────────────────────────────────

/// Avatar frame ID → accent colour. Returns null for unknown / unequipped
/// frame IDs so callers can fall back to a neutral border colour.
Color? avatarFrameColor(String? frameId) {
  if (frameId == null) return null;
  return _frameColors[frameId];
}

const _frameColors = <String, Color>{
  'frame_neon': Color(0xFF00C0D1),
  'frame_gold': Color(0xFFFFD700),
  'frame_fire': Color(0xFFFF6B35),
  'frame_glitch': Color(0xFF9B59B6),
  'frame_pixel': Color(0xFF22C55E),
  'frame_matrix': Color(0xFF00FF41),
};

/// Resolves the small preview glyph shown inside a cosmetic card's icon
/// square. We can't fit the full nickname-decoration template in 44×44 px,
/// so we trim previews longer than 4 user-visible characters down to their
/// first grapheme cluster — surrogate-pair emojis (e.g. 🔥) stay intact.
String cosmeticPreviewGlyph(CosmeticItem item) {
  final chars = item.preview.characters;
  if (chars.length <= 4) return item.preview;
  return chars.first;
}

/// Whether a cosmetic should render its full template preview line below
/// the name. Skins / frames / send-button styles render only the icon glyph.
bool showsTemplatePreview(CosmeticItem item) {
  return item.type == CosmeticType.nicknameDecor ||
      item.type == CosmeticType.titleBadge;
}

/// Action button label for a cosmetic card.
///
///   * Owned + equipped → "Зняти"
///   * Owned + not equipped → "Одягнути"
///   * Not owned + free → "Безкоштовно"
///   * Not owned + paid → e.g. "1.5K₲"
String cosmeticActionLabel({
  required CosmeticItem item,
  required bool isOwned,
  required bool isEquipped,
}) {
  if (isOwned) return isEquipped ? 'Зняти' : 'Одягнути';
  if (item.cost == 0) return 'Безкоштовно';
  return '${formatGrymni(item.cost)}₲';
}

// ─── "Can purchase / can upgrade" predicates ────────────────────────────────

/// Whether [grymni] is enough to afford the next hardware tier above
/// [current]. Returns false when [current] is already the top tier.
bool canAffordNextHardware(HardwareTier current, int grymni) {
  final next = current.nextTier;
  if (next == null) return false;
  return grymni >= next.cost;
}

/// Whether the office can be upgraded to its next tier given current
/// [grymni]. Returns false when:
///   * already the maximum tier, or
///   * the next tier is gated as "В розробці" (e.g. campus), or
///   * the player can't afford it.
bool canAffordNextOffice(OfficeLevel current, int grymni) {
  final next = current.nextLevel;
  if (next == null) return false;
  if (next.isWipComingSoon) return false;
  return grymni >= next.upgradeCost;
}

/// Cost of the next office expansion step, or null when the current tier
/// has none (or all steps are already bought).
int? nextExpansionCost(OfficeLevel level, int expansionsBought) {
  if (expansionsBought >= level.expansions.length) return null;
  return level.expansions[expansionsBought].cost;
}

/// Whether the player can afford the next expansion step at [level].
bool canAffordNextExpansion(OfficeLevel level, int expansionsBought, int grymni) {
  final cost = nextExpansionCost(level, expansionsBought);
  if (cost == null) return false;
  return grymni >= cost;
}

/// Whether a skill upgrade is *purchasable* — below the level-cap and
/// affordable. Mirrors `GameEconomyNotifier.canUpgradeSkill`.
bool canAffordSkillUpgrade({
  required int currentLevel,
  required int skillCap,
  required int upgradeCost,
  required int grymni,
}) {
  if (currentLevel >= skillCap) return false;
  return grymni >= upgradeCost;
}

/// Whether a cosmetic is purchasable: not owned and the player has enough.
/// Free items (cost == 0) are always purchasable when not owned.
bool canPurchaseCosmeticItem({
  required CosmeticItem item,
  required bool isOwned,
  required int grymni,
}) {
  if (isOwned) return false;
  return grymni >= item.cost;
}

// ─── Office card visual state ───────────────────────────────────────────────

/// Which CTA an office card should show. Encodes the precedence rules from
/// the original `_OfficeLevelCard`.
enum OfficeCardCta {
  /// "Upgrade for X₲" — when [level] is the next tier above current.
  upgrade,

  /// "+ X₲" — when [level] is the current tier and an expansion step is
  /// available.
  expansion,

  /// A green checkmark — when [level] is below current (already unlocked).
  ownedCheckmark,

  /// Nothing — when the level is locked (above the next tier) or the
  /// current tier has no expansion left to buy.
  none,
}

/// Pure resolver for the office-card CTA. The widget can switch on the
/// returned enum without re-deriving the predicates inline.
OfficeCardCta resolveOfficeCardCta({
  required OfficeLevel level,
  required OfficeLevel current,
  required int currentExpansions,
}) {
  if (level == current.nextLevel && !level.isWipComingSoon) {
    return OfficeCardCta.upgrade;
  }
  if (level == current) {
    final hasExpansion = currentExpansions < level.expansions.length;
    return hasExpansion ? OfficeCardCta.expansion : OfficeCardCta.none;
  }
  if (level.index < current.index) return OfficeCardCta.ownedCheckmark;
  return OfficeCardCta.none;
}
