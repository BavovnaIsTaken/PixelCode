/// Right panel: pixel-art office scene with animated agent characters.
///
/// Characters move around the office via BFS pathfinding, sit at desks
/// when active, and wander when idle — like a game.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/agent_provider.dart';
import '../../providers/build_mode_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/office_simulation_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import '../../services/agent_id_format.dart';
import 'build_menu.dart';
import 'character_sprites.dart';
import 'snap_logic.dart';
import 'foreman_overlay_painter.dart';
import 'office_game_state.dart';
import 'office_upgrade_dialog.dart';
import 'pixel_office_painter.dart';
import 'janitor_overlay.dart';
import 'pixel_sprites.dart';
import 'session_banner.dart';

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

  /// Foundation-buffer tile under the cursor, or null when the pointer is not
  /// over a buffer tile. Drives the hover/press wash in [PixelOfficePainter].
  ({int col, int row})? _hoveredBufferTile;
  bool _bufferTilePressed = false;

  /// 150 ms fade for the buffer hover wash. Forwards 0→1 on tile-enter,
  /// reverses on tile-exit so the colour swap doesn't pop.
  late final AnimationController _bufferHoverFade;

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
  /// "you can drag the office to peek at the buffer".
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
    _loadForemanIntroFlag();
    _bufferHoverFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() {
        if (mounted) setState(() {});
      });
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
    _bufferHoverFade.dispose();
    super.dispose();
  }

  bool _logExpanded = false;
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
    final agents = ref.watch(agentsProvider);
    final metrics = ref.watch(metricsProvider);
    final activityLog = ref.watch(activityLogProvider);
    final commEvents = ref.watch(commGraphProvider);
    final gameEconomy = ref.watch(gameEconomyProvider);

    // Reset zoom + pan transform on every entry/exit of build mode so a prior
    // session's pan doesn't carry over, and so leaving build mode never strands
    // the office mid-pan. Must live in build() directly — calling it from
    // _buildOffice fails because that helper runs inside ListenableBuilder's
    // builder callback, after the ConsumerState build has already returned.
    ref.listen<BuildModeState>(buildModeProvider, (prev, next) {
      if (prev?.active != next.active) {
        if (_transformController.value != Matrix4.identity()) {
          _transformController.value = Matrix4.identity();
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
              if (metrics.isNotEmpty) _TeamMetricsBar(metrics: metrics),
              if (commEvents.isNotEmpty) _CommGraphPanel(events: commEvents),
              _ActivityLogPanel(
                events: activityLog,
                expanded: _logExpanded,
                onToggle: () =>
                    setState(() => _logExpanded = !_logExpanded),
                onClear: () =>
                    ref.read(activityLogProvider.notifier).clear(),
              ),
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
                      if (buildMode.active &&
                          _bufferTileAt(e.localPosition, constraints) !=
                              null) {
                        if (!_bufferTilePressed) {
                          setState(() => _bufferTilePressed = true);
                        }
                      }
                    },
                    onPointerUp: (_) {
                      if (_isGrabbing) setState(() => _isGrabbing = false);
                      if (_bufferTilePressed) {
                        setState(() => _bufferTilePressed = false);
                      }
                    },
                    onPointerCancel: (_) {
                      if (_isGrabbing) setState(() => _isGrabbing = false);
                      if (_bufferTilePressed) {
                        setState(() => _bufferTilePressed = false);
                      }
                    },
                    child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 3.0,
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
                      },
                      onExit: (_) {
                        setState(() {
                          _hoveredAgentId = null;
                          _foremanHovering = false;
                          _hoveredBufferTile = null;
                          _bufferTilePressed = false;
                        });
                        if (_bufferHoverFade.value > 0) {
                          _bufferHoverFade.reverse();
                        }
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
                                  tick: slowTick,
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
                                  ghostIsValid: _ghostStatus(buildMode,
                                          gameEconomy.placedRooms)
                                      .valid,
                                  ghostPendingExpand: _ghostStatus(
                                          buildMode, gameEconomy.placedRooms)
                                      .pendingExpand,
                                  buildBufferCols:
                                      buildMode.active ? _bufferDims().cols : 0,
                                  buildBufferRows:
                                      buildMode.active ? _bufferDims().rows : 0,
                                  nextExpansionCost:
                                      gameEconomy.nextExpansion?.cost,
                                  hoveredBufferCol:
                                      _hoveredBufferTile?.col,
                                  hoveredBufferRow:
                                      _hoveredBufferTile?.row,
                                  bufferHoverAlpha: _bufferHoverFade.value,
                                  bufferHoverAffordable:
                                      (gameEconomy.nextExpansion?.cost ??
                                              1 << 30) <=
                                          gameEconomy.grymni,
                                  bufferHoverPressed: _bufferTilePressed,
                                  adjacencyLabel: _adjacencyLabel(
                                      buildMode, gameEconomy.placedRooms),
                                  placedCorridors:
                                      gameEconomy.placedCorridors,
                                  corridorAnchorCol:
                                      buildMode.corridorAnchorCol,
                                  corridorAnchorRow:
                                      buildMode.corridorAnchorRow,
                                  agentSpecializations: {
                                    for (final e
                                        in gameEconomy.agents.entries)
                                      if (e.value.specializations.isNotEmpty)
                                        e.key: e.value.specializations,
                                  },
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

        // Build-mode banner — diegetic affordance for the foundation buffer.
        // Shown whenever a room is selected in build mode so the player
        // notices the "drag past the wall to grow the office" mechanic.
        if (buildMode.active && buildMode.selectedRoomType != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: _BuildBanner(
                roomType: buildMode.selectedRoomType!,
                bufferAvailable:
                    _bufferDims().cols > 0 || _bufferDims().rows > 0,
                tierLabel: officeLevel.label,
                innerCols: _gameState.gridCols - 2,
                innerRows: _gameState.gridRows - 2,
              ),
            ),
          ),

        // Place Bar — floats above the build menu / above the canvas bottom
        // edge when a room type is selected and the ghost is live.
        if (buildMode.active && buildMode.selectedRoomType != null)
          Builder(builder: (context) {
            final status =
                _ghostStatus(buildMode, gameEconomy.placedRooms);
            final pendingCost =
                status.pendingExpand ? (status.plan?.totalCost ?? 0) : 0;
            return Positioned(
              left: 16,
              right: 16,
              bottom: (!wideMenu ? BuildMenu.kBottomSheetHeight : 0) + 12,
              child: _PlaceBar(
                roomType: buildMode.selectedRoomType!,
                ghostIsValid: status.valid,
                ghostLive: buildMode.ghostCol != null,
                rotation: buildMode.ghostRotation,
                pendingExpandCost: pendingCost,
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
                  final curStatus = _ghostStatus(mode, rooms);
                  if (mode.ghostCol == null || !curStatus.valid) {
                    return;
                  }
                  final econ = ref.read(gameEconomyProvider.notifier);
                  final extraSteps =
                      curStatus.plan?.extraSteps ?? 0;
                  final templateId = mode.selectedTemplateId;
                  if (templateId != null) {
                    final template = roomTemplateById(templateId);
                    if (template != null) {
                      econ.placeRoomTemplate(
                        template,
                        mode.ghostCol!,
                        mode.ghostRow!,
                        rotation: mode.ghostRotation,
                        expansionStepsToBuy: extraSteps,
                      );
                    }
                  } else {
                    econ.placeRoom(
                      mode.selectedRoomType!,
                      mode.ghostCol!,
                      mode.ghostRow!,
                      rotation: mode.ghostRotation,
                      expansionStepsToBuy: extraSteps,
                    );
                  }
                  ref.read(buildModeProvider.notifier).clearGhost();
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
    _updateBufferHover(pos, constraints, isBuildMode);
  }

  /// Detect which foundation-buffer tile (if any) the pointer sits over in
  /// build mode and drive the 150 ms hover fade. Outside the buffer we run
  /// the controller in reverse so the previous tile fades out cleanly.
  void _updateBufferHover(
      Offset screenPos, BoxConstraints constraints, bool isBuildMode) {
    if (!isBuildMode) {
      if (_hoveredBufferTile != null || _bufferTilePressed) {
        setState(() {
          _hoveredBufferTile = null;
          _bufferTilePressed = false;
        });
      }
      if (_bufferHoverFade.value > 0) _bufferHoverFade.reverse();
      return;
    }
    final tile = _bufferTileAt(screenPos, constraints);
    if (tile == null) {
      if (_hoveredBufferTile != null) {
        setState(() => _hoveredBufferTile = null);
      }
      if (_bufferTilePressed) setState(() => _bufferTilePressed = false);
      if (_bufferHoverFade.value > 0) _bufferHoverFade.reverse();
      return;
    }
    if (_hoveredBufferTile?.col != tile.col ||
        _hoveredBufferTile?.row != tile.row) {
      setState(() => _hoveredBufferTile = tile);
    }
    if (_bufferHoverFade.status != AnimationStatus.forward &&
        _bufferHoverFade.value < 1.0) {
      _bufferHoverFade.forward();
    }
  }

  /// Returns the (col, row) of the foundation-buffer tile under [screenPos],
  /// or null when the pointer is over the owned grid, outside the buffer, or
  /// build mode is inactive. Mirrors `_drawFoundationBuffer` so visuals and
  /// hit-tests can't drift.
  ({int col, int row})? _bufferTileAt(
      Offset screenPos, BoxConstraints constraints) {
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();
    final buf = _bufferDims();
    if (buf.cols == 0 && buf.rows == 0) return null;
    final gCols = _gameState.gridCols;
    final gRows = _gameState.gridRows;
    final startCol = gCols - 1;
    final endCol = gCols - 1 + buf.cols;
    final startRow = gRows - 1;
    final endRow = gRows - 1 + buf.rows;
    if (col < 0 || row < 0 || col > endCol || row > endRow) return null;
    final inRightStrip = col >= startCol && col <= endCol && row <= endRow;
    final inBottomStrip = row >= startRow && row <= endRow && col < startCol;
    if (!inRightStrip && !inBottomStrip) return null;
    return (col: col, row: row);
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
    // Deselect once inventory for this item is exhausted.
    if (ref.read(gameEconomyProvider).furnitureAvailable(selectedId) <= 0) {
      ref.read(selectedFurnitureIdProvider.notifier).state = null;
    }
  }

  // ─── Build Mode ────────────────────────────────────────────────────────────

  Offset _screenToWorld(Offset screenPos, BoxConstraints constraints) {
    // Mirror painter.paint(): include any active build-buffer in the canvas
    // dims so taps in the foundation-buffer area map to correct world coords.
    final buildMode = ref.read(buildModeProvider);
    final buf = buildMode.active ? _bufferDims() : (cols: 0, rows: 0);
    final cw = _gameState.canvasWidth + buf.cols * kTileSize;
    final ch = _gameState.canvasHeight + buf.rows * kTileSize;
    final scale = math.min(
        constraints.maxWidth / cw, constraints.maxHeight / ch);
    final ox = (constraints.maxWidth - cw * scale) / 2;
    final oy = (constraints.maxHeight - ch * scale) / 2;
    return Offset(
        (screenPos.dx - ox) / scale, (screenPos.dy - oy) / scale);
  }

  /// Number of foundation-buffer tiles drawn past each owned grid edge in
  /// build mode. Lets the player ghost-place outside the owned area; the
  /// transaction then auto-buys the required expansion step(s).
  static const int kBuildBufferTiles = 4;

  MouseCursor _buildModeCursor(BuildModeState mode, _GhostStatus? status) =>
      buildModeCursor(
        buildActive: mode.active,
        hasGhost: mode.selectedRoomType != null,
        ghostValid: status?.valid ?? false,
        ghostPendingExpand: status?.pendingExpand ?? false,
        isGrabbing: _isGrabbing,
      );

  /// Build-mode ghost status — tri-state with optional expansion plan.
  /// `pendingExpand` means the ghost is in the foundation buffer outside
  /// the owned grid; commit will trigger a combined expand+place transaction.
  bool _ghostIsValid(BuildModeState mode, List<PlacedRoom> rooms) =>
      _ghostStatus(mode, rooms).valid;

  _GhostStatus _ghostStatus(BuildModeState mode, List<PlacedRoom> rooms) {
    final rt = mode.selectedRoomType;
    final gc = mode.ghostCol;
    final gr = mode.ghostRow;
    if (rt == null || gc == null || gr == null) {
      return const _GhostStatus.invalid(GhostInvalidReason.outOfBounds);
    }

    final gCols = _gameState.gridCols;
    final gRows = _gameState.gridRows;
    final gw = mode.ghostWidth;
    final gh = mode.ghostHeight;

    // Reject left/top out-of-bounds — owned grid never extends in those
    // directions, expansions only grow right and bottom.
    if (gc < 1 || gr < 1) {
      return const _GhostStatus.invalid(GhostInvalidReason.outOfBounds);
    }

    // Overlap with existing rooms.
    for (final r in rooms) {
      final ox = gc < r.col + r.footprintWidth && gc + gw > r.col;
      final oy = gr < r.row + r.footprintHeight && gr + gh > r.row;
      if (ox && oy) {
        return const _GhostStatus.invalid(GhostInvalidReason.overlap);
      }
    }

    // Need this ghost to fit inside playable inner area (excluding 1-tile
    // walls on right and bottom). Compute minimum effective grid size that
    // would contain it.
    final neededCols = gc + gw + 1; // +1 for right wall column
    final neededRows = gr + gh + 1; // +1 for bottom wall row
    final neededInnerCols = neededCols - 2;
    final neededInnerRows = neededRows - 2;

    final fitsOwned = (gc + gw <= gCols - 1) && (gr + gh <= gRows - 1);

    // Overlap with blocked tiles (chairs, foreman, etc.) — only relevant when
    // ghost lies inside the currently owned playable area. Buffer tiles have
    // no blocked entries yet.
    if (fitsOwned) {
      final blocked = _gameState.blockedTiles;
      for (int dc = 0; dc < gw; dc++) {
        for (int dr = 0; dr < gh; dr++) {
          if (blocked.contains('${gc + dc},${gr + dr}')) {
            return const _GhostStatus.invalid(GhostInvalidReason.blocked);
          }
        }
      }
      return const _GhostStatus.valid();
    }

    // Ghost extends past the owned grid → consult expansion plan.
    final econ = ref.read(gameEconomyProvider);
    final plan = econ.officeLevel.computeExpansionPlan(
      econ.officeExpansions,
      neededInnerCols,
      neededInnerRows,
    );
    if (!plan.reachable) {
      return const _GhostStatus.invalid(GhostInvalidReason.tierCeiling);
    }

    // Clamp ghost to the visual buffer window so absurd placements far past
    // the buffer don't slip through as valid. Buffer is dynamic and grows
    // with the selected ghost (see _bufferDims).
    final buf = _bufferDims();
    if (gc + gw > gCols - 1 + buf.cols + 1) {
      return const _GhostStatus.invalid(GhostInvalidReason.bufferOverrun);
    }
    if (gr + gh > gRows - 1 + buf.rows + 1) {
      return const _GhostStatus.invalid(GhostInvalidReason.bufferOverrun);
    }

    // Must also have the grymni to cover the expansion cost.
    if (econ.grymni < plan.totalCost + rt.cost) {
      return const _GhostStatus.invalid(
          GhostInvalidReason.insufficientGrymni);
    }

    return _GhostStatus.pendingExpand(plan);
  }

  /// Buffer dimensions to render past each owned edge — clamped by the tier's
  /// remaining expansion capacity so we don't draw a buffer the player can
  /// never reach. When a room is selected in build mode, the buffer grows to
  /// at least `ghost.size + 1` so even a 7-wide teamFloor can be ghosted past
  /// the right wall and attached.
  ({int cols, int rows}) _bufferDims() {
    final econ = ref.read(gameEconomyProvider);
    final maxCols =
        econ.officeLevel.effectiveCols(econ.officeLevel.expansions.length);
    final maxRows =
        econ.officeLevel.effectiveRows(econ.officeLevel.expansions.length);
    final curCols = _gameState.gridCols;
    final curRows = _gameState.gridRows;

    final mode = ref.read(buildModeProvider);
    final ghostW = mode.ghostWidth;
    final ghostH = mode.ghostHeight;

    final requestedCols = math.max(kBuildBufferTiles, ghostW + 1);
    final requestedRows = math.max(kBuildBufferTiles, ghostH + 1);

    final cols = math.min(requestedCols, maxCols - curCols);
    final rows = math.min(requestedRows, maxRows - curRows);
    return (cols: cols < 0 ? 0 : cols, rows: rows < 0 ? 0 : rows);
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

  /// Direct one-click expansion purchase from a foundation-buffer tile. Honours
  /// the same affordance the hover wash signals: green = bought, red = not
  /// enough grymni → user-visible toast.
  void _tryBuyExpansionAtTap() {
    final econNotifier = ref.read(gameEconomyProvider.notifier);
    final econ = ref.read(gameEconomyProvider);
    final next = econ.nextExpansion;
    if (next == null) {
      _showThrottledSnack(
        'expansion_maxed',
        'Цей рівень офісу вже розширено максимально.',
      );
      return;
    }
    if (!econNotifier.canBuyOfficeExpansion()) {
      _showThrottledSnack(
        'expansion_insufficient',
        'Недостатньо ₲: потрібно ${next.cost}, є ${econ.grymni}.',
      );
      return;
    }
    econNotifier.buyOfficeExpansion();
    _showThrottledSnack(
      'expansion_bought',
      'Територію розширено! −${next.cost}₲',
      cooldown: const Duration(seconds: 1),
    );
  }

  void _handleBuildModeTap(Offset screenPos, BoxConstraints constraints,
      List<PlacedRoom> rooms) {
    final world = _screenToWorld(screenPos, constraints);
    final col = (world.dx / kTileSize).floor();
    final row = (world.dy / kTileSize).floor();

    final mode = ref.read(buildModeProvider);
    final notifier = ref.read(buildModeProvider.notifier);

    // ── Direct expansion purchase ──────────────────────────────────────────
    // No room/corridor in hand and tap is on a foundation-buffer tile → buy
    // the next expansion step outright (no room placement required). Lets the
    // player just "click the lot" they want, which is what the green/red hover
    // wash already promised them.
    if (mode.selectedRoomType == null &&
        mode.section != BuildSection.corridors &&
        _bufferTileAt(screenPos, constraints) != null) {
      _tryBuyExpansionAtTap();
      return;
    }

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

    // Apply snap-to-edge logic for room templates and regular rooms.
    // Uses rotation-aware ghost footprint and also snaps against corridors.
    if (mode.selectedRoomType != null) {
      final ghostCols = mode.ghostWidth;
      final ghostRows = mode.ghostHeight;
      final econ = ref.read(gameEconomyProvider);

      col = snapGhostCol(col, row, ghostCols, ghostRows, econ.placedRooms,
          placedCorridors: econ.placedCorridors);
      row = snapGhostRow(col, row, ghostCols, ghostRows, econ.placedRooms,
          placedCorridors: econ.placedCorridors);
    }

    if (col != mode.ghostCol || row != mode.ghostRow) {
      ref.read(buildModeProvider.notifier).setGhost(col: col, row: row);
    }
  }


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
    BoxConstraints constraints, {
    bool buildModeActive = false,
  }) {
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
                width: 96,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

    // Foreman label (hidden during build mode)
    if (!buildModeActive) {
      final fCol = foremanColFor(_gameState.gridCols);
      final fRow = foremanRowFor(_gameState.gridRows);
      final fScreenX = offsetX + (fCol + 0.5) * kTileSize * scale;
      // Sprite bottom = (fRow + 1) * kTileSize + kForemanVertOffset; label 2 px below.
      final fScreenY = offsetY + ((fRow + 1) * kTileSize + kForemanVertOffset + 2) * scale;

      widgets.add(
        Positioned(
          left: fScreenX - 40,
          top: fScreenY,
          child: IgnorePointer(
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xCC1A1A2E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: const Text(
                'Фрімен',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  shadows: [
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
enum GhostInvalidReason {
  /// Ghost lies in the left/top out-of-bounds halo (col<1 or row<1).
  outOfBounds,

  /// Ghost overlaps an already-placed room.
  overlap,

  /// Ghost overlaps a blocked tile (chair, foreman, decor) inside owned grid.
  blocked,

  /// Ghost extends past the tier's hard ceiling. Player must buy an office
  /// tier upgrade (in the shop) to expand further.
  tierCeiling,

  /// Ghost extends past the visible foundation buffer window. Player must
  /// move the ghost closer to the owned grid.
  bufferOverrun,

  /// Player doesn't have enough grymni to pay for the expansion + room.
  insufficientGrymni,
}

/// Tri-state ghost validity used by build mode.
///
/// - `valid` — fits inside currently owned grid, no overlap, affordable.
/// - `pendingExpand` — fits in foundation buffer outside owned grid; commit
///    triggers a combined expand+place transaction. `plan` holds the cost.
/// - `invalid` — out of bounds, overlaps, exceeds tier capacity, or
///    unaffordable. UI renders red ghost. `reason` holds the specific cause
///    for surfacing in the Place Bar.
class _GhostStatus {
  final bool valid;
  final bool pendingExpand;
  final PendingExpansionPlan? plan;
  final GhostInvalidReason? reason;

  const _GhostStatus.valid()
      : valid = true,
        pendingExpand = false,
        plan = null,
        reason = null;

  const _GhostStatus.invalid(this.reason)
      : valid = false,
        pendingExpand = false,
        plan = null;

  const _GhostStatus.pendingExpand(this.plan)
      : valid = true,
        pendingExpand = true,
        reason = null;
}

/// Banner overlay shown at the top of the canvas during build mode. Teaches
/// the "drag past the wall to grow the office" affordance — without this,
/// players who fill the office can't discover that the gold buffer beyond
/// the wall is an actual placement zone that auto-buys an expansion step.
class _BuildBanner extends StatelessWidget {
  final RoomType roomType;
  final bool bufferAvailable;
  final String tierLabel;
  final int innerCols;
  final int innerRows;

  const _BuildBanner({
    required this.roomType,
    required this.bufferAvailable,
    required this.tierLabel,
    required this.innerCols,
    required this.innerRows,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final amber = const Color(0xFFFFB020);

    final message = bufferAvailable
        ? 'Тягни «${roomType.nameUk}» у золоту зону за стіною — офіс розшириться сам'
        : 'Офіс на максимумі цього тіру. Купи апгрейд офісу через сторожа коло вхідних дверей';
    final subtitle = '$tierLabel • $innerCols×$innerRows клітинок';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: amber.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: 0.25),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            bufferAvailable
                ? Icons.arrow_outward
                : Icons.upgrade_outlined,
            color: amber,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: c.textHigh,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.textHigh.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
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

class _PlaceBar extends StatelessWidget {
  final RoomType roomType;
  final bool ghostIsValid;
  final bool ghostLive;
  final int rotation;

  /// Expansion-step cost paid alongside the room when the ghost is in the
  /// foundation buffer. Zero when no expansion is needed.
  final int pendingExpandCost;

  /// Reason the ghost is invalid — surfaced as inline text so the player
  /// knows whether to move closer, free grymni, or buy a tier upgrade.
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
    this.pendingExpandCost = 0,
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
    final isPendingExpand = pendingExpandCost > 0;
    final totalCost = roomType.cost + pendingExpandCost;

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
                        color: isPendingExpand
                            ? const Color(0xFFFFB020)
                            : c.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isPendingExpand) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(₲${roomType.cost} + ₲$pendingExpandCost розширення)',
                        style: TextStyle(
                          color: const Color(0xFFFFB020).withValues(alpha: 0.85),
                          fontSize: 9,
                        ),
                      ),
                    ],
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
                _buildChip(entry.key, entry.value),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String agentId, AgentMetrics m) {
    return _MetricChip(
      label: shortAgentLabel(agentId),
      color: agentAccentColor(agentRoleOf(agentId)),
      assigned: m.tasksAssigned,
      completed: m.tasksCompleted,
      rework: m.reworkCount,
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

/// Resolves the cursor shown over the build-mode canvas.
///
/// Empty-handed: `grab` → `grabbing` so the player notices the office can be
/// dragged to peek at the foundation buffer. Ghost in hand: `cell` for valid
/// drops and `forbidden` for invalid ones so the player sees at a glance
/// whether the next tap will land a room or no-op.
MouseCursor buildModeCursor({
  required bool buildActive,
  required bool hasGhost,
  required bool ghostValid,
  required bool ghostPendingExpand,
  required bool isGrabbing,
}) {
  if (!buildActive) return MouseCursor.defer;
  if (!hasGhost) {
    return isGrabbing
        ? SystemMouseCursors.grabbing
        : SystemMouseCursors.grab;
  }
  if (ghostValid || ghostPendingExpand) return SystemMouseCursors.cell;
  return SystemMouseCursors.forbidden;
}

/// Maps an invalid-ghost reason to the short Ukrainian label shown in the
/// Place Bar. Pure function for trivial unit testing — surfaces *why* the
/// red ghost appeared so the player knows what to do next.
String ghostInvalidReasonLabel(GhostInvalidReason? reason) {
  if (reason == null) return 'не вміщується';
  switch (reason) {
    case GhostInvalidReason.outOfBounds:
      return 'за межами офісу';
    case GhostInvalidReason.overlap:
      return 'перекриває кімнату';
    case GhostInvalidReason.blocked:
      return 'на меблях чи персоналі';
    case GhostInvalidReason.tierCeiling:
      return 'потрібен апгрейд офісу';
    case GhostInvalidReason.bufferOverrun:
      return 'занадто далеко — підсуньте ближче';
    case GhostInvalidReason.insufficientGrymni:
      return 'не вистачає ₲';
  }
}
