/// Inventory — a slot-grid of the tangible items the player OWNS and can act
/// on. This is deliberately NOT a settings surface: button styles, skins,
/// titles, frames and themes live in Settings; the inventory holds only
/// "things you do something with":
///
///   * Furniture — purchased office props. Tap a cell → place it on the canvas
///     (enters Build Mode with the item in hand).
///   * Оздоблення — owned wall / floor skin packs. Tap → jump to Build Mode's
///     Стіни/Підлога section to apply on a room.
///
/// Items live in a fixed cell grid (RPG/Minecraft-style, with empty slots).
/// Long-press a cell to drag it to another slot — the custom order persists on
/// GameState.inventoryOrder. The «Сортувати» button re-groups by category.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import '../canvas/build_menu.dart' show BuildSection;
import '../canvas/furniture_sprites.dart';

enum _ItemKind { furniture, wallPack, floorPack }

/// A single owned inventory item, normalised across furniture and skin packs
/// so the grid can render and act on them uniformly.
class _InvItem {
  final String id;
  final _ItemKind kind;
  final String name;

  // Furniture only.
  final FurnitureItem? furniture;
  final int total; // copies owned
  final int available; // copies not yet placed

  // Skin packs only — three preview colours.
  final List<Color> swatch;

  const _InvItem({
    required this.id,
    required this.kind,
    required this.name,
    this.furniture,
    this.total = 0,
    this.available = 0,
    this.swatch = const [],
  });
}

class InventoryPanel extends ConsumerStatefulWidget {
  const InventoryPanel({super.key});

  @override
  ConsumerState<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends ConsumerState<InventoryPanel> {
  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final c = context.appColors;

    final items = _ownedItems(game);
    final ownedOrdered = items.keys.toList();
    final reconciled = _reconcile(game.inventoryOrder, ownedOrdered);

    return ColoredBox(
      color: c.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(c, ownedOrdered),
          Container(height: 1, color: c.divider),
          Expanded(
            child: items.isEmpty
                ? _emptyState(c)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 8.0;
                      const pad = 12.0;
                      final usable = constraints.maxWidth - pad * 2;
                      // Aim for ~64px cells, clamped to a sensible column count.
                      final cols =
                          (usable / 72).floor().clamp(4, 8);
                      final cellSize =
                          (usable - spacing * (cols - 1)) / cols;

                      final slots = _padToGrid(reconciled, cols);

                      return GridView.builder(
                        padding: const EdgeInsets.all(pad),
                        itemCount: slots.length,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: 1,
                        ),
                        itemBuilder: (context, i) => _cell(
                          c,
                          slots,
                          i,
                          items,
                          cellSize,
                          cols,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _header(ThemeColors c, List<String> ownedOrdered) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: c.accent),
          const SizedBox(width: 8),
          Text(
            'Інвентар',
            style: TextStyle(
              color: c.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${ownedOrdered.length}',
            style: TextStyle(
              color: c.accent.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (ownedOrdered.isNotEmpty)
            _SortButton(onTap: () => _sort(ownedOrdered)),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 36, color: c.textLow.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              'Поки порожньо',
              style: TextStyle(
                color: c.textMedium,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Купи меблі або оздоблення у Build → Декор / Стіни',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textLow, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Cell ─────────────────────────────────────────────────────────────────

  Widget _cell(
    ThemeColors c,
    List<String> slots,
    int i,
    Map<String, _InvItem> items,
    double size,
    int cols,
  ) {
    final id = slots[i];
    final item = id.isEmpty ? null : items[id];

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => _onDrop(d.data, i, cols),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        if (item == null) {
          return _EmptyCell(c: c, hovering: hovering);
        }
        return LongPressDraggable<int>(
          data: i,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(c: c, item: item, size: size),
          childWhenDragging: _EmptyCell(c: c, hovering: false),
          child: _FilledCell(
            c: c,
            item: item,
            hovering: hovering,
            onTap: () => _useItem(item),
          ),
        );
      },
    );
  }

  // ─── Owned-item catalog ──────────────────────────────────────────────────────

  /// Owned items in canonical (default) order: furniture by catalog order,
  /// then wall packs, then floor packs. Insertion order is preserved by the
  /// returned LinkedHashMap.
  Map<String, _InvItem> _ownedItems(GameState g) {
    final m = <String, _InvItem>{};
    for (final f in furnitureCatalog) {
      final total = g.furnitureInventory[f.id] ?? 0;
      if (total > 0) {
        m[f.id] = _InvItem(
          id: f.id,
          kind: _ItemKind.furniture,
          name: f.name,
          furniture: f,
          total: total,
          available: g.furnitureAvailable(f.id),
        );
      }
    }
    for (final p in wallSkinPackCatalog) {
      if (p.cost == 0 || g.ownedWallSkinPacks.contains(p.id)) {
        m[p.id] = _InvItem(
          id: p.id,
          kind: _ItemKind.wallPack,
          name: p.name,
          swatch: [Color(p.wallBase), Color(p.wallTop), Color(p.wallInner)],
        );
      }
    }
    for (final p in floorSkinPackCatalog) {
      if (p.cost == 0 || g.ownedFloorSkinPacks.contains(p.id)) {
        m[p.id] = _InvItem(
          id: p.id,
          kind: _ItemKind.floorPack,
          name: p.name,
          swatch: [Color(p.floorDark), Color(p.floorLight), Color(p.floorGrid)],
        );
      }
    }
    return m;
  }

  /// Merge the persisted slot order with current ownership: keep each
  /// still-owned id in its slot (blanking unowned ids and any stray
  /// duplicate), then append newly-owned items right after the last occupied
  /// slot — a purchase lands at the end, not in an intentional gap.
  List<String> _reconcile(List<String> persisted, List<String> ownedOrdered) {
    final ownedSet = ownedOrdered.toSet();
    final seen = <String>{};
    final slots = [
      for (final id in persisted)
        (ownedSet.contains(id) && seen.add(id)) ? id : '',
    ];
    var insertAt = slots.lastIndexWhere((s) => s.isNotEmpty) + 1;
    for (final id in ownedOrdered) {
      if (seen.contains(id)) continue;
      while (insertAt < slots.length && slots[insertAt].isNotEmpty) {
        insertAt++;
      }
      if (insertAt < slots.length) {
        slots[insertAt] = id;
      } else {
        slots.add(id);
      }
      insertAt++;
      seen.add(id);
    }
    return slots;
  }

  /// Pad to a full rectangular grid with a spare row of empty slots to drag
  /// into (minimum 4 rows).
  List<String> _padToGrid(List<String> reconciled, int cols) {
    final slots = List<String>.from(reconciled);
    final lastIdx = slots.lastIndexWhere((s) => s.isNotEmpty);
    final usedRows = lastIdx < 0 ? 0 : (lastIdx ~/ cols) + 1;
    final minRows = math.max(4, usedRows + 1);
    final target = minRows * cols;
    while (slots.length < target) {
      slots.add('');
    }
    while (slots.length % cols != 0) {
      slots.add('');
    }
    return slots;
  }

  // ─── Actions ────────────────────────────────────────────────────────────────

  void _onDrop(int from, int to, int cols) {
    if (from == to || from < 0 || to < 0) return;
    // Re-derive the live grid rather than trusting the slot list captured at
    // build time, so a drop can't clobber an intervening reorder/purchase.
    final game = ref.read(gameEconomyProvider);
    final ownedOrdered = _ownedItems(game).keys.toList();
    final next = _padToGrid(_reconcile(game.inventoryOrder, ownedOrdered), cols);
    if (from >= next.length || to >= next.length) return;
    final tmp = next[to];
    next[to] = next[from];
    next[from] = tmp;
    // Persist trimmed — display re-pads empties.
    while (next.isNotEmpty && next.last.isEmpty) {
      next.removeLast();
    }
    ref.read(gameEconomyProvider.notifier).setInventoryOrder(next);
  }

  void _sort(List<String> ownedOrdered) {
    // ownedOrdered is already grouped by category (furniture by type, then
    // walls, then floors) — adopting it compacts the grid and re-groups it.
    ref
        .read(gameEconomyProvider.notifier)
        .setInventoryOrder(List<String>.from(ownedOrdered));
  }

  void _useItem(_InvItem item) {
    switch (item.kind) {
      case _ItemKind.furniture:
        if (item.available > 0) {
          _placeFurniture(item.id);
        } else {
          _toast('Усі копії «${item.name}» вже розміщено');
        }
      case _ItemKind.wallPack:
        _gotoBuildSection(BuildSection.walls,
            'Обери кімнату в Build, щоб застосувати «${item.name}»');
      case _ItemKind.floorPack:
        _gotoBuildSection(BuildSection.floors,
            'Обери кімнату в Build, щоб застосувати «${item.name}»');
    }
  }

  /// Hand the player to the office canvas with the furniture item in hand.
  void _placeFurniture(String itemId) {
    ref.read(buildModeProvider.notifier).enter();
    FurnitureEditModeCoord.enterPlacement(ref, itemId);
    ref.read(officeDeepLinkProvider.notifier).state =
        (ref.read(officeDeepLinkProvider) ?? 0) + 1;
  }

  /// Open Build Mode at [section] on the office canvas (for applying packs).
  void _gotoBuildSection(BuildSection section, String hint) {
    final build = ref.read(buildModeProvider.notifier);
    build.enter();
    build.setSection(section);
    ref.read(officeDeepLinkProvider.notifier).state =
        (ref.read(officeDeepLinkProvider) ?? 0) + 1;
    _toast(hint);
  }

  void _toast(String message) {
    final c = context.appColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: c.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ─── Sort button ──────────────────────────────────────────────────────────────

class _SortButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SortButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort_rounded, size: 13, color: c.textMedium),
              const SizedBox(width: 5),
              Text(
                'Сортувати',
                style: TextStyle(
                  color: c.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cells ───────────────────────────────────────────────────────────────────

class _EmptyCell extends StatelessWidget {
  final ThemeColors c;
  final bool hovering;

  const _EmptyCell({required this.c, required this.hovering});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovering
            ? c.accent.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hovering ? c.accent : c.border.withValues(alpha: 0.5),
          width: hovering ? 2 : 1,
        ),
      ),
    );
  }
}

class _FilledCell extends StatelessWidget {
  final ThemeColors c;
  final _InvItem item;
  final bool hovering;
  final VoidCallback onTap;

  const _FilledCell({
    required this.c,
    required this.item,
    required this.hovering,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFurniture = item.kind == _ItemKind.furniture;
    final placeable = isFurniture && item.available > 0;
    return Tooltip(
      message: item.name,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hovering
                    ? c.accent
                    : (placeable
                        ? c.success.withValues(alpha: 0.30)
                        : const Color(0xFF252540)),
                width: hovering ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(child: _icon()),
                if (isFurniture)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: _QtyBadge(
                      qty: item.total,
                      color: placeable ? c.success : c.textLow,
                    ),
                  ),
                // Category tag for packs so walls/floors read apart.
                if (!isFurniture)
                  Positioned(
                    left: 3,
                    top: 3,
                    child: Text(
                      item.kind == _ItemKind.wallPack ? '🧱' : '🟫',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    if (item.kind == _ItemKind.furniture) {
      final f = item.furniture!;
      return furnitureSpriteMap[f.id] != null
          ? FurnitureSpriteIcon(itemId: f.id, scale: 3.5)
          : Text(f.type.icon, style: const TextStyle(fontSize: 20));
    }
    return _PackSwatch(colors: item.swatch);
  }
}

class _DragFeedback extends StatelessWidget {
  final ThemeColors c;
  final _InvItem item;
  final double size;

  const _DragFeedback({required this.c, required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(-size / 2, -size / 2),
      child: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: size,
            height: size,
            child: _FilledCell(
              c: c,
              item: item,
              hovering: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }
}

class _PackSwatch extends StatelessWidget {
  final List<Color> colors;

  const _PackSwatch({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF252540)),
      ),
      child: Column(
        children: [
          for (final color in colors) Expanded(child: ColoredBox(color: color)),
        ],
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  final int qty;
  final Color color;

  const _QtyBadge({required this.qty, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '×$qty',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
