/// Right-side collapsible rail for Build Mode.
///
/// Two-stage reveal: the narrow rail on the right shows category tiles
/// (Presets / Compact / Luxury) + an exit button. Tapping a category slides
/// a horizontal card tray out of the bottom-left. Cards render a live pixel
/// preview of the actual room via [drawRoom] so the picker looks like the
/// thing you're buying, not a CSV row.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import 'office_game_state.dart';
import 'room_sprites.dart';
import 'room_themes.dart';

enum BuildCategory { presets, compact, luxury }

class BuildPickerRail extends StatelessWidget {
  final GameState economy;
  final RoomType? selectedRoomType;
  final OfficePreset? selectedPreset;
  final BuildCategory? activeCategory;
  final int tick;
  final bool showConfirmHint;
  final bool isEditMode;

  final ValueChanged<BuildCategory?> onCategoryTap;
  final ValueChanged<RoomType> onSelectRoom;
  final ValueChanged<OfficePreset> onSelectPreset;
  final VoidCallback onExit;
  final VoidCallback onToggleEdit;

  const BuildPickerRail({
    super.key,
    required this.economy,
    required this.selectedRoomType,
    required this.selectedPreset,
    required this.activeCategory,
    required this.tick,
    required this.showConfirmHint,
    required this.isEditMode,
    required this.onCategoryTap,
    required this.onSelectRoom,
    required this.onSelectPreset,
    required this.onExit,
    required this.onToggleEdit,
  });

  static const double kRailWidth = 64;
  static const double kTrayHeight = 138;
  static const _luxuryGold = Color(0xFFFFD700);
  static const _affordGreen = Color(0xFF44FF88);
  static const _invalidRed = Color(0xFFFF5A5A);

  /// Panel background blended from the current room theme so the build UI
  /// picks up the office vibe (gloomy brown in the garage, navy in modern,
  /// teal in tech hub, etc.).
  Color get _panelBg {
    final theme = roomThemeForLevel(economy.officeLevel);
    return Color.alphaBlend(
      theme.wallInner.withValues(alpha: 0.92),
      const Color(0xFF050508),
    );
  }

  bool get _isGarage => economy.officeLevel == OfficeLevel.garage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tray slides up when a category is active.
        Positioned(
          left: 0,
          right: kRailWidth,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: activeCategory == null
                ? const SizedBox(key: ValueKey('no-tray'))
                : _buildTray(context),
          ),
        ),

        // The rail itself.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: kRailWidth,
          child: _buildRail(),
        ),
      ],
    );
  }

  // ─── Rail (vertical strip) ────────────────────────────────────────────────

  Widget _buildRail() {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        border: const Border(
          left: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailHeader(
            isEditMode: isEditMode,
            onTap: onToggleEdit,
          ),
          const SizedBox(height: 8),
          _RailCategoryTile(
            icon: Icons.inventory_2_outlined,
            label: 'Набори',
            active: activeCategory == BuildCategory.presets,
            accent: _luxuryGold,
            onTap: () => onCategoryTap(
              activeCategory == BuildCategory.presets
                  ? null
                  : BuildCategory.presets,
            ),
          ),
          _RailCategoryTile(
            icon: Icons.view_module_outlined,
            label: 'Кімнати',
            active: activeCategory == BuildCategory.compact,
            accent: _affordGreen,
            onTap: () => onCategoryTap(
              activeCategory == BuildCategory.compact
                  ? null
                  : BuildCategory.compact,
            ),
          ),
          if (!_isGarage)
            _RailCategoryTile(
              icon: Icons.diamond_outlined,
              label: 'Преміум',
              active: activeCategory == BuildCategory.luxury,
              accent: const Color(0xFFE85DC6),
              onTap: () => onCategoryTap(
                activeCategory == BuildCategory.luxury
                    ? null
                    : BuildCategory.luxury,
              ),
            ),
          const Spacer(),
          _RailExitTile(onTap: onExit),
        ],
      ),
    );
  }

  // ─── Tray (horizontal card strip) ─────────────────────────────────────────

  Widget _buildTray(BuildContext context) {
    final theme = roomThemeForLevel(economy.officeLevel);
    final cat = activeCategory!;

    final List<Widget> cards;
    if (cat == BuildCategory.presets) {
      final presets = _isGarage
          ? officePresetCatalog.where((p) => !p.hasLuxury).toList()
          : officePresetCatalog;
      cards = [
        for (final preset in presets)
          _PresetCard(
            preset: preset,
            economy: economy,
            theme: theme,
            tick: tick,
            isSelected: selectedPreset?.id == preset.id,
            onTap: () => onSelectPreset(preset),
          ),
      ];
    } else {
      final wantLuxury = cat == BuildCategory.luxury;
      final rooms = RoomType.values
          .where((r) => r.isLuxury == wantLuxury)
          .where((r) => !_isGarage || !r.isLuxury)
          .toList();
      cards = [
        for (final rt in rooms)
          _RoomCard(
            type: rt,
            economy: economy,
            theme: theme,
            tick: tick,
            isSelected: selectedRoomType == rt,
            onTap: () => onSelectRoom(rt),
          ),
      ];
    }

    return Container(
      key: ValueKey('tray-$cat'),
      height: kTrayHeight,
      decoration: BoxDecoration(
        color: _panelBg,
        border: const Border(
          top: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 14,
            child: Row(
              children: [
                Text(
                  _categoryLabel(cat),
                  style: const TextStyle(
                    color: Color(0xFFB0B0C0),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showConfirmHint) ...[
                  const SizedBox(width: 10),
                  const Text(
                    '• Тапніть у офісі ще раз, щоб підтвердити',
                    style: TextStyle(
                      color: _luxuryGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cards,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(BuildCategory c) {
    switch (c) {
      case BuildCategory.presets:
        return 'НАБОРИ';
      case BuildCategory.compact:
        return 'КОМПАКТНІ КІМНАТИ';
      case BuildCategory.luxury:
        return 'ПРЕМІУМ';
    }
  }
}

// ─── Rail chrome ────────────────────────────────────────────────────────────

class _RailHeader extends StatelessWidget {
  final bool isEditMode;
  final VoidCallback onTap;

  const _RailHeader({required this.isEditMode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFFB84A);
    const idleColor = Color(0xFF44FF88);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isEditMode
              ? activeColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEditMode
                ? activeColor.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.08),
            width: isEditMode ? 1.2 : 0.6,
          ),
        ),
        child: Icon(
          Icons.build_rounded,
          color: isEditMode ? activeColor : idleColor,
          size: 18,
        ),
      ),
    );
  }
}

class _RailCategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _RailCategoryTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.08),
            width: active ? 1.2 : 0.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? accent : Colors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? accent : Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailExitTile extends StatelessWidget {
  final VoidCallback onTap;
  const _RailExitTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 18, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(height: 2),
            Text(
              'Вихід',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cards ──────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final RoomType type;
  final GameState economy;
  final RoomTheme theme;
  final int tick;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoomCard({
    required this.type,
    required this.economy,
    required this.theme,
    required this.tick,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canAfford = economy.grymni >= type.cost;
    final capHit = economy.placedRooms.where((r) => r.type == type).length >=
        type.maxPerOffice;
    final fitsInGrid = type.widthTiles <= economy.gridCols - 2 &&
        type.heightTiles <= economy.gridRows - 2;
    final available = canAfford && !capHit && fitsInGrid;

    final accent =
        type.isLuxury ? const Color(0xFFE85DC6) : BuildPickerRail._affordGreen;

    return _BaseCard(
      width: 108,
      isSelected: isSelected,
      available: available,
      selectedAccent: accent,
      luxuryFrame: type.isLuxury,
      onTap: available ? onTap : null,
      child: Column(
        children: [
          Expanded(
            child: _RoomPreview(
              type: type,
              theme: theme,
              tick: tick,
              desaturate: !available,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            type.nameUk,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: available
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          _CostPill(
            text: !fitsInGrid
                ? 'Замало місця'
                : capHit
                    ? 'Ліміт'
                    : '₲${type.cost}',
            subtext: available ? '${type.widthTiles}×${type.heightTiles}' : null,
            available: available,
            locked: !canAfford && fitsInGrid && !capHit,
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final OfficePreset preset;
  final GameState economy;
  final RoomTheme theme;
  final int tick;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.economy,
    required this.theme,
    required this.tick,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canAfford = economy.grymni >= preset.totalCost;

    final addedByType = <RoomType, int>{};
    for (final slot in preset.rooms) {
      addedByType[slot.type] = (addedByType[slot.type] ?? 0) + 1;
    }
    var capHit = false;
    for (final entry in addedByType.entries) {
      final existing =
          economy.placedRooms.where((r) => r.type == entry.key).length;
      if (existing + entry.value > entry.key.maxPerOffice) {
        capHit = true;
        break;
      }
    }

    final fitsInGrid = preset.widthTiles <= economy.gridCols - 2 &&
        preset.heightTiles <= economy.gridRows - 2;
    final available = canAfford && !capHit && fitsInGrid;

    return _BaseCard(
      width: 160,
      isSelected: isSelected,
      available: available,
      selectedAccent: BuildPickerRail._luxuryGold,
      luxuryFrame: preset.hasLuxury,
      onTap: available ? onTap : null,
      ribbon: '×${preset.rooms.length}',
      ribbonColor: const Color(0xFFB87333),
      child: Column(
        children: [
          Expanded(
            child: _PresetPreview(
              preset: preset,
              theme: theme,
              tick: tick,
              desaturate: !available,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: available
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          _CostPill(
            text: !fitsInGrid
                ? 'Замало місця'
                : capHit
                    ? 'Ліміт'
                    : '₲${preset.totalCost}',
            subtext: available && preset.discountPercent > 0
                ? '-${preset.discountPercent}%'
                : null,
            subtextColor: const Color(0xFF44FF88),
            available: available,
            locked: !canAfford && fitsInGrid && !capHit,
          ),
        ],
      ),
    );
  }
}

// ─── Base card chrome ───────────────────────────────────────────────────────

class _BaseCard extends StatelessWidget {
  final double width;
  final bool isSelected;
  final bool available;
  final Color selectedAccent;
  final bool luxuryFrame;
  final VoidCallback? onTap;
  final Widget child;
  final String? ribbon;
  final Color? ribbonColor;

  const _BaseCard({
    required this.width,
    required this.isSelected,
    required this.available,
    required this.selectedAccent,
    required this.luxuryFrame,
    required this.onTap,
    required this.child,
    this.ribbon,
    this.ribbonColor,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? selectedAccent
        : luxuryFrame
            ? const Color(0xFFFFD700).withValues(alpha: available ? 0.55 : 0.2)
            : Colors.white.withValues(alpha: available ? 0.12 : 0.05);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedAccent.withValues(alpha: 0.10)
              : const Color(0xFF14141C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.6 : (luxuryFrame ? 1.2 : 1),
          ),
        ),
        child: Stack(
          children: [
            child,
            if (ribbon != null)
              Positioned(
                top: -2,
                left: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: ribbonColor ?? const Color(0xFFB87333),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(
                    ribbon!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CostPill extends StatelessWidget {
  final String text;
  final String? subtext;
  final Color? subtextColor;
  final bool available;
  final bool locked;

  const _CostPill({
    required this.text,
    required this.available,
    required this.locked,
    this.subtext,
    this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = !available
        ? (locked
            ? BuildPickerRail._invalidRed
            : Colors.white.withValues(alpha: 0.4))
        : BuildPickerRail._affordGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A0F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            Icon(Icons.lock, size: 9, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtext != null) ...[
            const SizedBox(width: 4),
            Text(
              subtext!,
              style: TextStyle(
                color: subtextColor ?? Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Room preview (single room) ─────────────────────────────────────────────

class _RoomPreview extends StatelessWidget {
  final RoomType type;
  final RoomTheme theme;
  final int tick;
  final bool desaturate;

  const _RoomPreview({
    required this.type,
    required this.theme,
    required this.tick,
    required this.desaturate,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _RoomPreviewPainter(
      type: type,
      theme: theme,
      tick: tick,
    );
    Widget canvas = CustomPaint(painter: painter, size: Size.infinite);
    if (desaturate) {
      canvas = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]),
        child: canvas,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        color: theme.floorDark,
        child: canvas,
      ),
    );
  }
}

class _RoomPreviewPainter extends CustomPainter {
  final RoomType type;
  final RoomTheme theme;
  final int tick;

  _RoomPreviewPainter({
    required this.type,
    required this.theme,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final roomW = type.widthTiles * kTileSize;
    final roomH = type.heightTiles * kTileSize;
    final scale =
        (size.width / roomW).clamp(0.0, size.height / roomH).toDouble();
    final drawW = roomW * scale;
    final drawH = roomH * scale;
    canvas.save();
    canvas.translate(
      (size.width - drawW) / 2,
      (size.height - drawH) / 2,
    );
    canvas.scale(scale);
    drawRoom(
      canvas,
      PlacedRoom(id: 'preview', type: type, col: 0, row: 0),
      theme,
      tick,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoomPreviewPainter old) =>
      old.type != type || old.tick != tick || old.theme != theme;
}

// ─── Preset preview (all component rooms) ───────────────────────────────────

class _PresetPreview extends StatelessWidget {
  final OfficePreset preset;
  final RoomTheme theme;
  final int tick;
  final bool desaturate;

  const _PresetPreview({
    required this.preset,
    required this.theme,
    required this.tick,
    required this.desaturate,
  });

  @override
  Widget build(BuildContext context) {
    Widget canvas = CustomPaint(
      painter: _PresetPreviewPainter(
        preset: preset,
        theme: theme,
        tick: tick,
      ),
      size: Size.infinite,
    );
    if (desaturate) {
      canvas = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]),
        child: canvas,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        color: theme.floorDark,
        child: canvas,
      ),
    );
  }
}

class _PresetPreviewPainter extends CustomPainter {
  final OfficePreset preset;
  final RoomTheme theme;
  final int tick;

  _PresetPreviewPainter({
    required this.preset,
    required this.theme,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final footW = preset.widthTiles * kTileSize;
    final footH = preset.heightTiles * kTileSize;
    final scale =
        (size.width / footW).clamp(0.0, size.height / footH).toDouble();
    final drawW = footW * scale;
    final drawH = footH * scale;
    canvas.save();
    canvas.translate(
      (size.width - drawW) / 2,
      (size.height - drawH) / 2,
    );
    canvas.scale(scale);
    for (final slot in preset.rooms) {
      drawRoom(
        canvas,
        PlacedRoom(
          id: 'preview-${slot.type.name}-${slot.colOffset}-${slot.rowOffset}',
          type: slot.type,
          col: slot.colOffset,
          row: slot.rowOffset,
        ),
        theme,
        tick,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PresetPreviewPainter old) =>
      old.preset.id != preset.id || old.tick != tick || old.theme != theme;
}
