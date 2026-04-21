/// Settings browser for the "send" button cosmetic.
///
/// Each of the four variants (defined in [sendButtonCatalog]) renders its
/// live preview — the same widget that ships in the chat input, so the
/// hover/tap animations the user feels here match production 1:1.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../models/send_button_style.dart';
import '../../providers/game_economy_provider.dart';
import '../chat/send_button.dart';

// The send-button variants filtered from the shared cosmetic catalog.
List<CosmeticItem> get _sendButtonItems => cosmeticCatalog
    .where((c) => c.type == CosmeticType.sendButtonStyle)
    .toList();

class SendButtonSection extends ConsumerWidget {
  const SendButtonSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameEconomyProvider);
    final economy = ref.read(gameEconomyProvider.notifier);
    final activeId = game.equippedCosmetics[CosmeticType.sendButtonStyle.index];
    final items = _sendButtonItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: 2 columns wide, 1 column on narrow surfaces.
        final cols = constraints.maxWidth < 440 ? 1 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 118,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final owned = item.cost == 0 || economy.ownsCosmetic(item.id);
            // Classic is free: treat "no equipped ID" as active classic.
            final isActive = activeId == item.id ||
                (activeId == null && item.id == 'send_classic');
            final canAfford = game.grymni >= item.cost;
            return _SendButtonCard(
              item: item,
              isActive: isActive,
              isOwned: owned,
              canAfford: canAfford,
              onTap: () {
                if (!owned) return;
                if (item.id == 'send_classic') {
                  economy.unequipCosmetic(CosmeticType.sendButtonStyle);
                } else {
                  economy.equipCosmetic(item.id);
                }
              },
              onPurchase: owned || !canAfford
                  ? null
                  : () => economy.purchaseCosmetic(item.id),
            );
          },
        );
      },
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────

class _SendButtonCard extends StatelessWidget {
  const _SendButtonCard({
    required this.item,
    required this.isActive,
    required this.isOwned,
    required this.canAfford,
    required this.onTap,
    required this.onPurchase,
  });

  final CosmeticItem item;
  final bool isActive;
  final bool isOwned;
  final bool canAfford;
  final VoidCallback onTap;
  final VoidCallback? onPurchase;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final variant = sendButtonVariantForId(item.id);

    final borderColor = isActive
        ? c.accent
        : isOwned
            ? c.border
            : Colors.white.withValues(alpha: 0.06);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Live, interactive preview of the variant.
            SizedBox(
              width: 52,
              height: 52,
              child: Center(
                child: AbsorbPointer(
                  absorbing: !isOwned,
                  // A no-op onPressed is fine — we just want the hover/tap
                  // animations to fire for preview. For owned items we also
                  // equip on-tap via the card-level GestureDetector above.
                  child: SendButton(
                    onPressed: onTap,
                    variantOverride: variant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textHigh,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.cost > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.auto_awesome,
                            size: 11,
                            color: c.gold.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _StatusLine(
                    item: item,
                    isActive: isActive,
                    isOwned: isOwned,
                    canAfford: canAfford,
                    onPurchase: onPurchase,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.item,
    required this.isActive,
    required this.isOwned,
    required this.canAfford,
    required this.onPurchase,
  });

  final CosmeticItem item;
  final bool isActive;
  final bool isOwned;
  final bool canAfford;
  final VoidCallback? onPurchase;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    if (isActive) {
      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Активна',
            style: TextStyle(
              color: c.accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (isOwned) {
      return Text(
        'Клікни, щоб увімкнути',
        style: TextStyle(
          color: c.textMedium.withValues(alpha: 0.8),
          fontSize: 11,
        ),
      );
    }

    // Locked — show price + buy button.
    return Row(
      children: [
        Icon(Icons.lock_outline,
            size: 11, color: c.textLow.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${item.cost} ₲',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: canAfford ? c.gold : c.textLow,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _BuyButton(enabled: canAfford, onTap: onPurchase),
      ],
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: enabled
              ? c.gold.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: enabled
                ? c.gold.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          'Купити',
          style: TextStyle(
            color: enabled ? c.gold : c.textLow,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
