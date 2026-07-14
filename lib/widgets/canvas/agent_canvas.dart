/// Right panel: pixel-art office scene with animated agent characters.
///
/// Characters move around the office via BFS pathfinding, sit at desks
/// when active, and wander when idle — like a game.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/agent_operational_status_provider.dart';
import '../../providers/agent_provider.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/office_simulation_provider.dart';
import '../../providers/office_view_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import 'build_menu.dart';
import 'build_mode_logic.dart';
import 'character_sprites.dart';
import 'edit_mode_logic.dart';
import 'foreman_overlay_painter.dart';
import 'office_game_state.dart';
import 'office_upgrade_dialog.dart';
import 'pixel_office_painter.dart';
import 'janitor_overlay.dart';
import 'pixel_sprites.dart';
import 'session_banner.dart';

// Re-export the pure build-mode placement logic so existing importers of this
// file (and its tests) keep seeing GhostInvalidReason / ghostInvalidReasonLabel.
export 'build_mode_logic.dart'
    show
        GhostInvalidReason,
        GhostStatus,
        BuildGhostInput,
        computeGhostStatus,
        ghostTopLeft,
        ghostInvalidReasonLabel;

// ─── Main canvas widget ─────────────────────────────────────────────────────

class AgentCanvas extends ConsumerStatefulWidget {
  const AgentCanvas({super.key});

  @override
  ConsumerState<AgentCanvas> createState() => _AgentCanvasState();
}

class _AgentCanvasState extends ConsumerState<AgentCanvas>
    with SingleTickerProviderStateMixin {
  final SpriteManager _sprites = SpriteManager();
  final TransformationController _transformController =
      TransformationController();
  final FocusNode _keyboardFocusNode = FocusNode();

  /// Tile under the cursor while edit mode has a held or selected furniture
  /// item — drives the translucent "drop preview" footprint that follows the
  /// pointer, mirroring the buy-mode ghost. Null when nothing in hand, when
  /// the pointer left the canvas, or outside edit mode.
  ({int col, int row})? _furnitureGhostTile;

  /// When false, the canvas hides the amber selection halo around the
  /// currently selected agent. Tapping empty space clears it; tapping a
  /// character restores it. The underlying [selectedAgentProvider] stays put
  /// so chat context and name overlays remain addressable.
  bool _selectionVisible = true;

  /// True until the player has tapped the foreman at least once. Drives the
  /// bouncing onboarding chevron above the foreman's head. Persisted across
  /// launches so the chevron doesn't re-appear after every restart.
  bool _foremanIntroPending = true;

  /// True while a desktop pointer is hovering over the foreman hit rect.
  /// Drives the diegetic "Збудуємо?" speech bubble.
  bool _foremanHovering = false;

  /// True while a pointer is pressed inside the build-mode canvas with no
  /// ghost selected — drives the grab → grabbing cursor swap that signals
  /// "you can drag to reposition the office".
  bool _isGrabbing = false;

  static const String _foremanIntroSeenKey = 'foremanIntroSeen';

  /// Graphite "construction lot" backdrop revealed when the player pans the
  /// office in build mode. Sits on the dark end of the palette so the office
  /// foreground stays the focal point.
  static const Color _kBuildBackdrop = Color(0xFF13141A);

  /// How far past the office bounds the player can drag in build mode. Big
  /// enough to let a 7-wide ghost peek into the foundation buffer on narrow
  /// viewports without losing the office to the side.
  static const double _kBuildPanMargin = 160.0;

  /// Read-only access to the simulation game state. The simulation lives in
  /// [officeSimulationProvider] so its lifecycle is independent of this
  /// widget — recreating the canvas no longer resets agent positions.
  OfficeGameState get _gameState =>
      ref.read(officeSimulationProvider).gameState;

  @override
  void initState() {
    super.initState();
    _sprites.load().then((_) {
      if (mounted) setState(() {});
    });
    // Restore the player's saved office zoom/pan so it persists across hub-tab
    // switches (which recreate this widget) and app restarts. Build mode always
    // opens from identity, so only restore when not currently building.
    if (!ref.read(buildModeProvider).active) {
      _transformController.value = ref.read(officeViewProvider);
    }
    _loadForemanIntroFlag();
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

  @override
  void dispose() {
    _transformController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  String? _hoveredAgentId;

  final Map<String, DateTime> _toastCooldown = {};

  void _showThrottledSnack(
    String key,
    String message, {
    Duration cooldown = const Duration(seconds: 3),
    Duration duration = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    final last = _toastCooldown[key];
    if (last != null && now.difference(last) < cooldown) return;
    _toastCooldown[key] = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ));
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to the long-lived simulation. The service itself doesn't
    // change identity over the app lifetime — `ref.watch` here is just to
    // create the dependency edge (and trigger creation if not yet built).
    final service = ref.watch(officeSimulationProvider);
    // C.2.6 — read the reconciled view (status forced to idle when the
    // server's active_agents registry says no run is in flight) so the
    // canvas stops painting "still working" sprites for hung/cancelled
    // queries that never sent a final agent_status: idle push.
    final agents = ref.watch(reconciledAgentsProvider);
    final gameEconomy = ref.watch(gameEconomyProvider);

    // Snap the transform on every entry/exit of build mode: entering resets to
    // identity so a prior session's pan doesn't carry over and build mode's
    // larger pan margins start clean; leaving restores the player's saved
    // office zoom/pan (so it isn't lost just because they ducked into build
    // mode) without ever stranding the office mid-pan. Must live in build()
    // directly — calling it from _buildOffice fails because that helper runs
    // inside ListenableBuilder's builder callback, after the ConsumerState
    // build has already returned.
    ref.listen<BuildModeState>(buildModeProvider, (prev, next) {
      if (prev?.active != next.active) {
        final target =
            next.active ? Matrix4.identity() : ref.read(officeViewProvider);
        if (_transformController.value != target) {
          _transformController.value = target;
        }
        if (_isGrabbing) {
          setState(() => _isGrabbing = false);
        }
      }
    });

    final activeAgents = service.gameState.isAutonomous
        ? <MapEntry<String, AgentState>>[]
        : agents.entries.where((e) => e.value.isActive).toList();

    final c = context.appColors;
    // ListenableBuilder rebuilds the entire body on every simulation frame
    // so character-following overlays (name labels, cat label) track motion
    // without us having to call setState() ourselves.
    return ListenableBuilder(
      listenable: service.frame,
      builder: (context, _) {
        // Slow tick (~3.3 Hz) for monitor flicker, status pulses and bubbles.
        // Derived from the per-frame counter so we don't need a second timer.
        final slowTick = service.frame.value ~/ 18;
        return Container(
          color: c.background,
          child: Column(
            children: [
              _buildHeader(agents),
              if (activeAgents.isNotEmpty)
                _ActiveAgentsStrip(agents: activeAgents, tick: slowTick),
              Expanded(child: _buildOffice(agents, gameEconomy, slowTick)),
            ],
          ),
        );
      },
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

  Widget _buildOffice(
      Map<String, AgentState> agents, GameState gameEconomy, int slowTick) {
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
              final ghostStatus = buildMode.active
                  ? _ghostStatus(buildMode, gameEconomy.placedRooms)
                  : null;
              final cursor = _buildModeCursor(buildMode, ghostStatus);
              final furnitureGhost = editMode
                  ? _resolveFurnitureGhost(gameEconomy)
                  : (item: null, col: null, row: null, valid: false);
              // Free auto-connect corridor — the SAME path previewed here and
              // built on commit (empty unless a valid room ghost is armed).
              final connectingCorridor = (buildMode.active &&
                      ghostStatus != null &&
                      ghostStatus.valid &&
                      buildMode.selectedRoomType != null)
                  ? _connectingCorridorForGhost(buildMode)
                  : const <({int col, int row})>[];
              return Stack(
                children: [
                  // Graphite "construction lot" backdrop — only painted in
                  // build mode so the regular hub keeps its theme background.
                  if (buildMode.active)
                    const Positioned.fill(
                      child: ColoredBox(color: _kBuildBackdrop),
                    ),
                  Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) {
                      if (buildMode.active &&
                          buildMode.selectedRoomType == null) {
                        setState(() => _isGrabbing = true);
                      }
                    },
                    onPointerUp: (_) {
                      if (_isGrabbing) setState(() => _isGrabbing = false);
                    },
                    onPointerCancel: (_) {
                      if (_isGrabbing) setState(() => _isGrabbing = false);
                    },
                    child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 3.0,
                    // Persist zoom/pan after each gesture so the office reopens
                    // where the player left it. Skip build mode — its transform
                    // is transient and reset on exit, never persisted.
                    onInteractionEnd: (_) {
                      if (!ref.read(buildModeProvider).active) {
                        ref
                            .read(officeViewProvider.notifier)
                            .save(_transformController.value);
                      }
                    },
                    // Pan room past the office bounds is what reveals the
                    // foundation buffer + graphite backdrop in build mode.
                    boundaryMargin: buildMode.active
                        ? const EdgeInsets.all(_kBuildPanMargin)
                        : EdgeInsets.zero,
                    child: MouseRegion(
                      cursor: cursor,
                      onHover: (event) {
                        _onCanvasHover(event.localPosition, constraints);
                        _updateBuildGhost(event.localPosition, constraints);
                        _updateFurnitureGhost(event.localPosition, constraints);
                      },
                      onExit: (_) {
                        setState(() {
                          _hoveredAgentId = null;
                          _foremanHovering = false;
                          _furnitureGhostTile = null;
                        });
                      },
                      child: GestureDetector(
                        // `onTapUp` (not `onTapDown`) so the tap handler only
                        // fires after the gesture arena confirms a tap won.
                        // Long-press is deliberately NOT bound — it was the
                        // delete affordance for placed furniture, but in
                        // practice it fired on any "slightly long" click and
                        // ate the pickup, deleting the item by accident.
                        // Delete now lives as an explicit button in the
                        // build menu, surfaced only while something is held.
                        onTapUp: (d) =>
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
                                  tick: slowTick,
                                  officeLevel: officeLevel,
                                  placedFurniture:
                                      gameEconomy.placedFurniture,
                                  placedRooms: gameEconomy.placedRooms,
                                  editMode: editMode,
                                  selectedFurnitureId:
                                      ref.watch(selectedFurnitureIdProvider),
                                  heldPlacedFurnitureIndex: ref.watch(
                                      heldPlacedFurnitureIndexProvider),
                                  buildMode: buildMode.active,
                                  ghostRoomType: editMode
                                      ? null
                                      : buildMode.selectedRoomType,
                                  ghostRoomCol: buildMode.ghostCol,
                                  ghostRoomRow: buildMode.ghostRow,
                                  ghostRoomRotation: buildMode.ghostRotation,
                                  ghostIsValid: _ghostStatus(buildMode,
                                          gameEconomy.placedRooms)
                                      .valid,
                                  adjacencyLabel: _adjacencyLabel(
                                      buildMode, gameEconomy.placedRooms),
                                  placedCorridors:
                                      gameEconomy.placedCorridors,
                                  corridorAnchorCol:
                                      buildMode.corridorAnchorCol,
                                  corridorAnchorRow:
                                      buildMode.corridorAnchorRow,
                                  connectingCorridorTiles: connectingCorridor,
                                  agentSpecializations: {
                                    for (final e
                                        in gameEconomy.agents.entries)
                                      if (e.value.specializations.isNotEmpty)
                                        e.key: e.value.specializations,
                                  },
                                  ghostFurnitureItem: furnitureGhost.item,
                                  ghostFurnitureCol: furnitureGhost.col,
                                  ghostFurnitureRow: furnitureGhost.row,
                                  ghostFurnitureValid: furnitureGhost.valid,
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
                                      tick: slowTick,
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
                                      hasUnassignedAgent: gameEconomy.agents
                                          .values
                                          .any((a) => a.workplaceStatus ==
                                              WorkplaceStatus.unassigned),
                                    ),
                                  ),
                                ),
                              ),
                            ..._buildNameOverlays(
                              agents,
                              constraints,
                              buildModeActive: buildMode.active,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                  const Positioned.fill(child: JanitorOverlay()),
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

        // Session presence banner — viewer/takeover overlay.
        const SessionBanner(),

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
          Builder(builder: (context) {
            final status =
                _ghostStatus(buildMode, gameEconomy.placedRooms);
            // The price the commit actually charges: a template bills its
            // furniture-inclusive bundle cost, a plain room bills rt.cost.
            final placeTemplateId = buildMode.selectedTemplateId;
            final placeTemplate = placeTemplateId != null
                ? roomTemplateById(placeTemplateId)
                : null;
            final commitRoomCost = placeTemplate != null
                ? placeTemplate.bundleCost(furnitureCatalog)
                : buildMode.selectedRoomType!.cost;
            return Positioned(
              left: 16,
              right: 16,
              bottom: (!wideMenu ? BuildMenu.kBottomSheetHeight : 0) + 12,
              child: _PlaceBar(
                roomType: buildMode.selectedRoomType!,
                roomCost: commitRoomCost,
                ghostIsValid: status.valid,
                ghostLive: buildMode.ghostCol != null,
                rotation: buildMode.ghostRotation,
                invalidReason: status.reason,
                onCancel: () =>
                    ref.read(buildModeProvider.notifier).clearSelection(),
                onRotateCW: () =>
                    ref.read(buildModeProvider.notifier).rotateClockwise(),
                onRotateCCW: () => ref
                    .read(buildModeProvider.notifier)
                    .rotateCounterClockwise(),
                onPlace: () {
                  final mode = ref.read(buildModeProvider);
                  final rooms = ref.read(gameEconomyProvider).placedRooms;
                  _commitRoomGhost(mode, _ghostStatus(mode, rooms));
                },
              ),
            );
          }),
      ],
      ),
    );
  }

  bool get _isZoomed =>
      _transformController.value.getMaxScaleOnAxis() > 1.01;

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    ref.read(officeViewProvider.notifier).reset();
  }

  /// Is a next-tier move-in affordable right now (drives the foreman/door
  /// renovation-attention cue)?
  bool _renovationAttention(GameState game) {
    return ref.read(gameEconomyProvider.notifier).canUpgradeOffice();
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
    final fit = _canvasFit(constraints);
    final worldX = (screenPos.dx - fit.offsetX) / fit.scale;
    final worldY = (screenPos.dy - fit.offsetY) / fit.scale;

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
        _handleBuildModeTap(pos, constraints);
      }
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
        ref.read(selectedAgentProvider.notifier).select(hit);
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
  /// Tap handler for placement / move / delete-room while in furniture edit
  /// mode. Pure decision logic lives in [decideEditModeTap] — this method
  /// builds the input snapshot from current state, then applies the
  /// resulting action through providers and the game notifier.
  void _handleEditModeTap(Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();

    final game = ref.read(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);
    final input = EditModeTapInput(
      col: col,
      row: row,
      gridCols: _gameState.gridCols,
      gridRows: _gameState.gridRows,
      blockedTiles: _gameState.blockedTiles,
      placedFurniture: game.placedFurniture,
      placedRooms: game.placedRooms,
      heldPlacedIndex: ref.read(heldPlacedFurnitureIndexProvider),
      selectedFurnitureId: ref.read(selectedFurnitureIdProvider),
      lookupItem: furnitureById,
    );

    final action = decideEditModeTap(input);
    switch (action) {
      case TapNoOp():
        return;
      case TapReleaseHold():
      case TapReleaseStaleHold():
        FurnitureEditModeCoord.releaseHold(ref);
        return;
      case TapPickUp(:final placedIndex):
        FurnitureEditModeCoord.enterMove(ref, placedIndex);
        return;
      case TapMoveHere(:final placedIndex, :final col, :final row):
        notifier.moveFurniture(placedIndex, col, row);
        FurnitureEditModeCoord.releaseHold(ref);
        return;
      case TapPlaceFromInventory(:final itemId, :final col, :final row):
        notifier.placeFurniture(itemId, col, row);
        if (ref.read(gameEconomyProvider).furnitureAvailable(itemId) <= 0) {
          FurnitureEditModeCoord.releaseHold(ref);
        }
        return;
      case TapRemoveRoom(:final roomId):
        notifier.removeRoom(roomId);
        return;
    }
  }

  // ─── Build Mode ────────────────────────────────────────────────────────────

  Offset _screenToWorld(Offset screenPos, BoxConstraints constraints) {
    final fit = _canvasFit(constraints);
    return Offset(
      (screenPos.dx - fit.offsetX) / fit.scale,
      (screenPos.dy - fit.offsetY) / fit.scale,
    );
  }

  /// Shared fit-to-viewport math used by [PixelOfficePainter] and every
  /// overlay / hit-test on this canvas. Owning a single source of truth here
  /// is load-bearing: a previous incarnation duplicated this math in four
  /// places, and characters appeared past the office wall whenever any
  /// off-by-one diverged (most visibly on Galley, where the deck is long and
  /// the sea fills the surrounding viewport). Includes the build-mode
  /// foundation buffer so the foundation tiles past the right/bottom walls
  /// stay clickable and labels stay anchored to their sprites while the
  /// painter shifts to accommodate the buffer.
  _CanvasFit _canvasFit(BoxConstraints constraints) {
    final cw = _gameState.canvasWidth.toDouble();
    final ch = _gameState.canvasHeight.toDouble();
    final scale = math.min(
      constraints.maxWidth / cw,
      constraints.maxHeight / ch,
    );
    return _CanvasFit(
      scale: scale,
      offsetX: (constraints.maxWidth - cw * scale) / 2,
      offsetY: (constraints.maxHeight - ch * scale) / 2,
    );
  }

  MouseCursor _buildModeCursor(BuildModeState mode, GhostStatus? status) =>
      buildModeCursor(
        buildActive: mode.active,
        hasGhost: mode.selectedRoomType != null,
        ghostValid: status?.valid ?? false,
        isGrabbing: _isGrabbing,
      );

  /// Build-mode ghost status — delegates the rules to the pure
  /// [computeGhostStatus] so the ghost colour, the Place-bar enable, and the
  /// commit gate can never disagree. Stage 4: the office is a fixed lot, so the
  /// ghost simply fits or it doesn't — no expansion plan to consult.
  GhostStatus _ghostStatus(BuildModeState mode, List<PlacedRoom> rooms) {
    final rt = mode.selectedRoomType;
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (rt == null || gc == null || gr == null) {
      return const GhostStatus.invalid(GhostInvalidReason.outOfBounds);
    }

    final econ = ref.read(gameEconomyProvider);

    // Cost the commit will actually charge: template bundle, or room cost.
    final templateId = mode.selectedTemplateId;
    final template = templateId != null ? roomTemplateById(templateId) : null;
    final roomCost =
        template != null ? template.bundleCost(furnitureCatalog) : rt.cost;

    return computeGhostStatus(BuildGhostInput(
      col: gc,
      row: gr,
      width: mode.ghostWidth,
      height: mode.ghostHeight,
      gridCols: _gameState.gridCols,
      gridRows: _gameState.gridRows,
      blockedTiles: _gameState.blockedTiles,
      rooms: rooms,
      roomCount: rooms.where((r) => r.type == rt).length,
      maxPerOffice: rt.maxPerOffice,
      grymni: econ.grymni,
      roomCost: roomCost,
    ));
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

  void _handleBuildModeTap(Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    final cursorCol = (world.dx / kTileSize).floor();
    final cursorRow = (world.dy / kTileSize).floor();

    final mode = ref.read(buildModeProvider);
    final notifier = ref.read(buildModeProvider.notifier);

    // ── Corridor placement — two-tap: anchor then endpoint ──────────────────
    if (mode.section == BuildSection.corridors) {
      final ac = mode.corridorAnchorCol;
      final ar = mode.corridorAnchorRow;
      if (ac == null || ar == null) {
        notifier.setCorridorAnchor(cursorCol, cursorRow);
        notifier.setGhost(col: cursorCol, row: cursorRow);
      } else {
        final path = _computeCorridorPath(ac, ar, cursorCol, cursorRow);
        final econ = ref.read(gameEconomyProvider.notifier);
        if (!_corridorPathValid(path)) {
          _showThrottledSnack(
              'corridor_invalid', 'Коридор не можна прокласти тут.');
        } else if (!econ.canPlaceCorridor(path, wide: mode.corridorWide)) {
          // Geometrically fine but unaffordable — give explicit ₲ feedback
          // instead of silently no-op'ing (parity with the room flow).
          final cost = econ.corridorCost(path, wide: mode.corridorWide);
          _showThrottledSnack(
              'corridor_cost', 'Недостатньо ₲: коридор коштує $cost.');
        } else {
          econ.placeCorridor(path, wide: mode.corridorWide);
        }
        notifier.clearCorridorAnchor();
      }
      return;
    }

    // ── Room / template placement ───────────────────────────────────────────
    // A tap ARMS / moves the ghost (center-anchored under the cursor). On
    // DESKTOP a click on a VALID spot also places immediately — hover already
    // positioned the ghost ("навів, зелене, клік, поставив"). On TOUCH the tap
    // only aims; the floating Place bar's button is the deliberate commit.
    if (mode.selectedRoomType == null) return;
    final tile = ghostTopLeft(
      cursorCol: cursorCol,
      cursorRow: cursorRow,
      width: mode.ghostWidth,
      height: mode.ghostHeight,
    );
    notifier.setGhost(col: tile.col, row: tile.row);

    if (_isDesktop) {
      final armed = ref.read(buildModeProvider);
      final status =
          _ghostStatus(armed, ref.read(gameEconomyProvider).placedRooms);
      if (status.valid) _commitRoomGhost(armed, status);
    }
  }

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// The free auto-connect corridor path for the current room ghost (empty if
  /// none or invalid). Computed against the rooms placed SO FAR — call it
  /// BEFORE the ghost's own room joins the list.
  List<({int col, int row})> _connectingCorridorForGhost(BuildModeState mode) {
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (gc == null || gr == null || mode.selectedRoomType == null) {
      return const [];
    }
    final path = connectingCorridorPath(
      footLeft: gc,
      footTop: gr,
      footRight: gc + mode.ghostWidth,
      footBottom: gr + mode.ghostHeight,
      rooms: ref.read(gameEconomyProvider).placedRooms,
      gridCols: _gameState.gridCols,
      gridRows: _gameState.gridRows,
    );
    return _corridorPathValid(path) ? path : const [];
  }

  /// The single room/template commit — shared by the Place button AND a
  /// desktop click on a valid ghost. Auto-connects the new room to its nearest
  /// neighbour with a free corridor.
  void _commitRoomGhost(BuildModeState mode, GhostStatus status) {
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (gc == null || gr == null || !status.valid) return;
    final econ = ref.read(gameEconomyProvider.notifier);

    // Resolve the corridor BEFORE the new room joins placedRooms (otherwise
    // the "nearest room" would be the room we're about to place).
    final corridor = _connectingCorridorForGhost(mode);

    final templateId = mode.selectedTemplateId;
    if (templateId != null) {
      final template = roomTemplateById(templateId);
      if (template != null) {
        econ.placeRoomTemplate(template, gc, gr, rotation: mode.ghostRotation);
      }
    } else {
      econ.placeRoom(mode.selectedRoomType!, gc, gr,
          rotation: mode.ghostRotation);
    }

    if (corridor.isNotEmpty) {
      econ.addConnectingCorridor(corridor);
    }
    ref.read(buildModeProvider.notifier).clearGhost();
  }

  /// Geometric validity for a corridor path: every tile must be inside the
  /// playable inner area, off any blocked tile, and not inside a room
  /// footprint (corridors connect rooms; they shouldn't run through them).
  bool _corridorPathValid(List<({int col, int row})> path) {
    if (path.isEmpty) return false;
    final gCols = _gameState.gridCols;
    final gRows = _gameState.gridRows;
    final blocked = _gameState.blockedTiles;
    final rooms = ref.read(gameEconomyProvider).placedRooms;
    for (final t in path) {
      if (t.col < 1 || t.row < 1 || t.col > gCols - 2 || t.row > gRows - 2) {
        return false;
      }
      if (blocked.contains('${t.col},${t.row}')) return false;
      for (final r in rooms) {
        if (t.col >= r.col &&
            t.col < r.col + r.footprintWidth &&
            t.row >= r.row &&
            t.row < r.row + r.footprintHeight) {
          return false;
        }
      }
    }
    return true;
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
    final cursorCol = (world.dx / kTileSize).floor();
    final cursorRow = (world.dy / kTileSize).floor();

    // Center-anchor multi-tile room footprints under the cursor. The old
    // top-left anchor made big rooms appear shifted down-and-right, and the
    // now-removed snap-to-edge made them leap to neighbours — both read as
    // "snaps somewhere unclear". Corridors / empty-hand track the raw tile.
    final tile = mode.selectedRoomType != null
        ? ghostTopLeft(
            cursorCol: cursorCol,
            cursorRow: cursorRow,
            width: mode.ghostWidth,
            height: mode.ghostHeight,
          )
        : (col: cursorCol, row: cursorRow);

    if (tile.col != mode.ghostCol || tile.row != mode.ghostRow) {
      ref
          .read(buildModeProvider.notifier)
          .setGhost(col: tile.col, row: tile.row);
    }
  }

  /// Mirrors the buy-mode ghost for the furniture edit flow: as long as the
  /// player has something in hand (held placed item OR selected inventory
  /// item), keep a hover-tile in widget state so the painter can render the
  /// translucent footprint that "follows" the cursor. Cleared when the hand
  /// is empty or edit mode is off, so the ghost disappears with the same
  /// gesture that emptied the hand (drop, cancel, exit).
  /// Resolves the held/selected furniture item under the ghost tile and runs
  /// the same placement validity check the tap handler uses, so the painter
  /// can colour the ghost green (will accept the drop) or red (will refuse).
  /// Returns nulls when nothing is in hand or the ghost tile is unset.
  ({FurnitureItem? item, int? col, int? row, bool valid})
      _resolveFurnitureGhost(GameState gameEconomy) {
    final tile = _furnitureGhostTile;
    if (tile == null) {
      return (item: null, col: null, row: null, valid: false);
    }
    final heldIdx = ref.watch(heldPlacedFurnitureIndexProvider);
    final selectedId = ref.watch(selectedFurnitureIdProvider);
    FurnitureItem? item;
    int? exclude;
    if (heldIdx != null &&
        heldIdx >= 0 &&
        heldIdx < gameEconomy.placedFurniture.length) {
      item = furnitureById(gameEconomy.placedFurniture[heldIdx].itemId);
      exclude = heldIdx;
    } else if (selectedId != null) {
      item = furnitureById(selectedId);
    }
    if (item == null) {
      return (item: null, col: null, row: null, valid: false);
    }
    final valid = canPlaceFurnitureAt(
      col: tile.col,
      row: tile.row,
      item: item,
      gridCols: _gameState.gridCols,
      gridRows: _gameState.gridRows,
      blockedTiles: _gameState.blockedTiles,
      placedFurniture: gameEconomy.placedFurniture,
      lookupItem: furnitureById,
      excludePlacedIndex: exclude,
    );
    return (item: item, col: tile.col, row: tile.row, valid: valid);
  }

  void _updateFurnitureGhost(Offset screenPos, BoxConstraints constraints) {
    if (!ref.read(furnitureEditModeProvider)) {
      if (_furnitureGhostTile != null) {
        setState(() => _furnitureGhostTile = null);
      }
      return;
    }
    final held = ref.read(heldPlacedFurnitureIndexProvider);
    final selected = ref.read(selectedFurnitureIdProvider);
    if (held == null && selected == null) {
      if (_furnitureGhostTile != null) {
        setState(() => _furnitureGhostTile = null);
      }
      return;
    }
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();
    if (_furnitureGhostTile?.col != col || _furnitureGhostTile?.row != row) {
      setState(() => _furnitureGhostTile = (col: col, row: row));
    }
  }


  bool _hitTestPlant(Offset screenPos, BoxConstraints constraints) {
    final fit = _canvasFit(constraints);
    final worldX = (screenPos.dx - fit.offsetX) / fit.scale;
    final worldY = (screenPos.dy - fit.offsetY) / fit.scale;

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
    BoxConstraints constraints, {
    bool buildModeActive = false,
  }) {
    final fit = _canvasFit(constraints);
    final scale = fit.scale;
    final offsetX = fit.offsetX;
    final offsetY = fit.offsetY;

    // Soft-clamped UI scale for floating nameplates. We don't want the
    // labels to grow past their design baseline (cap at 1.0) and we don't
    // want them to shrink past readability on heavily zoomed-out big offices
    // like the galley (floor at 0.55).
    final uiScale = scale.clamp(0.55, 1.0);

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

      final bannerW = 96 * uiScale;
      widgets.add(
        Positioned(
          left: screenX - bannerW / 2,
          top: screenY,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedAgentProvider.notifier).select(instanceId);
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
                width: bannerW,
                padding: EdgeInsets.symmetric(
                    vertical: 2 * uiScale, horizontal: 4 * uiScale),
                decoration: BoxDecoration(
                  color: highlighted
                      ? borderColor.withValues(alpha: 0.15)
                      : const Color(0xCC1A1A2E),
                  borderRadius: BorderRadius.circular(6 * uiScale),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: highlighted
                            ? const Color(0xFFFFC107)
                            : isActive
                                ? color
                                : Colors.white.withValues(alpha: 0.85),
                        fontSize: 9 * uiScale,
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
                        fontSize: 7 * uiScale,
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
                          fontSize: 7 * uiScale,
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

    // Foreman label (hidden during build mode)
    if (!buildModeActive) {
      final fCol = foremanColFor(_gameState.gridCols);
      final fRow = foremanRowFor(_gameState.gridRows);
      final fScreenX = offsetX + (fCol + 0.5) * kTileSize * scale;
      // Sprite bottom = (fRow + 1) * kTileSize + kForemanVertOffset; label 2 px below.
      final fScreenY = offsetY + ((fRow + 1) * kTileSize + kForemanVertOffset + 2) * scale;

      final foremanW = 80 * uiScale;
      widgets.add(
        Positioned(
          left: fScreenX - foremanW / 2,
          top: fScreenY,
          child: IgnorePointer(
            child: Container(
              width: foremanW,
              padding: EdgeInsets.symmetric(
                  vertical: 2 * uiScale, horizontal: 4 * uiScale),
              decoration: BoxDecoration(
                color: const Color(0xCC1A1A2E),
                borderRadius: BorderRadius.circular(6 * uiScale),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Text(
                'Фрімен',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFD700),
                  fontSize: 9 * uiScale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  shadows: const [
                    Shadow(color: Color(0xCC000000), blurRadius: 2),
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
/// Reason a ghost placement is invalid — surfaced to the Place Bar so the
/// player understands *why* the red rect appeared.
// GhostInvalidReason / GhostStatus / ghostInvalidReasonLabel moved to the pure,
// testable build_mode_logic.dart and re-exported from this library (see the
// `export` directive near the top) for existing importers.


class _PlaceBar extends StatelessWidget {
  final RoomType roomType;
  final bool ghostIsValid;
  final bool ghostLive;
  final int rotation;

  /// The cost the commit will actually charge for the room/template itself
  /// (plain room cost, or a template's furniture-inclusive bundle cost) — NOT
  /// the bare RoomType.cost, which understates templates.
  final int roomCost;

  /// Reason the ghost is invalid — surfaced as inline text so the player
  /// knows whether to move closer or free grymni.
  /// Null when ghost is valid or no specific reason was recorded.
  final GhostInvalidReason? invalidReason;
  final VoidCallback onCancel;
  final VoidCallback onRotateCW;
  final VoidCallback onRotateCCW;
  final VoidCallback onPlace;

  const _PlaceBar({
    required this.roomType,
    required this.ghostIsValid,
    required this.ghostLive,
    required this.rotation,
    required this.roomCost,
    this.invalidReason,
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
    final totalCost = roomCost;

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
                      '₲$totalCost',
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
                        ghostInvalidReasonLabel(invalidReason),
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
                    '₲$totalCost',
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


/// Resolves the cursor shown over the build-mode canvas.
///
/// Empty-handed: `grab` → `grabbing` so the player notices the office can be
/// dragged to reposition. Ghost in hand: `cell` for valid drops and
/// `forbidden` for invalid ones so the player sees at a glance whether the
/// next tap will land a room or no-op.
MouseCursor buildModeCursor({
  required bool buildActive,
  required bool hasGhost,
  required bool ghostValid,
  required bool isGrabbing,
}) {
  if (!buildActive) return MouseCursor.defer;
  if (!hasGhost) {
    return isGrabbing
        ? SystemMouseCursors.grabbing
        : SystemMouseCursors.grab;
  }
  if (ghostValid) return SystemMouseCursors.cell;
  return SystemMouseCursors.forbidden;
}

/// Result of fitting the office canvas into the available viewport. Shared by
/// the painter, overlay widgets, and hit-tests so the three never drift.
class _CanvasFit {
  final double scale;
  final double offsetX;
  final double offsetY;
  const _CanvasFit({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });
}
