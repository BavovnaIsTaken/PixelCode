/// Build Mode menu shell — replaces the legacy right-side rail+tray.
///
/// Two layouts driven by viewport width (`kBreakpoint = 768 dp`):
///  * **Wide** (desktop / tablet-landscape): NavigationRail on the left + a
///    280 dp scrollable content panel beside it.
///  * **Narrow** (mobile / tablet-portrait): bottom sheet 200 dp tall, with
///    a horizontal chip row across the top and the content list below.
///
/// Six sections: Rooms / Templates / Corridors / Walls / Floors / Decor.
/// Stage 1 shipped **Rooms**; Stage 2 added **Decor** (migrated from the
/// Shop's "Меблі" tab). Templates / Corridors / Walls / Floors still render
/// a "Скоро в Stage 2" placeholder so the IA stays honest about what's
/// available now and what's coming.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import 'build_decor_section.dart';
import 'build_menu_helpers.dart';
import 'office_game_state.dart';
import 'room_sprites.dart';
import 'room_themes.dart';

enum BuildSection { rooms, templates, corridors, walls, floors, decor }

extension BuildSectionDisplay on BuildSection {
  String get label => switch (this) {
        BuildSection.rooms => 'Кімнати',
        BuildSection.templates => 'Шаблони',
        BuildSection.corridors => 'Коридори',
        BuildSection.walls => 'Стіни',
        BuildSection.floors => 'Підлоги',
        BuildSection.decor => 'Декор',
      };

  IconData get icon => switch (this) {
        BuildSection.rooms => Icons.meeting_room_outlined,
        BuildSection.templates => Icons.auto_awesome_outlined,
        BuildSection.corridors => Icons.timeline_outlined,
        BuildSection.walls => Icons.crop_din_outlined,
        BuildSection.floors => Icons.grid_4x4_outlined,
        BuildSection.decor => Icons.local_florist_outlined,
      };

  /// Sections without Stage 1/2 content show a "coming soon" panel.
  /// Stage 2 added Templates and Decor; Walls/Floors/Corridors still pending.
  bool get isStage1Ready =>
      this == BuildSection.rooms ||
      this == BuildSection.decor ||
      this == BuildSection.templates ||
      this == BuildSection.corridors ||
      this == BuildSection.walls ||
      this == BuildSection.floors;
}

/// Viewport-width breakpoint that decides the layout. Note: this is the
/// SCREEN width, not the BuildMenu container width — the menu is mounted in
/// a 440dp side panel on desktop, so checking parent constraints would
/// always read narrow and we'd render the wrong form.
const double _kBreakpoint = 768;

class BuildMenu extends ConsumerWidget {
  const BuildMenu({super.key});

  // Public layout constants — agent_canvas reads these to allocate canvas space.
  static const double kRailWidth = 88;
  static const double kPanelWidth = 280;
  static const double kBottomSheetHeight = 200;
  static const double kBreakpoint = _kBreakpoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final economy = ref.watch(gameEconomyProvider);
    final mode = ref.watch(buildModeProvider);
    final isEditMode = ref.watch(furnitureEditModeProvider);
    // Static thumbnails — there's no animation worth the rebuild cost in a
    // 64×56 px card. The live canvas still animates at full fps.
    const tick = 0;

    final wide = MediaQuery.of(context).size.width >= _kBreakpoint;
    return wide
        ? _buildWide(context, ref, economy, mode, tick, isEditMode)
        : _buildNarrow(context, ref, economy, mode, tick, isEditMode);
  }

  // ─── Wide layout: rail + panel on the left ────────────────────────────────

  Widget _buildWide(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    int tick,
    bool isEditMode,
  ) {
    return Row(
      children: [
        SizedBox(
          width: kRailWidth,
          child: _buildRail(context, ref, mode, isEditMode),
        ),
        Expanded(
          child: _buildPanel(context, ref, economy, mode, tick),
        ),
      ],
    );
  }

  Widget _buildRail(
    BuildContext context,
    WidgetRef ref,
    BuildModeState mode,
    bool isEditMode,
  ) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          right: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            tooltip: 'Вийти',
            icon: Icon(Icons.close, color: c.textHigh),
            onPressed: () => ref.read(buildModeProvider.notifier).exit(),
          ),
          const SizedBox(height: 4),
          _SlidingRail(
            sections: BuildSection.values.toList(),
            active: mode.section,
            onSelect: (s) => ref.read(buildModeProvider.notifier).setSection(s),
          ),
          const Spacer(),
          IconButton(
            tooltip: isEditMode ? 'Вийти з редагування' : 'Видалити кімнати',
            icon: Icon(
              isEditMode ? Icons.edit_off : Icons.edit_outlined,
              color: isEditMode ? c.gold : c.textMedium,
            ),
            onPressed: () {
              final next = !ref.read(furnitureEditModeProvider);
              if (!next) {
                // Exiting edit mode: clear furniture placement selection.
                ref.read(selectedFurnitureIdProvider.notifier).state = null;
              } else {
                // Entering edit mode abandons any in-flight pick — can't
                // place and delete at the same time.
                ref.read(buildModeProvider.notifier).clearSelection();
              }
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    int tick,
  ) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          right: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader(context, economy, mode.section),
          Expanded(child: _sectionContent(context, ref, economy, mode, tick)),
        ],
      ),
    );
  }

  Widget _panelHeader(
    BuildContext context,
    GameState economy,
    BuildSection section,
  ) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            section.label,
            style: TextStyle(
              color: c.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 14,
            color: c.textMedium,
          ),
          const SizedBox(width: 4),
          Text(
            '₲${economy.grymni}',
            style: TextStyle(
              color: c.gold,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Narrow layout: bottom sheet with chip row ────────────────────────────

  Widget _buildNarrow(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    int tick,
    bool isEditMode,
  ) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Column(
        children: [
          _chipRow(context, ref, mode.section),
          Expanded(child: _sectionContent(context, ref, economy, mode, tick)),
        ],
      ),
    );
  }

  Widget _chipRow(BuildContext context, WidgetRef ref, BuildSection active) {
    final c = context.appColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Вийти',
            icon: Icon(Icons.close, color: c.textHigh, size: 20),
            onPressed: () => ref.read(buildModeProvider.notifier).exit(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in BuildSection.values) ...[
                  _sectionChip(context, ref, s, active),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip(
    BuildContext context,
    WidgetRef ref,
    BuildSection s,
    BuildSection active,
  ) {
    final c = context.appColors;
    final isActive = s == active;
    return ChoiceChip(
      label: Text(s.label),
      selected: isActive,
      onSelected: (_) => ref.read(buildModeProvider.notifier).setSection(s),
      avatar: Icon(s.icon, size: 16),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isActive ? c.background : c.textHigh,
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: c.surfaceDim,
      selectedColor: c.accent,
    );
  }

  // ─── Section content ──────────────────────────────────────────────────────

  Widget _sectionContent(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    int tick,
  ) {
    if (!mode.section.isStage1Ready) {
      return _comingSoonStub(context, mode.section);
    }
    if (mode.section == BuildSection.rooms) {
      return _roomsList(ref, economy, mode.selectedRoomType, tick);
    }
    if (mode.section == BuildSection.templates) {
      return _templatesList(ref, economy, mode.selectedTemplateId, tick);
    }
    if (mode.section == BuildSection.corridors) {
      return _corridorSection(context, ref, economy, mode);
    }
    if (mode.section == BuildSection.walls) {
      return _skinPackSection(
        context,
        ref,
        economy,
        mode.selectedPlacedRoomId,
        isWall: true,
      );
    }
    if (mode.section == BuildSection.floors) {
      return _skinPackSection(
        context,
        ref,
        economy,
        mode.selectedPlacedRoomId,
        isWall: false,
      );
    }
    if (mode.section == BuildSection.decor) {
      return const BuildDecorSection();
    }
    return const SizedBox.shrink();
  }

  Widget _corridorSection(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
  ) {
    final c = context.appColors;
    final notifier = ref.read(buildModeProvider.notifier);
    final hasAnchor = mode.corridorAnchorCol != null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Wide / Narrow toggle ──────────────────────────────────────────
        Text(
          'Тип коридору:',
          style: TextStyle(
              color: c.textLow, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _CorridorTypeChip(
                label: 'Вузький',
                subtitle: '₲50/тайл',
                icon: Icons.remove,
                selected: !mode.corridorWide,
                onTap: () {
                  if (mode.corridorWide) notifier.toggleCorridorWide();
                },
                colors: c,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CorridorTypeChip(
                label: 'Широкий',
                subtitle: '₲90/тайл  +3% швид.',
                icon: Icons.remove_road,
                selected: mode.corridorWide,
                onTap: () {
                  if (!mode.corridorWide) notifier.toggleCorridorWide();
                },
                colors: c,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ── Placement instructions / status ───────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: hasAnchor
              ? _CorridorStatus(
                  key: const ValueKey('anchor-set'),
                  icon: Icons.adjust,
                  color: c.gold,
                  title: 'Якір встановлено',
                  subtitle:
                      '(${mode.corridorAnchorCol}, ${mode.corridorAnchorRow}) → натисніть другу точку на канвасі',
                  trailing: TextButton(
                    onPressed: notifier.clearCorridorAnchor,
                    child: Text('Скасувати',
                        style: TextStyle(color: c.error, fontSize: 11)),
                  ),
                  colors: c,
                )
              : _CorridorStatus(
                  key: const ValueKey('no-anchor'),
                  icon: Icons.touch_app_outlined,
                  color: c.textMedium,
                  title: 'Крок 1',
                  subtitle: 'Натисніть першу точку на канвасі щоб встановити якір',
                  trailing: null,
                  colors: c,
                ),
        ),
        const SizedBox(height: 8),
        if (!hasAnchor)
          _CorridorStatus(
            icon: Icons.place_outlined,
            color: c.textMedium,
            title: 'Крок 2',
            subtitle: 'Натисніть другу точку — коридор відмалюється автоматично (Г-форма)',
            trailing: null,
            colors: c,
          ),
        const SizedBox(height: 16),
        // ── Placed corridors ─────────────────────────────────────────────
        if (economy.placedCorridors.isNotEmpty) ...[
          Text(
            'Розміщені коридори:',
            style: TextStyle(
                color: c.textLow, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final corridor in economy.placedCorridors)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surfaceDim,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      corridor.wide
                          ? Icons.remove_road
                          : Icons.remove,
                      size: 14,
                      color: c.textMedium,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            corridor.wide ? 'Широкий' : 'Вузький',
                            style: TextStyle(
                              color: c.textHigh,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${corridor.tiles.length} тайлів',
                            style: TextStyle(
                              color: c.textLow,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        ref.read(gameEconomyProvider.notifier).removeCorridor(corridor.id);
                      },
                      icon: Icon(Icons.delete_outline, color: c.error, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Видалити (50% повернення)',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        // ── Balance hint ─────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 13, color: c.textLow),
            const SizedBox(width: 4),
            Text(
              'Баланс: ₲${economy.grymni}',
              style: TextStyle(color: c.textLow, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _skinPackSection(
    BuildContext context,
    WidgetRef ref,
    GameState economy,
    String? selectedRoomId, {
    required bool isWall,
  }) {
    final c = context.appColors;
    final notifier = ref.read(gameEconomyProvider.notifier);
    final ownedIds =
        isWall ? economy.ownedWallSkinPacks : economy.ownedFloorSkinPacks;

    final selectedRoom = selectedRoomId != null
        ? economy.placedRooms
            .where((r) => r.id == selectedRoomId)
            .firstOrNull
        : null;
    final activeSkinId = isWall
        ? (selectedRoom?.wallSkinId ?? kWallSkinFreeId)
        : (selectedRoom?.floorSkinId ?? kFloorSkinFreeId);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (economy.placedRooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Спочатку розмістіть кімнату на канвасі.',
              style: TextStyle(color: c.textLow, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          Text(
            'Вибрати кімнату:',
            style: TextStyle(
                color: c.textLow, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final room in economy.placedRooms)
                GestureDetector(
                  onTap: () => ref
                      .read(buildModeProvider.notifier)
                      .selectPlacedRoom(room.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: room.id == selectedRoomId
                          ? c.accent.withValues(alpha: 0.25)
                          : c.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: room.id == selectedRoomId
                            ? c.accent
                            : c.border,
                      ),
                    ),
                    child: Text(
                      room.type.nameUk,
                      style: TextStyle(
                        color: room.id == selectedRoomId
                            ? c.accent
                            : c.textHigh,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (selectedRoom != null) ...[
            Text(
              isWall ? 'Оздоблення стін:' : 'Покриття підлоги:',
              style: TextStyle(
                  color: c.textLow,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (isWall)
              for (final pack in wallSkinPackCatalog)
                _SkinPackCard(
                  packId: pack.id,
                  packName: pack.name,
                  packDescription: pack.description,
                  packCost: pack.cost,
                  previewColors: [
                    Color(pack.wallBase),
                    Color(pack.wallTop),
                    Color(pack.wallInner),
                  ],
                  isOwned: pack.cost == 0 || ownedIds.contains(pack.id),
                  isActive: pack.id == activeSkinId,
                  economy: economy,
                  onBuy: () => notifier.purchaseWallSkinPack(pack),
                  onApply: () =>
                      notifier.applyRoomWallSkin(selectedRoom.id, pack.id),
                )
            else
              for (final pack in floorSkinPackCatalog)
                _SkinPackCard(
                  packId: pack.id,
                  packName: pack.name,
                  packDescription: pack.description,
                  packCost: pack.cost,
                  previewColors: [
                    Color(pack.floorDark),
                    Color(pack.floorLight),
                    Color(pack.floorGrid),
                  ],
                  isOwned: pack.cost == 0 || ownedIds.contains(pack.id),
                  isActive: pack.id == activeSkinId,
                  economy: economy,
                  onBuy: () => notifier.purchaseFloorSkinPack(pack),
                  onApply: () =>
                      notifier.applyRoomFloorSkin(selectedRoom.id, pack.id),
                ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Виберіть кімнату вище щоб застосувати скін.',
                style: TextStyle(color: c.textLow, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }

  Widget _templatesList(
    WidgetRef ref,
    GameState economy,
    String? selectedTemplateId,
    int tick,
  ) {
    final available = roomTemplateCatalog
        .where((t) => _isRoomAvailable(t.baseRoom, economy))
        .toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: available.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TemplateCard(
        template: available[i],
        economy: economy,
        tick: tick,
        isSelected: selectedTemplateId == available[i].id,
        onTap: () =>
            ref.read(buildModeProvider.notifier).toggleTemplate(available[i]),
      ),
    );
  }

  Widget _comingSoonStub(BuildContext context, BuildSection section) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 40, color: c.textLow),
            const SizedBox(height: 12),
            Text(
              '${section.label} — скоро',
              style: TextStyle(
                color: c.textHigh,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Прийде у Stage 2 разом з шаблонами кімнат, коридорами і пакетами стін/підлог.',
              style: TextStyle(
                color: c.textMedium,
                fontSize: 11,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomsList(
    WidgetRef ref,
    GameState economy,
    RoomType? selectedRoomType,
    int tick,
  ) {
    final available = RoomType.values
        .where((rt) => _isRoomAvailable(rt, economy))
        .toList();
    // Rooms first (enclosed units), then Zones (open feature areas) — so the
    // user scans walls-with-doors before luxury venues.
    final rooms =
        available.where((rt) => rt.category == RoomCategory.room).toList();
    final zones =
        available.where((rt) => rt.category == RoomCategory.zone).toList();

    final items = <Widget>[];
    if (rooms.isNotEmpty) {
      items.add(const _SectionLabel(label: 'Кімнати'));
      for (final rt in rooms) {
        items.add(_RoomCard(
          type: rt,
          economy: economy,
          tick: tick,
          isSelected: selectedRoomType == rt,
          onTap: () => ref.read(buildModeProvider.notifier).toggleRoom(rt),
        ));
      }
    }
    if (zones.isNotEmpty) {
      items.add(const SizedBox(height: 4));
      items.add(const _SectionLabel(label: 'Зони'));
      for (final rt in zones) {
        items.add(_RoomCard(
          type: rt,
          economy: economy,
          tick: tick,
          isSelected: selectedRoomType == rt,
          onTap: () => ref.read(buildModeProvider.notifier).toggleRoom(rt),
        ));
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => items[i],
    );
  }

  bool _isRoomAvailable(RoomType type, GameState game) =>
      isRoomAvailableForTier(type, game.officeLevel);
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.textLow,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}


// ─── Room card ───────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final RoomType type;
  final GameState economy;
  final int tick;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoomCard({
    required this.type,
    required this.economy,
    required this.tick,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final canAfford = economy.grymni >= type.cost;
    final placedCount = economy.placedRooms.where((r) => r.type == type).length;
    final atCap = placedCount >= type.maxPerOffice;
    final available = canAfford && !atCap;

    // Pixel-art preview keeps using the room theme — the preview *is* a
    // room, and rooms inherit their colors from the office tier.
    final roomTheme = roomThemeForLevel(economy.officeLevel);

    // Selection accent: theme accent for compact rooms, gold for luxury so
    // the "this is the special tier" signal still reads at a glance even
    // when the player swaps the UI theme.
    final selectionColor = type.isLuxury ? c.gold : c.accent;

    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: available ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? selectionColor : c.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Live pixel preview — same drawRoom the painter uses.
              SizedBox(
                width: 64,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    painter: _RoomPreviewPainter(
                      type: type,
                      theme: roomTheme,
                      tick: tick,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${type.icon} ${type.nameUk}',
                            style: TextStyle(
                              color: c.textHigh,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (type.category == RoomCategory.zone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: c.gold.withValues(alpha: 0.5),
                                  width: 0.6),
                            ),
                            child: Text(
                              'Зона',
                              style: TextStyle(
                                color: c.gold,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${type.widthTiles}×${type.heightTiles}'
                      ' · до ${type.maxPerOffice} шт.',
                      style: TextStyle(color: c.textLow, fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₲${type.cost}',
                          style: TextStyle(
                            color: canAfford ? c.gold : c.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (atCap) ...[
                          const SizedBox(width: 6),
                          Text(
                            'досягнуто ліміт',
                            style: TextStyle(
                              color: c.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    // Scale the room sprite to fit the preview box. Keep aspect ratio so
    // luxury rooms (which are wider) read at a smaller pixel scale rather
    // than getting squashed.
    final rw = (type.widthTiles * kTileSize).toDouble();
    final rh = (type.heightTiles * kTileSize).toDouble();
    final scale = math.min(size.width / rw, size.height / rh);
    final dx = (size.width - rw * scale) / 2;
    final dy = (size.height - rh * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    // drawRoom anchors at room.col/row * kTileSize — we feed col=0/row=0 so
    // the sprite renders at origin, then the canvas transform places it.
    drawRoom(
      canvas,
      PlacedRoom(id: '_preview_${type.index}', type: type, col: 0, row: 0),
      theme,
      tick,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RoomPreviewPainter old) =>
      old.type != type || old.theme != theme || old.tick != tick;
}


// ─── Template card ──────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final RoomTemplate template;
  final GameState economy;
  final int tick;
  final bool isSelected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.economy,
    required this.tick,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final raw = template.rawCost(furnitureCatalog);
    final bundle = template.bundleCost(furnitureCatalog);
    final saved = raw - bundle;
    final canAfford = economy.grymni >= bundle;
    final placedCount =
        economy.placedRooms.where((r) => r.type == template.baseRoom).length;
    final atCap = placedCount >= template.baseRoom.maxPerOffice;
    final available = canAfford && !atCap;
    final roomTheme = roomThemeForLevel(economy.officeLevel);

    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: available ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? c.accent : c.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CustomPaint(
                        painter: _RoomPreviewPainter(
                          type: template.baseRoom,
                          theme: roomTheme,
                          tick: tick,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${template.baseRoom.icon} ${template.name}',
                          style: TextStyle(
                            color: c.textHigh,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          template.description,
                          style: TextStyle(color: c.textMedium, fontSize: 10),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Меблів: ${template.furniture.length} · '
                          'до ${template.baseRoom.maxPerOffice} шт.',
                          style: TextStyle(color: c.textLow, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Pricing breakdown — base + furniture − bundle discount.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'База ₲${template.baseRoom.cost} + меблі '
                        '₲${raw - template.baseRoom.cost} − ${template.discountPercent}%',
                        style: TextStyle(color: c.textMedium, fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₲$bundle',
                      style: TextStyle(
                        color: canAfford ? c.gold : c.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (saved > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: c.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '−₲$saved',
                          style: TextStyle(
                            color: c.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (atCap) ...[
                const SizedBox(height: 4),
                Text(
                  'Досягнуто ліміту базової кімнати',
                  style: TextStyle(
                    color: c.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Skin pack card ──────────────────────────────────────────────────────────

class _SkinPackCard extends StatelessWidget {
  const _SkinPackCard({
    required this.packId,
    required this.packName,
    required this.packDescription,
    required this.packCost,
    required this.previewColors,
    required this.isOwned,
    required this.isActive,
    required this.economy,
    required this.onBuy,
    required this.onApply,
  });

  final String packId;
  final String packName;
  final String packDescription;
  final int packCost;
  final List<Color> previewColors;
  final bool isOwned;
  final bool isActive;
  final GameState economy;
  final VoidCallback onBuy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final canAfford = economy.grymni >= packCost;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isActive
              ? c.accent.withValues(alpha: 0.12)
              : c.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? c.accent : c.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Color swatch preview — 3 stacked rects
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Column(
                    children: [
                      for (final col in previewColors)
                        Expanded(
                          child: Container(color: col),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      packName,
                      style: TextStyle(
                        color: c.textHigh,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      packDescription,
                      style: TextStyle(color: c.textLow, fontSize: 9),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action button
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Активно',
                    style: TextStyle(
                        color: c.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700),
                  ),
                )
              else if (isOwned)
                GestureDetector(
                  onTap: onApply,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Застосувати',
                      style: TextStyle(
                          color: c.background,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: canAfford ? onBuy : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: canAfford
                          ? c.gold.withValues(alpha: 0.15)
                          : c.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: canAfford ? c.gold : c.border,
                      ),
                    ),
                    child: Text(
                      '₲$packCost',
                      style: TextStyle(
                        color: canAfford ? c.gold : c.textLow,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
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
}

// ─── Corridor type chip ──────────────────────────────────────────────────────

class _CorridorTypeChip extends StatelessWidget {
  const _CorridorTypeChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.accent.withValues(alpha: 0.18)
              : c.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c.accent : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: selected ? c.accent : c.textMedium),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? c.accent : c.textHigh,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: c.textLow, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Corridor status row ─────────────────────────────────────────────────────

class _CorridorStatus extends StatelessWidget {
  const _CorridorStatus({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.colors,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final ThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textHigh,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: c.textLow, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ─── Rail slider ─────────────────────────────────────────────────────────────

// Each tile occupies exactly this many logical pixels vertically (64 height +
// 2 top margin + 2 bottom margin). The indicator uses this to compute its
// AnimatedPositioned target without needing GlobalKeys or RenderBox lookups.
const double _kTileSlotH = 68.0;
const double _kTileH = 64.0;
const double _kTileHMargin = 4.0;

class _SlidingRail extends StatelessWidget {
  final List<BuildSection> sections;
  final BuildSection active;
  final ValueChanged<BuildSection> onSelect;

  const _SlidingRail({
    required this.sections,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final idx = sections.indexOf(active).clamp(0, sections.length - 1);

    return SizedBox(
      height: sections.length * _kTileSlotH,
      child: Stack(
        children: [
          // Sliding indicator — animates to the active section's position.
          // AnimatedPositioned simply updates its target on every rebuild;
          // rapid taps only change the destination, never break the tween.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            top: idx * _kTileSlotH + 2,
            left: _kTileHMargin,
            right: _kTileHMargin,
            height: _kTileH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.accent, width: 1),
              ),
            ),
          ),
          Column(
            children: [
              for (final s in sections)
                _RailTile(
                  section: s,
                  isActive: s == active,
                  onTap: () => onSelect(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  final BuildSection section;
  final bool isActive;
  final VoidCallback onTap;

  const _RailTile({
    required this.section,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _kTileH,
        margin: const EdgeInsets.symmetric(
          horizontal: _kTileHMargin,
          vertical: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              section.icon,
              color: isActive ? c.accent : c.textMedium,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              section.label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? c.accent : c.textMedium,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
