/// Decor section content for the BuildMenu — furniture and plants browser.
///
/// Migrated from `shop_panel.dart`'s legacy `_FurnitureTab` (Stage 2 of the
/// Build System rework). The Shop now keeps only hires, skills, office tier
/// upgrades, cosmetics, and donation; furniture moves into Build Mode where
/// the player is already pointing at the office.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import 'furniture_sprites.dart';

class BuildDecorSection extends ConsumerStatefulWidget {
  const BuildDecorSection({super.key});

  @override
  ConsumerState<BuildDecorSection> createState() => _BuildDecorSectionState();
}

class _BuildDecorSectionState extends ConsumerState<BuildDecorSection> {
  FurnitureType _selectedType = FurnitureType.coffeeTable;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);
    final c = context.appColors;
    final selectedId = ref.watch(selectedFurnitureIdProvider);

    final filtered =
        furnitureCatalog.where((f) => f.type == _selectedType).toList();
    final totalOwned =
        game.furnitureInventory.values.fold(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader(
          icon: Icons.chair_outlined,
          title: 'Меблі офісу',
          trailing: 'У інвентарі: $totalOwned',
        ),
        const SizedBox(height: 16),
        _SectionHeader(icon: Icons.category_outlined, title: 'Категорія'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final type in FurnitureType.values)
              _TypeChip(
                type: type,
                isSelected: _selectedType == type,
                onTap: () => setState(() => _selectedType = type),
              ),
          ],
        ),
        // Placement hint banner — appears whenever an item is active
        if (selectedId != null) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 12,
                  color: c.accent.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Тап на канвасі — розмістити  ·  Тап тут — скасувати',
                    style: TextStyle(
                      color: c.accent.withValues(alpha: 0.6),
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.storefront_outlined,
          title: _selectedType.label,
        ),
        const SizedBox(height: 8),
        for (final item in filtered)
          _ItemCard(
            item: item,
            totalQty: game.furnitureInventory[item.id] ?? 0,
            availableQty: game.furnitureAvailable(item.id),
            isActive: selectedId == item.id,
            canBuy: notifier.canPurchaseFurniture(item.id),
            onBuy: () {
              notifier.purchaseFurniture(item.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('«${item.name}» у інвентарі! −${item.cost}₲'),
                  backgroundColor: c.success,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            onActivate: () =>
                FurnitureEditModeCoord.enterPlacement(ref, item.id),
            onDeactivate: () => FurnitureEditModeCoord.releaseHold(ref),
          ),
      ],
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Icon(icon, size: 14, color: c.textMedium),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: c.textMedium,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing!,
            style: TextStyle(
              color: c.accent.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Category chip ───────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final FurnitureType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? c.accent.withValues(alpha: 0.15) : c.surfaceDim,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                isSelected ? c.accent.withValues(alpha: 0.4) : c.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(type.icon, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 5),
            Text(
              type.label,
              style: TextStyle(
                color: isSelected ? c.accent : c.textMedium,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Item card ───────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final FurnitureItem item;
  final int totalQty;      // total copies purchased
  final int availableQty;  // copies in inventory (not placed)
  final bool isActive;     // currently selected for placement
  final bool canBuy;
  final VoidCallback onBuy;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  const _ItemCard({
    required this.item,
    required this.totalQty,
    required this.availableQty,
    required this.isActive,
    required this.canBuy,
    required this.onBuy,
    required this.onActivate,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    final notOwned = totalQty == 0;
    final outOfStock = totalQty > 0 && availableQty <= 0;
    final hasStock = availableQty > 0;

    final Color borderColor;
    final Color bgColor;
    final double opacity;

    if (isActive) {
      borderColor = c.accent;
      bgColor = c.accent.withValues(alpha: 0.10);
      opacity = 1.0;
    } else if (hasStock) {
      borderColor = c.success.withValues(alpha: 0.25);
      bgColor = c.surfaceDim;
      opacity = 1.0;
    } else if (outOfStock) {
      borderColor = c.border;
      bgColor = c.surfaceDim;
      opacity = 0.55;
    } else {
      borderColor = c.border;
      bgColor = c.surfaceDim;
      opacity = 1.0;
    }

    return GestureDetector(
      onTap: isActive
          ? onDeactivate
          : (hasStock ? onActivate : null),
      child: Opacity(
        opacity: opacity,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor,
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    _ItemIcon(item: item),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isActive
                                        ? c.accent
                                        : (notOwned
                                            ? c.textMedium
                                            : c.textHigh),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (item.widthTiles > 1 ||
                                  item.heightTiles > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: c.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${item.widthTiles}x${item.heightTiles}',
                                    style: TextStyle(
                                      color:
                                          c.accent.withValues(alpha: 0.8),
                                      fontSize: 7,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style:
                                TextStyle(color: c.textLow, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildAction(c, hasStock, outOfStock),
                  ],
                ),
              ),
              // Left accent strip — active state only
              if (isActive)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(
      ThemeColors c, bool hasStock, bool outOfStock) {
    if (isActive) {
      return _ActionChip(
        label: 'Скасувати',
        color: c.accent,
        onTap: onDeactivate,
      );
    }
    if (hasStock) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyBadge(qty: availableQty, color: c.success),
          const SizedBox(width: 6),
          _ActionChip(
            label: 'Місце',
            color: c.accent,
            onTap: onActivate,
          ),
        ],
      );
    }
    if (outOfStock) {
      return _ActionChip(
        label: '+${item.cost}₲',
        color: c.accent,
        onTap: canBuy ? onBuy : null,
      );
    }
    // Not owned
    return _BuyButton(
      label: '${item.cost}₲',
      enabled: canBuy,
      onTap: canBuy ? onBuy : null,
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _QtyBadge extends StatelessWidget {
  final int qty;
  final Color color;

  const _QtyBadge({required this.qty, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = qty > 99 ? '×99+' : '×$qty';
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : color.withValues(alpha: 0.4);
    return MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: effectiveColor.withValues(alpha: enabled ? 0.4 : 0.15)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: effectiveColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemIcon extends StatelessWidget {
  final FurnitureItem item;

  const _ItemIcon({required this.item});

  @override
  Widget build(BuildContext context) {
    final sprite = furnitureSpriteMap[item.id];
    return Container(
      width: 40,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF252540)),
      ),
      child: Center(
        child: sprite != null
            ? FurnitureSpriteIcon(itemId: item.id, scale: 3.5)
            : Text(item.type.icon, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _BuyButton({
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final color = enabled ? c.accent : c.textLow;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: color.withValues(alpha: enabled ? 0.4 : 0.15)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
