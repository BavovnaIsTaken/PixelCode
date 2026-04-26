/// Build Mode menu shell — replaces the legacy right-side rail+tray.
///
/// Two layouts driven by viewport width (`kBreakpoint = 768 dp`):
///  * **Wide** (desktop / tablet-landscape): NavigationRail on the left + a
///    280 dp scrollable content panel beside it.
///  * **Narrow** (mobile / tablet-portrait): bottom sheet 200 dp tall, with
///    a horizontal chip row across the top and the content list below.
///
/// Six sections: Rooms / Templates / Corridors / Walls / Floors / Decor.
/// Stage 1 ships meaningful content only for **Rooms**; the other sections
/// render a "Скоро в Stage 2" placeholder so the navigation IA is honest
/// about what's available now and what's coming.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
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

  /// Sections without Stage 1 content show a "coming soon" panel.
  bool get isStage1Ready => this == BuildSection.rooms;
}

/// Width breakpoint between bottom-sheet and rail layouts.
const double _kBreakpoint = 768;

/// Tick provider — small private signal that drives the room-card preview
/// animation cycles. Rebuilt every ~120 ms so subtle "alive" flickers in
/// the preview sprites tick along.
final _previewTickProvider = StreamProvider<int>((ref) async* {
  var i = 0;
  while (true) {
    yield i++;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
});

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
    final tick = ref.watch(_previewTickProvider).value ?? 0;
    final isEditMode = ref.watch(furnitureEditModeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kBreakpoint;
        return wide
            ? _buildWide(context, ref, economy, mode, tick, isEditMode)
            : _buildNarrow(context, ref, economy, mode, tick, isEditMode);
      },
    );
  }

  Color _panelBg(GameState economy) {
    final theme = roomThemeForLevel(economy.officeLevel);
    return Color.alphaBlend(
      theme.wallInner.withValues(alpha: 0.92),
      const Color(0xFF050508),
    );
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
          child: _buildRail(ref, economy, mode, isEditMode),
        ),
        Expanded(
          child: _buildPanel(context, ref, economy, mode, tick),
        ),
      ],
    );
  }

  Widget _buildRail(
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    bool isEditMode,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg(economy),
        border: const Border(
          right: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            tooltip: 'Вийти',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => ref.read(buildModeProvider.notifier).exit(),
          ),
          const SizedBox(height: 4),
          for (final s in BuildSection.values) _railTile(ref, s, mode.section),
          const Spacer(),
          IconButton(
            tooltip: isEditMode ? 'Вийти з редагування' : 'Видалити кімнати',
            icon: Icon(
              isEditMode ? Icons.edit_off : Icons.edit_outlined,
              color: isEditMode
                  ? const Color(0xFFFFD700)
                  : Colors.white.withValues(alpha: 0.7),
            ),
            onPressed: () {
              final next = !ref.read(furnitureEditModeProvider);
              ref.read(furnitureEditModeProvider.notifier).state = next;
              if (next) {
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

  Widget _railTile(WidgetRef ref, BuildSection s, BuildSection active) {
    final isActive = s == active;
    return InkWell(
      onTap: () => ref.read(buildModeProvider.notifier).setSection(s),
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: const Color(0xFF00C0D1), width: 1)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              s.icon,
              color: isActive
                  ? const Color(0xFF00C0D1)
                  : Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              s.label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? const Color(0xFF00C0D1)
                    : Colors.white.withValues(alpha: 0.7),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
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
    return Container(
      decoration: BoxDecoration(
        color: _panelBg(economy),
        border: const Border(
          right: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader(economy, mode.section),
          Expanded(child: _sectionContent(ref, economy, mode, tick)),
        ],
      ),
    );
  }

  Widget _panelHeader(GameState economy, BuildSection section) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            section.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 4),
          Text(
            '₲${economy.grymni}',
            style: const TextStyle(
              color: Color(0xFFFFD700),
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
    return Container(
      decoration: BoxDecoration(
        color: _panelBg(economy),
        border: const Border(
          top: BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      child: Column(
        children: [
          _chipRow(ref, mode.section),
          Expanded(child: _sectionContent(ref, economy, mode, tick)),
        ],
      ),
    );
  }

  Widget _chipRow(WidgetRef ref, BuildSection active) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Вийти',
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
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
                  _sectionChip(ref, s, active),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip(WidgetRef ref, BuildSection s, BuildSection active) {
    final isActive = s == active;
    return ChoiceChip(
      label: Text(s.label),
      selected: isActive,
      onSelected: (_) => ref.read(buildModeProvider.notifier).setSection(s),
      avatar: Icon(s.icon, size: 16),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isActive ? Colors.black : Colors.white.withValues(alpha: 0.85),
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      selectedColor: const Color(0xFF00C0D1),
    );
  }

  // ─── Section content ──────────────────────────────────────────────────────

  Widget _sectionContent(
    WidgetRef ref,
    GameState economy,
    BuildModeState mode,
    int tick,
  ) {
    if (!mode.section.isStage1Ready) return _comingSoonStub(mode.section);
    if (mode.section == BuildSection.rooms) {
      return _roomsList(ref, economy, mode.selectedRoomType, tick);
    }
    return const SizedBox.shrink();
  }

  Widget _comingSoonStub(BuildSection section) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              section.icon,
              size: 40,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              '${section.label} — скоро',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Прийде у Stage 2 разом з шаблонами кімнат, коридорами і пакетами стін/підлог.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
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
    final rooms = RoomType.values
        .where((rt) => _isRoomAvailable(rt, economy))
        .toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _RoomCard(
        type: rooms[i],
        economy: economy,
        tick: tick,
        isSelected: selectedRoomType == rooms[i],
        onTap: () =>
            ref.read(buildModeProvider.notifier).toggleRoom(rooms[i]),
      ),
    );
  }

  bool _isRoomAvailable(RoomType type, GameState game) {
    // Hide luxury rooms in the garage tier; they don't fit anyway and seeing
    // them locked is more clutter than aspiration at the smallest grid.
    if (type.isLuxury && game.officeLevel == OfficeLevel.garage) return false;
    return true;
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
    final canAfford = economy.grymni >= type.cost;
    final placedCount = economy.placedRooms.where((r) => r.type == type).length;
    final atCap = placedCount >= type.maxPerOffice;
    final available = canAfford && !atCap;

    final theme = roomThemeForLevel(economy.officeLevel);
    final accentColor = type.isLuxury
        ? const Color(0xFFE85DC6)
        : const Color(0xFF44FF88);

    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: available ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A14).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? accentColor : const Color(0x22FFFFFF),
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
                      theme: theme,
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
                      '${type.icon} ${type.nameUk}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${type.widthTiles}×${type.heightTiles}'
                      ' · до ${type.maxPerOffice} шт.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₲${type.cost}',
                          style: TextStyle(
                            color: canAfford
                                ? const Color(0xFFFFD700)
                                : const Color(0xFFFF5A5A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (atCap) ...[
                          const SizedBox(width: 6),
                          Text(
                            'досягнуто ліміт',
                            style: TextStyle(
                              color: const Color(0xFFFF5A5A)
                                  .withValues(alpha: 0.85),
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
