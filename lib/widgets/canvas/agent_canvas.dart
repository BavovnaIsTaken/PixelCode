/// Right panel: pixel-art office scene with animated agent characters.
///
/// Characters move around the office via BFS pathfinding, sit at desks
/// when active, and wander when idle — like a game.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/agent_provider.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import 'build_menu.dart';
import 'character_sprites.dart';
import 'snap_logic.dart';
import 'foreman_overlay_painter.dart';
import 'office_game_state.dart';
import 'office_upgrade_dialog.dart';
import 'pixel_office_painter.dart';
import 'pixel_sprites.dart';

// ─── Main canvas widget ─────────────────────────────────────────────────────

class AgentCanvas extends ConsumerStatefulWidget {
  const AgentCanvas({super.key});

  @override
  ConsumerState<AgentCanvas> createState() => _AgentCanvasState();
}

class _AgentCanvasState extends ConsumerState<AgentCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final OfficeGameState _gameState;
  final SpriteManager _sprites = SpriteManager();
  final TransformationController _transformController =
      TransformationController();
  final FocusNode _keyboardFocusNode = FocusNode();
  Duration _lastElapsed = Duration.zero;
  int _tick = 0;
  double _tickAccum = 0;

  /// When false, the canvas hides the amber selection halo around the
  /// currently selected agent. Tapping empty space clears it; tapping a
  /// character restores it. The underlying [selectedAgentProvider] stays put
  /// so chat context and name overlays remain addressable.
  bool _selectionVisible = true;

  // Build Mode state lives in `buildModeProvider` — agent_canvas is just one
  // of two surfaces that consume it (the other is hub_screen, which mounts
  // the menu in the chat-panel slot on desktop).

  // Track last synced level/rooms to avoid rebuilding tile map every frame
  OfficeLevel? _lastLevel;
  int _lastExpansions = -1;
  List<PlacedRoom>? _lastRooms;
  List<FurniturePlacement>? _lastFurniture;
  List<PlacedCorridor>? _lastCorridors;

  StreamSubscription<ServerMessage>? _msgSub;
  Timer? _posSyncTimer;

  /// True until the player has tapped the foreman at least once. Drives the
  /// bouncing onboarding chevron above the foreman's head. Persisted across
  /// launches so the chevron doesn't re-appear after every restart.
  bool _foremanIntroPending = true;

  /// True while a desktop pointer is hovering over the foreman hit rect.
  /// Drives the diegetic "Збудуємо?" speech bubble.
  bool _foremanHovering = false;

  static const String _foremanIntroSeenKey = 'foremanIntroSeen';

  @override
  void initState() {
    super.initState();
    _gameState = OfficeGameState();
    _ticker = createTicker(_onTick)..start();
    _sprites.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadForemanIntroFlag();
    _startPositionSync();
  }

  Future<void> _loadForemanIntroFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_foremanIntroSeenKey) ?? false;
    if (mounted && seen) {
      setState(() => _foremanIntroPending = false);
    }
  }

  Future<void> _markForemanIntroSeen() async {
    if (!_foremanIntroPending) return;
    setState(() => _foremanIntroPending = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foremanIntroSeenKey, true);
  }

  void _startPositionSync() {
    // Send our positions every 3 seconds so other devices can follow
    _posSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final ws = ref.read(wsServiceProvider);
      if (ws.isConnected) {
        ws.syncPositions(_gameState.serializePositions());
      }
    });

    // Listen for position updates from other devices
    _msgSub = ref.read(wsServiceProvider).messages.listen(_onServerMessage);
  }

  void _onServerMessage(ServerMessage msg) {
    if (msg is PositionsSyncMessage) {
      _gameState.applyRemotePositions({
        for (final e in msg.positions.entries)
          e.key: (
            col: e.value.col,
            row: e.value.row,
            state: e.value.state,
            dir: e.value.dir,
            onSkateboard: e.value.onSkateboard,
          ),
      });
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _posSyncTimer?.cancel();
    _ticker.dispose();
    _transformController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    final clampedDt = dt.clamp(0.0, 0.1);

    _gameState.update(clampedDt);

    // Slow tick for monitor animation & bubbles (~3.3 Hz)
    _tickAccum += clampedDt;
    if (_tickAccum >= 0.3) {
      _tickAccum -= 0.3;
      _tick++;
    }

    setState(() {});
  }


  bool _logExpanded = false;
  String? _hoveredAgentId;

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);
    final metrics = ref.watch(metricsProvider);
    final activityLog = ref.watch(activityLogProvider);
    final commEvents = ref.watch(commGraphProvider);
    final gameEconomy = ref.watch(gameEconomyProvider);

    // Rebuild tile map when office level, expansions, rooms, furniture, or corridors change
    final level = gameEconomy.officeLevel;
    final expansions = gameEconomy.officeExpansions;
    final rooms = gameEconomy.placedRooms;
    final furniture = gameEconomy.placedFurniture;
    final corridors = gameEconomy.placedCorridors;
    if (!identical(rooms, _lastRooms) ||
        !identical(furniture, _lastFurniture) ||
        !identical(corridors, _lastCorridors) ||
        level != _lastLevel ||
        expansions != _lastExpansions) {
      _lastLevel = level;
      _lastExpansions = expansions;
      _lastRooms = rooms;
      _lastFurniture = furniture;
      _lastCorridors = corridors;
      _gameState.rebuildLayout(level, expansions, rooms, furniture, corridors);
    }

    // Sync agent states and hired status into game engine
    _gameState.syncAgents(agents);
    final hardwareMap = {
      for (final e in gameEconomy.agents.entries)
        e.key: e.value.hardware,
    };
    _gameState.syncHiredAgents(gameEconomy.hiredAgentIds, hardwareMap);

    final activeAgents =
        agents.entries.where((e) => e.value.isActive).toList();

    final c = context.appColors;
    return Container(
      color: c.background,
      child: Column(
        children: [
          _buildHeader(agents),
          if (activeAgents.isNotEmpty)
            _ActiveAgentsStrip(agents: activeAgents, tick: _tick),
          Expanded(
            child: _buildOffice(agents, gameEconomy),
          ),
          if (metrics.isNotEmpty) _TeamMetricsBar(metrics: metrics),
          if (commEvents.isNotEmpty) _CommGraphPanel(events: commEvents),
          _ActivityLogPanel(
            events: activityLog,
            expanded: _logExpanded,
            onToggle: () => setState(() => _logExpanded = !_logExpanded),
            onClear: () => ref.read(activityLogProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, AgentState> agents) {
    final active =
        agents.values.where((a) => a.status != AgentStatus.idle).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined,
              color: Colors.white.withValues(alpha: 0.5), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Команда',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active > 0
                  ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              active > 0 ? '$active активн.' : 'усі вільні',
              style: TextStyle(
                color: active > 0
                    ? const Color(0xFF00C0D1)
                    : Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffice(Map<String, AgentState> agents, GameState gameEconomy) {
    final officeLevel = gameEconomy.officeLevel;
    final editMode = ref.watch(furnitureEditModeProvider);
    final buildMode = ref.watch(buildModeProvider);

    // BuildMenu sits in the chat-panel slot on wide viewports — agent_canvas
    // doesn't render it there. On narrow viewports the canvas hosts a 200dp
    // bottom sheet so the canvas stays visible above it during placement.
    final viewportWidth = MediaQuery.of(context).size.width;
    final wideMenu = viewportWidth >= BuildMenu.kBreakpoint;
    final menuBottomSpace = buildMode.active && !wideMenu
        ? BuildMenu.kBottomSheetHeight
        : 0.0;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: buildMode.active,
      onKeyEvent: (event) {
        if (!buildMode.active) return;
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        if (event.logicalKey == LogicalKeyboardKey.keyR) {
          if (shift) {
            ref.read(buildModeProvider.notifier).rotateCounterClockwise();
          } else {
            ref.read(buildModeProvider.notifier).rotateClockwise();
          }
        } else if (event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(buildModeProvider.notifier).clearSelection();
        }
      },
      child: Stack(
      children: [
        // Canvas — shrinks only when the mobile bottom sheet is open. On
        // desktop the menu takes the chat slot, so canvas keeps its full
        // share of this column.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: menuBottomSpace,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 3.0,
                    child: MouseRegion(
                      onHover: (event) {
                        _onCanvasHover(event.localPosition, constraints);
                        _updateBuildGhost(event.localPosition, constraints);
                      },
                      onExit: (_) {
                        setState(() {
                          _hoveredAgentId = null;
                          _foremanHovering = false;
                        });
                      },
                      child: GestureDetector(
                        onTapDown: (d) =>
                            _onCanvasTap(d.localPosition, constraints),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: PixelOfficePainter(
                                  gameState: _gameState,
                                  sprites: _sprites,
                                  selectedAgentId: _selectionVisible
                                      ? ref.watch(selectedAgentProvider)
                                      : null,
                                  hoveredAgentId: _hoveredAgentId,
                                  tick: _tick,
                                  officeLevel: officeLevel,
                                  placedFurniture:
                                      gameEconomy.placedFurniture,
                                  placedRooms: gameEconomy.placedRooms,
                                  editMode: editMode,
                                  selectedFurnitureId:
                                      ref.watch(selectedFurnitureIdProvider),
                                  buildMode: buildMode.active,
                                  ghostRoomType: editMode
                                      ? null
                                      : buildMode.selectedRoomType,
                                  ghostRoomCol: buildMode.ghostCol,
                                  ghostRoomRow: buildMode.ghostRow,
                                  ghostRoomRotation: buildMode.ghostRotation,
                                  ghostIsValid: _ghostIsValid(
                                      buildMode, gameEconomy.placedRooms),
                                  adjacencyLabel: _adjacencyLabel(
                                      buildMode, gameEconomy.placedRooms),
                                  placedCorridors:
                                      gameEconomy.placedCorridors,
                                  corridorAnchorCol:
                                      buildMode.corridorAnchorCol,
                                  corridorAnchorRow:
                                      buildMode.corridorAnchorRow,
                                ),
                              ),
                            ),
                            // Foreman + back-wall door — diegetic entry
                            // points to Build mode and the upgrade dialog.
                            // Hidden while the player is already building.
                            if (!buildMode.active)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: ForemanOverlayPainter(
                                      gridCols: _gameState.gridCols,
                                      gridRows: _gameState.gridRows,
                                      tick: _tick,
                                      officeLevel: officeLevel,
                                      sprites: _sprites,
                                      attention: _renovationAttention(
                                          gameEconomy),
                                      firstTimePrompt: _foremanIntroPending,
                                      hovering: _foremanHovering,
                                      nextTier: officeLevel.nextLevel,
                                      doorAffordable: ref
                                          .read(gameEconomyProvider.notifier)
                                          .canUpgradeOffice(),
                                      doorDisabled:
                                          officeLevel.nextLevel == null ||
                                              officeLevel
                                                  .nextLevel!.isWipComingSoon,
                                    ),
                                  ),
                                ),
                              ),
                            ..._buildNameOverlays(agents, constraints),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isZoomed)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: _resetZoom,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xCC1A1A2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Icon(
                            Icons.zoom_out_map_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),

        // BuildMenu — narrow viewport only. On wide viewports the menu lives
        // in the chat-panel slot rendered by hub_screen, leaving the canvas
        // its full share of this column.
        if (buildMode.active && !wideMenu)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: BuildMenu.kBottomSheetHeight,
            child: const BuildMenu(),
          ),

        // Place Bar — floats above the build menu / above the canvas bottom
        // edge when a room type is selected and the ghost is live.
        if (buildMode.active && buildMode.selectedRoomType != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: (!wideMenu ? BuildMenu.kBottomSheetHeight : 0) + 12,
            child: _PlaceBar(
              roomType: buildMode.selectedRoomType!,
              ghostIsValid: _ghostIsValid(buildMode, gameEconomy.placedRooms),
              ghostLive: buildMode.ghostCol != null,
              rotation: buildMode.ghostRotation,
              onCancel: () => ref.read(buildModeProvider.notifier).clearSelection(),
              onRotateCW: () => ref.read(buildModeProvider.notifier).rotateClockwise(),
              onRotateCCW: () => ref.read(buildModeProvider.notifier).rotateCounterClockwise(),
              onPlace: () {
                final mode = ref.read(buildModeProvider);
                final rooms = ref.read(gameEconomyProvider).placedRooms;
                if (mode.ghostCol == null || !_ghostIsValid(mode, rooms)) {
                  return;
                }
                final econ = ref.read(gameEconomyProvider.notifier);
                final templateId = mode.selectedTemplateId;
                if (templateId != null) {
                  final template = roomTemplateById(templateId);
                  if (template != null) {
                    econ.placeRoomTemplate(
                      template,
                      mode.ghostCol!,
                      mode.ghostRow!,
                      rotation: mode.ghostRotation,
                    );
                  }
                } else {
                  econ.placeRoom(
                    mode.selectedRoomType!,
                    mode.ghostCol!,
                    mode.ghostRow!,
                    rotation: mode.ghostRotation,
                  );
                }
                ref.read(buildModeProvider.notifier).clearGhost();
              },
            ),
          ),
      ],
      ),
    );
  }

  bool get _isZoomed =>
      _transformController.value.getMaxScaleOnAxis() > 1.01;

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  /// Is something affordable right now that would make sense to buy from
  /// the renovation flow (next-tier move-in OR the next expansion step)?
  bool _renovationAttention(GameState game) {
    final notifier = ref.read(gameEconomyProvider.notifier);
    return notifier.canUpgradeOffice() || notifier.canBuyOfficeExpansion();
  }

  void _enterBuildMode() {
    ref.read(buildModeProvider.notifier).enter();
    // Hide hover bubble — pointer is now over the build menu, not the foreman.
    if (_foremanHovering) setState(() => _foremanHovering = false);
    // Persist that the player has discovered the foreman entry — chevron
    // never re-appears on subsequent launches.
    _markForemanIntroSeen();
  }

  /// Hit-test the Foreman sprite (world-space rect from foreman_overlay_painter).
  bool _hitTestForeman(Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    return foremanHitRect(_gameState.gridCols, _gameState.gridRows)
        .contains(world);
  }

  /// Hit-test the back-wall door.
  bool _hitTestDoor(Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    return doorHitRect(_gameState.gridCols).contains(world);
  }

  /// Convert screen position to world position and hit-test characters.
  String? _hitTestCharacter(Offset screenPos, BoxConstraints constraints) {
    final cw = _gameState.canvasWidth;
    final ch = _gameState.canvasHeight;
    final scaleX = constraints.maxWidth / cw;
    final scaleY = constraints.maxHeight / ch;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (constraints.maxWidth - cw * scale) / 2;
    final offsetY = (constraints.maxHeight - ch * scale) / 2;

    final worldX = (screenPos.dx - offsetX) / scale;
    final worldY = (screenPos.dy - offsetY) / scale;

    // Check characters sorted by Y descending (front-most first)
    final chars = _gameState.characters.values.toList()
      ..sort((a, b) => b.y.compareTo(a.y));

    for (final ch in chars) {
      final sittingOffset =
          ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
      final left = ch.x - 8;
      final right = ch.x + 8;
      final top = ch.y + sittingOffset - 28; // slightly less than full sprite
      final bottom = ch.y + sittingOffset;

      if (worldX >= left && worldX <= right &&
          worldY >= top && worldY <= bottom) {
        return ch.instanceId;
      }
    }
    return null;
  }

  void _onCanvasHover(Offset pos, BoxConstraints constraints) {
    final hit = _hitTestCharacter(pos, constraints);
    if (hit != _hoveredAgentId) {
      setState(() => _hoveredAgentId = hit);
    }
    // Foreman hover only matters outside build mode (where the entry exists).
    final isBuildMode = ref.read(buildModeProvider).active;
    final overForeman =
        !isBuildMode && _hitTestForeman(pos, constraints);
    if (overForeman != _foremanHovering) {
      setState(() => _foremanHovering = overForeman);
    }
  }

  void _scheduleOverlayHover(String agentId) {
    if (_hoveredAgentId != agentId) {
      setState(() => _hoveredAgentId = agentId);
    }
  }

  void _onCanvasTap(Offset pos, BoxConstraints constraints) {
    final isEditMode = ref.read(furnitureEditModeProvider);
    final isBuildMode = ref.read(buildModeProvider).active;

    // Build mode: edit mode removes placed rooms/furniture; otherwise place.
    if (isBuildMode) {
      if (isEditMode) {
        _handleEditModeTap(pos, constraints);
      } else {
        _handleBuildModeTap(
            pos, constraints, ref.read(gameEconomyProvider).placedRooms);
      }
      return;
    }

    // Furniture edit mode (outside build mode, from Shop panel toggle):
    // place or remove furniture on grid.
    if (isEditMode) {
      _handleFurnitureTap(pos, constraints);
      return;
    }

    // Back-wall door → open upgrade dialog. Check before the foreman so the
    // door wins when hit regions happen to overlap on very small grids.
    if (_hitTestDoor(pos, constraints)) {
      showOfficeUpgradeDialog(context);
      return;
    }

    // Foreman → enter Build mode.
    if (_hitTestForeman(pos, constraints)) {
      _enterBuildMode();
      return;
    }

    final hit = _hitTestCharacter(pos, constraints);
    if (hit != null) {
      // [hit] is already an instanceId — select that specific agent directly.
      final ch = _gameState.characters[hit];
      if (ch != null && ch.isHired) {
        ref.read(selectedAgentProvider.notifier).state = hit;
        if (!_selectionVisible) setState(() => _selectionVisible = true);
        return;
      }
    }
    // Check plant clicks (easter egg)
    if (_hitTestPlant(pos, constraints)) return;
    // Empty tap: clear the on-canvas selection halo. Provider state is kept
    // so the chat panel still knows who was last focused.
    if (_selectionVisible) setState(() => _selectionVisible = false);
  }

  /// Edit mode in Build Mode: tap a placed room to refund+remove it; tap a
  /// placed furniture item to remove it. Rooms take priority over furniture
  /// when both occupy the tile (furniture visually sits inside a room).
  void _handleEditModeTap(Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();
    if (col < 1 ||
        col >= _gameState.gridCols - 1 ||
        row < 1 ||
        row >= _gameState.gridRows - 1) {
      return;
    }

    final game = ref.read(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);

    for (int i = 0; i < game.placedFurniture.length; i++) {
      final p = game.placedFurniture[i];
      final item = furnitureById(p.itemId);
      if (item == null) continue;
      if (col >= p.col &&
          col < p.col + item.widthTiles &&
          row >= p.row &&
          row < p.row + item.heightTiles) {
        notifier.removePlacedFurniture(i);
        return;
      }
    }

    for (final room in game.placedRooms) {
      if (col >= room.col &&
          col < room.col + room.type.widthTiles &&
          row >= room.row &&
          row < room.row + room.type.heightTiles) {
        notifier.removeRoom(room.id);
        return;
      }
    }
  }

  void _handleFurnitureTap(Offset screenPos, BoxConstraints constraints) {
    final cw = _gameState.canvasWidth;
    final ch = _gameState.canvasHeight;
    final scaleX = constraints.maxWidth / cw;
    final scaleY = constraints.maxHeight / ch;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (constraints.maxWidth - cw * scale) / 2;
    final offsetY = (constraints.maxHeight - ch * scale) / 2;

    final worldX = (screenPos.dx - offsetX) / scale;
    final worldY = (screenPos.dy - offsetY) / scale;

    final col = (worldX / kTileSize).floor();
    final row = (worldY / kTileSize).floor();

    // Must be on floor (not wall)
    if (col < 1 || col >= _gameState.gridCols - 1 || row < 1 || row >= _gameState.gridRows - 1) {
      return;
    }

    // Check if tapping on existing placed furniture → remove it
    final game = ref.read(gameEconomyProvider);
    for (int i = 0; i < game.placedFurniture.length; i++) {
      final p = game.placedFurniture[i];
      final item = furnitureById(p.itemId);
      if (item == null) continue;
      if (col >= p.col &&
          col < p.col + item.widthTiles &&
          row >= p.row &&
          row < p.row + item.heightTiles) {
        ref.read(gameEconomyProvider.notifier).removePlacedFurniture(i);
        return;
      }
    }

    // Place selected furniture
    final selectedId = ref.read(selectedFurnitureIdProvider);
    if (selectedId == null) return;
    final item = furnitureById(selectedId);
    if (item == null) return;

    // Check tile is not blocked
    final blocked = _gameState.blockedTiles;
    for (int dc = 0; dc < item.widthTiles; dc++) {
      for (int dr = 0; dr < item.heightTiles; dr++) {
        if (blocked.contains('${col + dc},${row + dr}')) return;
      }
    }

    ref.read(gameEconomyProvider.notifier).placeFurniture(selectedId, col, row);
  }

  // ─── Build Mode ────────────────────────────────────────────────────────────

  Offset _screenToWorld(Offset screenPos, BoxConstraints constraints) {
    final cw = _gameState.canvasWidth;
    final ch = _gameState.canvasHeight;
    final scale = math.min(
        constraints.maxWidth / cw, constraints.maxHeight / ch);
    final ox = (constraints.maxWidth - cw * scale) / 2;
    final oy = (constraints.maxHeight - ch * scale) / 2;
    return Offset(
        (screenPos.dx - ox) / scale, (screenPos.dy - oy) / scale);
  }

  bool _ghostIsValid(BuildModeState mode, List<PlacedRoom> rooms) {
    final rt = mode.selectedRoomType;
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (rt == null || gc == null || gr == null) return false;
    final gCols = _gameState.gridCols;
    final gRows = _gameState.gridRows;
    final gw = mode.ghostWidth;
    final gh = mode.ghostHeight;
    // Must be fully inside inner grid
    if (gc < 1 || gr < 1) return false;
    if (gc + gw > gCols - 1) return false;
    if (gr + gh > gRows - 1) return false;
    // No overlap with blocked tiles
    final blocked = _gameState.blockedTiles;
    for (int dc = 0; dc < gw; dc++) {
      for (int dr = 0; dr < gh; dr++) {
        if (blocked.contains('${gc + dc},${gr + dr}')) return false;
      }
    }
    // No overlap with existing rooms (use their rotated footprint too)
    for (final r in rooms) {
      final ox = gc < r.col + r.footprintWidth && gc + gw > r.col;
      final oy = gr < r.row + r.footprintHeight && gr + gh > r.row;
      if (ox && oy) return false;
    }
    return true;
  }

  /// Returns the adjacency bonus/penalty label for the current ghost, or null.
  String? _adjacencyLabel(BuildModeState mode, List<PlacedRoom> rooms) {
    final rt = mode.selectedRoomType;
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (rt == null || gc == null || gr == null) return null;
    final pct = computeAdjacencyBonusPercent(rt, gc, gr, mode.ghostRotation, rooms);
    if (pct == null) return null;
    return pct > 0 ? '+$pct%' : '−${pct.abs()}%';
  }

  void _handleBuildModeTap(Offset screenPos, BoxConstraints constraints,
      List<PlacedRoom> rooms) {
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();

    final mode = ref.read(buildModeProvider);
    final notifier = ref.read(buildModeProvider.notifier);

    // ── Corridor placement — two-tap: anchor then endpoint ──────────────────
    if (mode.section == BuildSection.corridors) {
      final ac = mode.corridorAnchorCol;
      final ar = mode.corridorAnchorRow;
      if (ac == null || ar == null) {
        // First tap — set anchor.
        notifier.setCorridorAnchor(col, row);
        notifier.setGhost(col: col, row: row);
      } else {
        // Second tap — compute L-path and place.
        final path = _computeCorridorPath(ac, ar, col, row);
        final econ = ref.read(gameEconomyProvider.notifier);
        econ.placeCorridor(path, wide: mode.corridorWide);
        notifier.clearCorridorAnchor();
      }
      return;
    }

    // ── Room / template placement — two-step ghost ───────────────────────────
    final isRepeatTap = mode.ghostCol == col && mode.ghostRow == row;
    if (!isRepeatTap) {
      notifier.setGhost(col: col, row: row);
      return;
    }

    final rt = mode.selectedRoomType;
    if (rt == null) return;
    if (!_ghostIsValid(mode, rooms)) return;

    final econ = ref.read(gameEconomyProvider.notifier);
    final templateId = mode.selectedTemplateId;
    if (templateId != null) {
      final template = roomTemplateById(templateId);
      if (template != null) {
        econ.placeRoomTemplate(template, col, row, rotation: mode.ghostRotation);
      }
    } else {
      econ.placeRoom(rt, col, row, rotation: mode.ghostRotation);
    }
    notifier.clearGhost();
  }

  /// Computes the L-shaped tile path (horizontal first, then vertical) from
  /// anchor to endpoint. No duplicate tiles — the corner is included once.
  List<({int col, int row})> _computeCorridorPath(
      int ac, int ar, int gc, int gr) {
    final tiles = <String, ({int col, int row})>{};
    final cMin = ac < gc ? ac : gc;
    final cMax = ac < gc ? gc : ac;
    for (int c = cMin; c <= cMax; c++) {
      tiles['$c,$ar'] = (col: c, row: ar);
    }
    final rMin = ar < gr ? ar : gr;
    final rMax = ar < gr ? gr : ar;
    for (int r = rMin; r <= rMax; r++) {
      tiles['$gc,$r'] = (col: gc, row: r);
    }
    return tiles.values.toList();
  }

  void _updateBuildGhost(Offset screenPos, BoxConstraints constraints) {
    final mode = ref.read(buildModeProvider);
    if (!mode.active) return;
    final world = _screenToWorld(screenPos, constraints);
    var col = (world.dx / kTileSize).floor();
    var row = (world.dy / kTileSize).floor();

    // Apply snap-to-edge logic for room templates and regular rooms
    if (mode.selectedRoomType != null) {
      final ghostCols = mode.selectedRoomType!.widthTiles;
      final ghostRows = mode.selectedRoomType!.heightTiles;
      final econ = ref.read(gameEconomyProvider);

      col = _snapGhostCol(col, row, ghostCols, ghostRows, econ.placedRooms);
      row = _snapGhostRow(col, row, ghostCols, ghostRows, econ.placedRooms);
    }

    if (col != mode.ghostCol || row != mode.ghostRow) {
      ref.read(buildModeProvider.notifier).setGhost(col: col, row: row);
    }
  }

  int _snapGhostCol(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
      List<PlacedRoom> placedRooms) =>
      snapGhostCol(ghostCol, ghostRow, ghostCols, ghostRows, placedRooms);

  int _snapGhostRow(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
      List<PlacedRoom> placedRooms) =>
      snapGhostRow(ghostCol, ghostRow, ghostCols, ghostRows, placedRooms);


  bool _hitTestPlant(Offset screenPos, BoxConstraints constraints) {
    final cw = _gameState.canvasWidth;
    final ch = _gameState.canvasHeight;
    final scaleX = constraints.maxWidth / cw;
    final scaleY = constraints.maxHeight / ch;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (constraints.maxWidth - cw * scale) / 2;
    final offsetY = (constraints.maxHeight - ch * scale) / 2;

    final worldX = (screenPos.dx - offsetX) / scale;
    final worldY = (screenPos.dy - offsetY) / scale;

    for (final placement in _gameState.placedFurniture) {
      if (!placement.itemId.startsWith('plant_')) continue;
      final isLarge = placement.itemId == 'plant_large';
      final px = placement.col * kTileSize;
      // Large plant sprite extends one tile above its footprint.
      final py = isLarge
          ? placement.row * kTileSize - kTileSize
          : placement.row * kTileSize;
      final height = isLarge ? kTileSize * 2 : kTileSize;
      if (worldX >= px && worldX <= px + kTileSize &&
          worldY >= py && worldY <= py + height) {
        _gameState.activatePlant(placement.col, placement.row);
        return true;
      }
    }
    return false;
  }

  List<Widget> _buildNameOverlays(
    Map<String, AgentState> agents,
    BoxConstraints constraints,
  ) {
    final cw = _gameState.canvasWidth;
    final ch = _gameState.canvasHeight;
    final scaleX = constraints.maxWidth / cw;
    final scaleY = constraints.maxHeight / ch;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (constraints.maxWidth - cw * scale) / 2;
    final offsetY = (constraints.maxHeight - ch * scale) / 2;

    final widgets = <Widget>[];

    // One label per hired character instance (multiple coders → multiple
    // labels) so the overlay reflects the real roster, not the fixed station
    // list.
    final selectedId =
        _selectionVisible ? ref.watch(selectedAgentProvider) : null;
    for (final ch in _gameState.characters.values) {
      if (!ch.isHired) continue;

      final instanceId = ch.instanceId;
      final agentState = agents[instanceId];
      final isActive =
          agentState != null && agentState.status != AgentStatus.idle;
      final isSelected = selectedId == instanceId;
      final isHovered = _hoveredAgentId == instanceId;
      final color = agentAccentColor(ch.roleType);

      // Label follows the character, anchored below
      final labelX = ch.x;
      final sittingOffset =
          ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
      final labelY = ch.y + sittingOffset + 6;

      final screenX = offsetX + labelX * scale;
      final screenY = offsetY + labelY * scale;

      // Prefer the actual AgentInfo nickname (respects renames) and fall back
      // to the catalog-based defaults.
      final info = agentState?.info;
      final nick = info?.name ??
          (_agentNickAndRole(ch.roleType).$1);
      final role = info?.role ??
          (_agentNickAndRole(ch.roleType).$2);

      final highlighted = isSelected || isHovered;
      const borderColor = Color(0xFFFFC107); // amber for both hover & select

      widgets.add(
        Positioned(
          left: screenX - 40,
          top: screenY,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedAgentProvider.notifier).state = instanceId;
              if (!_selectionVisible) {
                setState(() => _selectionVisible = true);
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _scheduleOverlayHover(instanceId),
              onHover: (_) => _scheduleOverlayHover(instanceId),
              onExit: (_) {
                if (_hoveredAgentId == instanceId) {
                  setState(() => _hoveredAgentId = null);
                }
              },
              child: Container(
                width: 80,
                padding:
                    const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                decoration: BoxDecoration(
                  color: highlighted
                      ? borderColor.withValues(alpha: 0.15)
                      : const Color(0xCC1A1A2E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: highlighted
                        ? borderColor.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // Nickname
                    Text(
                      nick,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: highlighted
                            ? const Color(0xFFFFC107)
                            : isActive
                                ? color
                                : Colors.white.withValues(alpha: 0.85),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        shadows: const [
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    // Role (always visible)
                    Text(
                      role,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: highlighted
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 7,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    // Status when active
                    if (isActive)
                      Text(
                        _statusLabel(agentState.status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.6),
                          fontSize: 7,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Cat label
    final cat = _gameState.cat;
    final catLabelX = cat.x;
    final catLabelY = cat.y + (cat.state == CatAction.sleep ? 0 : 5);
    final catScreenX = offsetX + catLabelX * scale;
    final catScreenY = offsetY + catLabelY * scale;
    final catStatus = switch (cat.state) {
      CatAction.sleep => '💤 спить',
      CatAction.walk => '🐾 гуляє',
      CatAction.idle => '😺 сидить',
    };

    widgets.add(
      Positioned(
        left: catScreenX - 30,
        top: catScreenY,
        child: IgnorePointer(
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A2E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFFF8C42).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Мурчик',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF8C42),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                Text(
                  catStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 7,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return widgets;
  }

  static (String nick, String role) _agentNickAndRole(String id) =>
      switch (id) {
        'manager' => ('Капітан', 'координатор'),
        'tech-lead' => ('Архітект', 'технічний лідер'),
        'coder' => ('Майстер', 'розробник'),
        'reviewer' => ('Детектив', 'рецензент'),
        'tester' => ('Крашер', 'контроль якості'),
        'security' => ('Страж', 'безпека'),
        'ui-ux-designer' => ('Піксельник', 'UI/UX'),
        'llm-specialist' => ('Промптер', 'LLM-спеціаліст'),
        _ => (id, ''),
      };

  String _statusLabel(AgentStatus status) => switch (status) {
        AgentStatus.thinking => 'думає...',
        AgentStatus.typing => 'пише...',
        AgentStatus.reading => 'читає...',
        AgentStatus.running => 'виконує...',
        AgentStatus.waiting => 'чекає',
        AgentStatus.idle => '',
      };
}

// ─── Place Bar ───────────────────────────────────────────────────────────────

/// Floating action bar shown when a room type is selected in Build Mode.
/// Provides [X cancel] [↺ CCW] [↻ CW] [✓ Place ₲N] controls.
class _PlaceBar extends StatelessWidget {
  final RoomType roomType;
  final bool ghostIsValid;
  final bool ghostLive;
  final int rotation;
  final VoidCallback onCancel;
  final VoidCallback onRotateCW;
  final VoidCallback onRotateCCW;
  final VoidCallback onPlace;

  const _PlaceBar({
    required this.roomType,
    required this.ghostIsValid,
    required this.ghostLive,
    required this.rotation,
    required this.onCancel,
    required this.onRotateCW,
    required this.onRotateCCW,
    required this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final canPlace = ghostIsValid && ghostLive;
    final rotLabel = rotation == 0
        ? ''
        : '$rotation°';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Room name + cost
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${roomType.icon} ${roomType.nameUk}',
                  style: TextStyle(
                    color: c.textHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '₲${roomType.cost}',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rotLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        rotLabel,
                        style: TextStyle(color: c.textMedium, fontSize: 10),
                      ),
                    ],
                    if (ghostLive && !ghostIsValid) ...[
                      const SizedBox(width: 6),
                      Text(
                        'не вміщується',
                        style: TextStyle(color: c.error, fontSize: 10),
                      ),
                    ] else if (!ghostLive) ...[
                      const SizedBox(width: 6),
                      Text(
                        'оберіть місце',
                        style: TextStyle(color: c.textLow, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cancel
          _BarButton(
            icon: Icons.close,
            tooltip: 'Скасувати (Esc)',
            color: c.textMedium,
            onTap: onCancel,
          ),
          const SizedBox(width: 4),
          // Rotate CCW
          _BarButton(
            icon: Icons.rotate_left,
            tooltip: 'Повернути ліворуч (Shift+R)',
            color: c.textMedium,
            onTap: onRotateCCW,
          ),
          const SizedBox(width: 4),
          // Rotate CW
          _BarButton(
            icon: Icons.rotate_right,
            tooltip: 'Повернути праворуч (R)',
            color: c.textMedium,
            onTap: onRotateCW,
          ),
          const SizedBox(width: 8),
          // Confirm place
          GestureDetector(
            onTap: canPlace ? onPlace : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: canPlace
                    ? c.accent.withValues(alpha: 0.15)
                    : c.surfaceDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: canPlace ? c.accent : c.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 14,
                    color: canPlace ? c.accent : c.textLow,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '₲${roomType.cost}',
                    style: TextStyle(
                      color: canPlace ? c.accent : c.textLow,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─── Active Agents Status Strip ─────────────────────────────────────────────

class _ActiveAgentsStrip extends StatelessWidget {
  final List<MapEntry<String, AgentState>> agents;
  final int tick;

  const _ActiveAgentsStrip({required this.agents, required this.tick});

  static const _statusIcons = <AgentStatus, IconData>{
    AgentStatus.thinking: Icons.psychology_rounded,
    AgentStatus.typing: Icons.edit_rounded,
    AgentStatus.reading: Icons.visibility_rounded,
    AgentStatus.running: Icons.terminal_rounded,
    AgentStatus.waiting: Icons.hourglass_top_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        border: Border(
          bottom: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        children: [
          for (final entry in agents)
            _buildAgentRow(entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _buildAgentRow(String agentId, AgentState agent) {
    final color = agentAccentColor(agentId);
    final icon = _statusIcons[agent.status] ?? Icons.circle;
    final elapsed = _formatElapsed(agent.activeSince);
    final description = agent.lastToolDescription ?? agent.currentTask;
    final pulseAlpha = 0.6 + 0.4 * ((tick % 3) / 2.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: pulseAlpha),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            agent.info.name,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            _statusLabel(agent.status),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '·',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (elapsed != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                elapsed,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(AgentStatus status) => switch (status) {
        AgentStatus.thinking => 'думає',
        AgentStatus.typing => 'пише',
        AgentStatus.reading => 'читає',
        AgentStatus.running => 'виконує',
        AgentStatus.waiting => 'чекає',
        AgentStatus.idle => '',
      };

  String? _formatElapsed(DateTime? since) {
    if (since == null) return null;
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }
}

// ─── Comm Graph Panel ───────────────────────────────────────────────────────

class _CommGraphPanel extends StatefulWidget {
  final List<CommEvent> events;
  const _CommGraphPanel({required this.events});

  @override
  State<_CommGraphPanel> createState() => _CommGraphPanelState();
}

class _CommGraphPanelState extends State<_CommGraphPanel> {
  int? _windowMinutes = 30;

  static const _windows = <int?, String>{
    5: '5m',
    30: '30m',
    60: '1h',
    180: '3h',
    600: '10h',
    1440: '24h',
    null: 'Все',
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff =
        _windowMinutes != null ? now - _windowMinutes! * 60 * 1000 : 0;
    final filtered =
        widget.events.where((e) => e.timestamp >= cutoff).toList();

    final edges = <(String, String), int>{};
    for (final e in filtered) {
      final key = (e.from, e.to);
      edges[key] = (edges[key] ?? 0) + 1;
    }

    final sorted = edges.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                'Комунікації',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              for (final entry in _windows.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _windowMinutes = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _windowMinutes == entry.key
                            ? const Color(0xFF00C0D1)
                                .withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _windowMinutes == entry.key
                              ? const Color(0xFF00C0D1)
                                  .withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: _windowMinutes == entry.key
                              ? const Color(0xFF00C0D1)
                              : Colors.white.withValues(alpha: 0.25),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Немає комунікацій у цьому вікні',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.15),
                  fontSize: 9,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final edge in sorted.take(12))
                    _CommEdge(
                      from: edge.key.$1,
                      to: edge.key.$2,
                      count: edge.value,
                      fromColor: agentAccentColor(edge.key.$1),
                      toColor: agentAccentColor(edge.key.$2),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommEdge extends StatelessWidget {
  final String from;
  final String to;
  final int count;
  final Color fromColor;
  final Color toColor;

  const _CommEdge({
    required this.from,
    required this.to,
    required this.count,
    required this.fromColor,
    required this.toColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            from == 'user' ? 'Ви' : from,
            style: TextStyle(
              color: fromColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 9,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          Text(
            to == 'user' ? 'Ви' : to,
            style: TextStyle(
              color: toColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF00C0D1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF00C0D1),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Team Metrics Bar ───────────────────────────────────────────────────────

class _TeamMetricsBar extends StatelessWidget {
  final Map<String, AgentMetrics> metrics;

  const _TeamMetricsBar({required this.metrics});

  static const _agentLabels = <String, String>{
    'manager': 'MGR',
    'tech-lead': 'TL',
    'coder': 'DEV',
    'reviewer': 'REV',
    'tester': 'QA',
    'security': 'SEC',
    'ui-ux-designer': 'UI',
    'llm-specialist': 'LLM',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                'Метрики команди',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final entry in metrics.entries)
                _MetricChip(
                  label: _agentLabels[entry.key] ?? entry.key,
                  color: agentAccentColor(entry.key),
                  assigned: entry.value.tasksAssigned,
                  completed: entry.value.tasksCompleted,
                  rework: entry.value.reworkCount,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;
  final int assigned;
  final int completed;
  final int rework;

  const _MetricChip({
    required this.label,
    required this.color,
    required this.assigned,
    required this.completed,
    required this.rework,
  });

  @override
  Widget build(BuildContext context) {
    final hasRework = rework > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasRework
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$completed/$assigned',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
          if (hasRework) ...[
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${rework}rw',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Activity Log Panel ─────────────────────────────────────────────────────

class _ActivityLogPanel extends StatefulWidget {
  final List<ActivityEventMessage> events;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const _ActivityLogPanel({
    required this.events,
    required this.expanded,
    required this.onToggle,
    required this.onClear,
  });

  @override
  State<_ActivityLogPanel> createState() => _ActivityLogPanelState();
}

class _ActivityLogPanelState extends State<_ActivityLogPanel> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ActivityLogPanel old) {
    super.didUpdateWidget(old);
    if (widget.events.length > old.events.length && widget.expanded) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  static const _eventIcons = <String, IconData>{
    'started': Icons.play_arrow_rounded,
    'tool_use': Icons.build_rounded,
    'completed': Icons.check_circle_outline_rounded,
    'delegated': Icons.call_split_rounded,
    'error': Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final count = widget.events.length;

    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDim,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Журнал активності',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C0D1)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Color(0xFF00C0D1),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            SizedBox(
              height: 180,
              child: Stack(
                children: [
                  count == 0
                      ? Center(
                          child: Text(
                            'Поки що немає активності',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.15),
                              fontSize: 11,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: count,
                          itemBuilder: (context, i) {
                            final e = widget.events[i];
                            final color = agentAccentColor(e.agentId);
                            final icon = _eventIcons[e.event] ??
                                Icons.circle_outlined;
                            final time =
                                '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                                '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                                '${e.timestamp.second.toString().padLeft(2, '0')}';

                            return Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 52,
                                    child: Text(
                                      time,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.2),
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  Icon(icon, size: 11, color: color),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 62,
                                    child: Text(
                                      e.agentId,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      e.detail,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 9,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: widget.onClear,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E24),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
