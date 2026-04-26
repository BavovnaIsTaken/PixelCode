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

    final filtered =
        furnitureCatalog.where((f) => f.type == _selectedType).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader(
          icon: Icons.chair_outlined,
          title: 'Меблі офісу',
          trailing: '${game.ownedFurniture.length} придбано',
        ),
        const SizedBox(height: 8),
        _editModeBlock(c, game),
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
        const SizedBox(height: 16),
        _SectionHeader(
          icon: Icons.storefront_outlined,
          title: _selectedType.label,
        ),
        const SizedBox(height: 8),
        for (final item in filtered)
          _ItemCard(
            item: item,
            isOwned: game.ownedFurniture.contains(item.id),
            canBuy: notifier.canPurchaseFurniture(item.id),
            onBuy: () {
              notifier.purchaseFurniture(item.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('«${item.name}» придбано! −${item.cost}₲'),
                  backgroundColor: c.success,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _editModeBlock(ThemeColors c, GameState game) {
    final isEditMode = ref.watch(furnitureEditModeProvider);
    final selectedId = ref.watch(selectedFurnitureIdProvider);
    final selectedItem =
        selectedId != null ? furnitureById(selectedId) : null;

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            final current = ref.read(furnitureEditModeProvider);
            ref.read(furnitureEditModeProvider.notifier).state = !current;
            if (current) {
              ref.read(selectedFurnitureIdProvider.notifier).state = null;
            }
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isEditMode
                  ? c.accent.withValues(alpha: 0.12)
                  : c.surfaceDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isEditMode
                    ? c.accent.withValues(alpha: 0.4)
                    : c.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isEditMode
                      ? Icons.grid_on_rounded
                      : Icons.grid_view_rounded,
                  size: 14,
                  color: isEditMode ? c.accent : c.accent.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  isEditMode
                      ? 'Редактор увімкнено'
                      : 'Розмістити меблі',
                  style: TextStyle(
                    color: isEditMode ? c.accent : c.textMedium,
                    fontSize: 10,
                    fontWeight:
                        isEditMode ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isEditMode
                        ? c.accent.withValues(alpha: 0.2)
                        : c.surfaceDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isEditMode ? 'ВИМКНУТИ' : 'УВІМКНУТИ',
                    style: TextStyle(
                      color: isEditMode ? c.accent : c.textLow,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isEditMode) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedItem != null
                      ? 'Обрано: ${selectedItem.name}'
                      : 'Обери предмет для розміщення:',
                  style: TextStyle(color: c.textMedium, fontSize: 9),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final id in game.ownedFurniture)
                      GestureDetector(
                        onTap: () => ref
                            .read(selectedFurnitureIdProvider.notifier)
                            .state = selectedId == id ? null : id,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: selectedId == id
                                ? c.accent.withValues(alpha: 0.2)
                                : c.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: selectedId == id
                                  ? c.accent.withValues(alpha: 0.5)
                                  : c.border,
                            ),
                          ),
                          child: Text(
                            furnitureById(id)?.name ?? id,
                            style: TextStyle(
                              color: selectedId == id
                                  ? c.accent
                                  : c.textMedium,
                              fontSize: 9,
                              fontWeight: selectedId == id
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Тап на полотні = розмістити. Тап на меблях = прибрати.',
                  style: TextStyle(color: c.textLow, fontSize: 8),
                ),
              ],
            ),
          ),
        ],
        if (!isEditMode)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Розміщено: ${game.placedFurniture.length}',
              style: TextStyle(color: c.textMedium, fontSize: 9),
            ),
          ),
      ],
    );
  }
}

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
          color: isSelected
              ? c.accent.withValues(alpha: 0.15)
              : c.surfaceDim,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? c.accent.withValues(alpha: 0.4)
                : c.border,
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

class _ItemCard extends StatelessWidget {
  final FurnitureItem item;
  final bool isOwned;
  final bool canBuy;
  final VoidCallback onBuy;

  const _ItemCard({
    required this.item,
    required this.isOwned,
    required this.canBuy,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final borderColor = isOwned
        ? c.success.withValues(alpha: 0.3)
        : c.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(item.type.icon,
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
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
                          color: isOwned ? c.textHigh : c.textMedium,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.widthTiles > 1 || item.heightTiles > 1) ...[
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
                            color: c.accent.withValues(alpha: 0.8),
                            fontSize: 7,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (isOwned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: c.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'КУПЛЕНО',
                          style: TextStyle(
                            color: c.success,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(color: c.textLow, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isOwned)
            Icon(Icons.check_circle, size: 18, color: c.success.withValues(alpha: 0.6))
          else
            _BuyButton(
              label: '${item.cost}₲',
              enabled: canBuy,
              onTap: canBuy ? onBuy : null,
            ),
        ],
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
            border: Border.all(color: color.withValues(alpha: enabled ? 0.4 : 0.15)),
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
