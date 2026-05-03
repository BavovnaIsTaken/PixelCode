/// Office game state — manages the tile-based office with animated characters.
///
/// Ported from pixel-agents TypeScript implementation.
/// Characters have FSM states (idle, walk, type), pathfind via BFS,
/// and wander around when inactive.
library;

import 'dart:math';

import '../../models/agent_message.dart';
import '../../models/game_economy.dart';
import '../../providers/agent_provider.dart';
import 'character_accessories.dart';

// ─── Constants ──────────────────────────────────────────────────────────────

const int kGridCols = 20;
const int kGridRows = 14;
const double kTileSize = 16.0;

/// Virtual canvas dimensions.
const double kCanvasWidth = kGridCols * kTileSize; // 320
const double kCanvasHeight = kGridRows * kTileSize; // 224

/// Maximum combined walk-speed multiplier from room effects.
///
/// Guards the workstation↔serverRoom adjacency pairs + wide-corridor bonus
/// from unbounded stacking. When the agent `speed` stat eventually affects
/// task-dispatch timing, that formula must also reference this ceiling so the
/// combined (stat × room) multiplier stays sane (D.1 interaction guard).
const double kSpeedBonusCeiling = 1.35;

// Character animation timing
const double kWalkSpeedPxPerSec = 48.0;
const double kWalkFrameDuration = 0.15;
const double kTypeFrameDuration = 0.3;

// Wander AI
const double kWanderPauseMin = 3.0;
const double kWanderPauseMax = 15.0;
const int kWanderMovesMin = 3;
const int kWanderMovesMax = 6;
const double kSeatRestMin = 30.0;
const double kSeatRestMax = 90.0;

// Rendering offsets
const double kSittingOffsetPx = 6.0;
const double kCharZSortOffset = 0.5;

// Cat AI
const double kCatWalkSpeed = 32.0;
const double kCatWalkFrameDuration = 0.12;
const double kCatIdlePauseMin = 2.0;
const double kCatIdlePauseMax = 8.0;
const double kCatSleepMin = 15.0;
const double kCatSleepMax = 40.0;
const double kCatSleepOnDeskChance = 0.3;

// Coffee machine (2 tiles wide, against the wall)
const int kCoffeeMachineCol = 13;
const int kCoffeeMachineRow = 1;
const int kCoffeeMachineCol2 = 14; // second tile
// Snack table next to coffee machine
const int kSnackTableCol = 15;
const int kSnackTableRow = 1;

// Foreman — anchors onto the bottom wall row at the right edge. He's
// "outside the office" visually: feet rest on the wall strip, upper body
// overhangs into the last floor row. Inline helpers so the painter, hit-
// test, and blockedTiles all compute the same tile from current grid dims.
int foremanColFor(int gridCols) => gridCols - 1;
int foremanRowFor(int gridRows) => gridRows - 1;
/// Extra downward shift applied to the foreman sprite and its hit-rect
/// so he stands 1/3 tile lower within his anchor tile.
const double kForemanVertOffset = kTileSize / 3;
const double kCoffeeBrewDuration = 6.0;

// Skateboard
const double kSkateboardSpeed = 96.0;
const double kSkateboardChance = 0.2;
const double kSkateMountDuration = 0.8;
const double kSkateDismountDuration = 0.6;
const double kSkateRideFrameDuration = 0.25;
// A skate ride chains this many waypoints so the character laps the office
// instead of rolling three tiles — picked so total path ≈ 5× a normal wander.
const int kSkateWaypointCount = 5;
const int kSkateWaypointSamples = 12;

// Coffee
const double kCoffeeWalkChance = 0.15;
const double kCoffeeDrinkDuration = 20.0;
const double kCoffeeSkateChance = 0.05;

// Plant easter egg
const double kPlantAnimDuration = 3.0;
const double kPlantBounceSpeed = 8.0;

// Chat interaction
const double kChatMinDuration = 4.0;
const double kChatMaxDuration = 9.0;
const double kChatCooldownMin = 30.0;
const double kChatCooldownMax = 90.0;
/// Probability each second an eligible idle character rolls for initiating
/// a chat with a nearby teammate.
const double kChatStartChancePerSec = 0.12;
const double kChatScanInterval = 0.5;

// ─── Enums ──────────────────────────────────────────────────────────────────

enum TileType { wall, floor }

enum CharDirection { down, left, right, up }

enum CharState { idle, walk, typing, skateMount, skateDismount, waiting }

enum CatAction { idle, walk, sleep }

// ─── Tile position ──────────────────────────────────────────────────────────

class TilePos {
  final int col;
  final int row;
  const TilePos(this.col, this.row);
}

// ─── Desk stations ──────────────────────────────────────────────────────────

class DeskStation {
  final String agentId;
  final int deskCol;
  final int deskRow;
  final int seatCol;
  final int seatRow;
  final CharDirection facingDir;
  /// True for stations created from placed workstation rooms (not canonical).
  final bool isExtra;

  const DeskStation({
    required this.agentId,
    required this.deskCol,
    required this.deskRow,
    required this.seatCol,
    required this.seatRow,
    required this.facingDir,
    this.isExtra = false,
  });
}

/// 7 desk stations in the office.
/// Manager: top center.
/// Row 1: Tech Lead, Coder, Reviewer.
/// Row 2: Tester, Security, UI/UX Designer.
const kStations = <DeskStation>[
  DeskStation(
    agentId: 'manager',
    deskCol: 9, deskRow: 3,
    seatCol: 9, seatRow: 4,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'tech-lead',
    deskCol: 3, deskRow: 6,
    seatCol: 3, seatRow: 7,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'coder',
    deskCol: 9, deskRow: 6,
    seatCol: 9, seatRow: 7,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'reviewer',
    deskCol: 15, deskRow: 6,
    seatCol: 15, seatRow: 7,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'tester',
    deskCol: 3, deskRow: 9,
    seatCol: 3, seatRow: 10,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'security',
    deskCol: 9, deskRow: 9,
    seatCol: 9, seatRow: 10,
    facingDir: CharDirection.up,
  ),
  DeskStation(
    agentId: 'ui-ux-designer',
    deskCol: 15, deskRow: 9,
    seatCol: 15, seatRow: 10,
    facingDir: CharDirection.up,
  ),
];

// ─── Game character ─────────────────────────────────────────────────────────

class GameCharacter {
  /// Stable unique identity (e.g. "coder#2"). Used as the map key and for
  /// matching against selection / agent-state / position-sync messages.
  final String instanceId;

  /// Which role this character belongs to (e.g. "coder"). Used for palette,
  /// accent color, and station assignment — many instances can share a role.
  final String roleType;

  final CharCosmetics cosmetics;
  int get paletteIndex => cosmetics.paletteIndex;

  CharState state;
  CharDirection dir;
  double x, y;
  int tileCol, tileRow;
  List<TilePos> path;
  double moveProgress;
  int frame;
  double frameTimer;
  double wanderTimer;
  int wanderCount;
  int wanderLimit;
  bool isActive;
  bool isReading;
  bool isHired;
  HardwareTier hardware;
  AgentStatus displayStatus;
  double seatTimer;
  DeskStation? seat;
  bool isOnSkateboard;
  bool hasCoffee;
  double coffeeTimer;

  // Chat interaction state
  bool isChatting;
  double chatTimer;
  double chatCooldown;
  String? chatPartnerId;

  GameCharacter({
    required this.instanceId,
    required this.roleType,
    required this.seat,
    this.state = CharState.typing,
    CharDirection? dir,
    double? x,
    double? y,
    int? tileCol,
    int? tileRow,
    this.isActive = false,
    this.seatTimer = 0,
    this.isOnSkateboard = false,
    this.hasCoffee = false,
    this.coffeeTimer = 0,
    this.isChatting = false,
    this.chatTimer = 0,
    double? chatCooldown,
    this.chatPartnerId,
  })  : cosmetics = cosmeticsFor(instanceId, roleType),
        dir = dir ?? seat?.facingDir ?? CharDirection.down,
        x = x ??
            (seat != null
                ? seat.seatCol * kTileSize + kTileSize / 2
                : kTileSize * 2),
        y = y ??
            (seat != null
                ? seat.seatRow * kTileSize + kTileSize / 2
                : kTileSize * 2),
        tileCol = tileCol ?? seat?.seatCol ?? 2,
        tileRow = tileRow ?? seat?.seatRow ?? 2,
        path = [],
        moveProgress = 0,
        frame = 0,
        frameTimer = 0,
        wanderTimer = _randomRange(kWanderPauseMin, kWanderPauseMax),
        wanderCount = 0,
        wanderLimit = _randomInt(kWanderMovesMin, kWanderMovesMax),
        isReading = false,
        isHired = true,
        hardware = HardwareTier.oldLaptop,
        displayStatus = AgentStatus.idle,
        chatCooldown = chatCooldown ?? _randomRange(8.0, 20.0);
}

// ─── Office cat ────────────────────────────────────────────────────────────

class OfficeCat {
  CatAction state;
  CharDirection dir;
  double x, y;
  int tileCol, tileRow;
  List<TilePos> path;
  double moveProgress;
  int frame;
  double frameTimer;
  double stateTimer;
  int wanderCount;
  String? sleepDeskAgent;

  OfficeCat({int startCol = 12, int startRow = 5})
      : state = CatAction.idle,
        dir = CharDirection.down,
        x = startCol * kTileSize + kTileSize / 2,
        y = startRow * kTileSize + kTileSize / 2,
        tileCol = startCol,
        tileRow = startRow,
        path = [],
        moveProgress = 0,
        frame = 0,
        frameTimer = 0,
        stateTimer = _randomRange(kCatIdlePauseMin, kCatIdlePauseMax),
        wanderCount = 0;
}

// ─── Plant easter egg state ────────────────────────────────────────────────

class PlantEasterEgg {
  /// Active bounce timers keyed by placement tile `"col,row"`.
  final Map<String, double> activeTimers = {};
}

// ─── Utilities ──────────────────────────────────────────────────────────────

final _rng = Random();

double _randomRange(double min, double max) =>
    min + _rng.nextDouble() * (max - min);

int _randomInt(int min, int max) => min + _rng.nextInt(max - min + 1);

CharDirection _directionBetween(
  int fromCol, int fromRow,
  int toCol, int toRow,
) {
  final dc = toCol - fromCol;
  final dr = toRow - fromRow;
  if (dc > 0) return CharDirection.right;
  if (dc < 0) return CharDirection.left;
  if (dr > 0) return CharDirection.down;
  return CharDirection.up;
}

// ─── Pathfinding ────────────────────────────────────────────────────────────

bool _isWalkable(
  int col, int row,
  List<List<TileType>> tileMap,
  Set<String> blocked,
) {
  if (row < 0 || row >= tileMap.length) return false;
  if (col < 0 || col >= tileMap[0].length) return false;
  if (tileMap[row][col] == TileType.wall) return false;
  if (blocked.contains('$col,$row')) return false;
  return true;
}

List<TilePos> _findPath(
  int startCol, int startRow,
  int endCol, int endRow,
  List<List<TileType>> tileMap,
  Set<String> blocked,
) {
  if (startCol == endCol && startRow == endRow) return [];
  if (!_isWalkable(endCol, endRow, tileMap, blocked)) return [];

  final startKey = '$startCol,$startRow';
  final endKey = '$endCol,$endRow';
  final visited = <String>{startKey};
  final parent = <String, String>{};
  final queue = <TilePos>[TilePos(startCol, startRow)];

  while (queue.isNotEmpty) {
    final curr = queue.removeAt(0);
    final currKey = '${curr.col},${curr.row}';

    if (currKey == endKey) {
      final path = <TilePos>[];
      var k = endKey;
      while (k != startKey) {
        final parts = k.split(',');
        path.insert(0, TilePos(int.parse(parts[0]), int.parse(parts[1])));
        k = parent[k]!;
      }
      return path;
    }

    for (final d in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
      final nc = curr.col + d.$1;
      final nr = curr.row + d.$2;
      final nk = '$nc,$nr';
      if (visited.contains(nk)) continue;
      if (!_isWalkable(nc, nr, tileMap, blocked)) continue;
      visited.add(nk);
      parent[nk] = currKey;
      queue.add(TilePos(nc, nr));
    }
  }

  return [];
}

// ─── Office game state ──────────────────────────────────────────────────────

class OfficeGameState {
  int _gridCols;
  int _gridRows;
  List<PlacedRoom> _placedRooms;
  List<FurniturePlacement> _placedFurniture;
  List<PlacedCorridor> _placedCorridors;
  double _chatScanAccum = 0;

  int get gridCols => _gridCols;
  int get gridRows => _gridRows;
  double get canvasWidth => gridCols * kTileSize;
  double get canvasHeight => gridRows * kTileSize;

  late List<List<TileType>> tileMap;
  late Set<String> blockedTiles;
  late List<TilePos> walkableTiles;
  final Map<String, GameCharacter> characters = {};
  late OfficeCat cat;
  final PlantEasterEgg plantEasterEgg = PlantEasterEgg();
  bool coffeeMachineBrewing = false;
  double _coffeeBrewTimer = 0;

  List<DeskStation> _extraStations = [];
  List<DeskStation> get allStations => [...kStations, ..._extraStations];

  // ── Passive room effects (recomputed on rebuildLayout) ──
  double _speedBonus = 1.0;         // server room: 1.1×
  double _seatRestMultiplier = 1.0; // break room: 1.5× seat rest timer
  TilePos? _loungeCenterTile;       // lounge: skate/wander target bias

  double get speedBonus => _speedBonus;
  double get seatRestMultiplier => _seatRestMultiplier;
  TilePos? get loungeCenterTile => _loungeCenterTile;

  OfficeGameState({
    OfficeLevel level = OfficeLevel.garage,
    int expansions = 0,
    List<PlacedRoom> placedRooms = const [],
    List<FurniturePlacement> placedFurniture = const [],
    List<PlacedCorridor> placedCorridors = const [],
  })  : _gridCols = level.effectiveCols(expansions),
        _gridRows = level.effectiveRows(expansions),
        _placedRooms = placedRooms,
        _placedFurniture = placedFurniture,
        _placedCorridors = placedCorridors {
    _buildAll();
    cat = OfficeCat();
  }

  void _buildAll() {
    _buildExtraStations();
    _buildTileMap();
    _buildBlockedTiles();
    _buildWalkableTiles();
    _buildRoomEffects();
  }

  void _buildRoomEffects() {
    // ── Global effects ──────────────────────────────────────────────────────
    final hasServer = _placedRooms.any((r) => r.type == RoomType.serverRoom);
    _speedBonus = hasServer ? 1.1 : 1.0;

    _seatRestMultiplier =
        _placedRooms.any((r) => r.type == RoomType.breakRoom) ? 1.5 : 1.0;

    final lounge =
        _placedRooms.where((r) => r.type == RoomType.lounge).firstOrNull;
    _loungeCenterTile = lounge != null
        ? TilePos(
            lounge.col + lounge.type.widthTiles ~/ 2,
            lounge.row + lounge.type.heightTiles ~/ 2,
          )
        : null;

    // ── Adjacency effects (office_design.md §4) ─────────────────────────────
    if (hasServer) {
      // Penalty: serverRoom far from every workstation → speed −5 pp.
      final servers = _placedRooms.where((r) => r.type == RoomType.serverRoom);
      final workstations =
          _placedRooms.where((r) => r.type == RoomType.workstation).toList();
      if (workstations.isEmpty) {
        _speedBonus -= 0.05;
      } else {
        for (final srv in servers) {
          final srvCx = srv.col + srv.footprintWidth / 2.0;
          final srvCy = srv.row + srv.footprintHeight / 2.0;
          final hasNearby = workstations.any((ws) {
            final rcx = ws.col + ws.footprintWidth / 2.0;
            final rcy = ws.row + ws.footprintHeight / 2.0;
            return (rcx - srvCx).abs() + (rcy - srvCy).abs() <= 8;
          });
          if (!hasNearby) _speedBonus -= 0.05;
        }
      }
      // Clamp to a sensible floor so stacking penalties can't go negative.
      if (_speedBonus < 0.9) _speedBonus = 0.9;
    }

    // workstation ↔ serverRoom adjacent → +5 % speed (global accumulation).
    for (int i = 0; i < _placedRooms.length; i++) {
      for (int j = i + 1; j < _placedRooms.length; j++) {
        final a = _placedRooms[i];
        final b = _placedRooms[j];
        if (!areRoomsAdjacent(a, b)) continue;

        if ((a.type == RoomType.workstation &&
                b.type == RoomType.serverRoom) ||
            (a.type == RoomType.serverRoom &&
                b.type == RoomType.workstation)) {
          _speedBonus += 0.05;
        }

        // breakRoom ↔ lounge synergy doubles the morale multiplier.
        if ((a.type == RoomType.breakRoom && b.type == RoomType.lounge) ||
            (a.type == RoomType.lounge && b.type == RoomType.breakRoom)) {
          _seatRestMultiplier = _seatRestMultiplier * 2.0;
        }
      }
    }

    // Wide corridors give a global +3 % speed bonus (one applies regardless of count).
    if (_placedCorridors.any((c) => c.wide)) {
      _speedBonus += 0.03;
    }

    // Hard ceiling: room bonuses can't stack past kSpeedBonusCeiling.
    // Floor already applied above (0.9); ceiling prevents runaway when many
    // workstation↔serverRoom pairs are placed.
    _speedBonus = _speedBonus.clamp(0.9, kSpeedBonusCeiling);
  }

  /// Rebuild layout after an office upgrade, expansion purchase, or Build
  /// Mode change. Characters are kept in place — those outside the new
  /// bounds will pathfind to valid tiles on their next update tick.
  void rebuildLayout(
    OfficeLevel newLevel,
    int newExpansions,
    List<PlacedRoom> newRooms, [
    List<FurniturePlacement> newFurniture = const [],
    List<PlacedCorridor> newCorridors = const [],
  ]) {
    _gridCols = newLevel.effectiveCols(newExpansions);
    _gridRows = newLevel.effectiveRows(newExpansions);
    _placedRooms = newRooms;
    _placedFurniture = newFurniture;
    _placedCorridors = newCorridors;
    _buildAll();
  }

  void _buildExtraStations() {
    _extraStations = [
      for (final room in _placedRooms)
        if (room.type == RoomType.workstation)
          DeskStation(
            agentId: 'ws_${room.id}',
            deskCol: room.col,
            deskRow: room.row,
            seatCol: room.col,
            seatRow: room.row + 1,
            facingDir: CharDirection.up,
            isExtra: true,
          ),
    ];
  }

  void _buildTileMap() {
    tileMap = List.generate(gridRows, (row) {
      return List.generate(gridCols, (col) {
        if (row == 0 ||
            row == gridRows - 1 ||
            col == 0 ||
            col == gridCols - 1) {
          return TileType.wall;
        }
        return TileType.floor;
      });
    });

    // Ensure corridor tiles are always walkable (floor type)
    for (final corridor in _placedCorridors) {
      for (final tile in corridor.tiles) {
        if (tile.row >= 0 && tile.row < gridRows && tile.col >= 0 && tile.col < gridCols) {
          tileMap[tile.row][tile.col] = TileType.floor;
        }
        // Wide corridors occupy two columns
        if (corridor.wide && tile.col + 1 >= 0 && tile.col + 1 < gridCols && tile.row >= 0 && tile.row < gridRows) {
          tileMap[tile.row][tile.col + 1] = TileType.floor;
        }
      }
    }
  }

  void _buildBlockedTiles() {
    blockedTiles = {};
    for (final station in kStations) {
      blockedTiles.add('${station.deskCol},${station.deskRow}');
      blockedTiles.add('${station.seatCol},${station.seatRow}');
    }
    for (final station in _extraStations) {
      blockedTiles.add('${station.deskCol},${station.deskRow}');
      blockedTiles.add('${station.seatCol},${station.seatRow}');
    }
    blockedTiles.add('$kCoffeeMachineCol,$kCoffeeMachineRow');
    blockedTiles.add('$kCoffeeMachineCol2,$kCoffeeMachineRow');
    blockedTiles.add('$kSnackTableCol,$kSnackTableRow');

    // Foreman stands on the bottom wall; his upper body overhangs the inner
    // tile directly above. Block that inner tile so rooms/furniture can't
    // cover his head. The wall tile itself isn't walkable anyway, so adding
    // it to blockedTiles is a no-op for pathing but keeps intent explicit.
    final fCol = foremanColFor(gridCols);
    final fRow = foremanRowFor(gridRows);
    blockedTiles.add('$fCol,$fRow');
    if (fRow > 0) blockedTiles.add('$fCol,${fRow - 1}');

    // Placed furniture items (if they block the path) occupy their footprint.
    for (final placement in _placedFurniture) {
      final item = furnitureById(placement.itemId);
      if (item == null || !item.blocksPath) continue;
      for (int dc = 0; dc < item.widthTiles; dc++) {
        for (int dr = 0; dr < item.heightTiles; dr++) {
          blockedTiles.add('${placement.col + dc},${placement.row + dr}');
        }
      }
    }

    // Internal solid features of placed rooms. Workstation rooms are handled
    // via _extraStations already — their desk/seat tiles are blocked there.
    for (final room in _placedRooms) {
      for (final t in _roomInternalBlocks(room)) {
        blockedTiles.add('${t.col},${t.row}');
      }
    }

    // Corridor tiles must never be blocked (room internals may have captured them)
    for (final corridor in _placedCorridors) {
      for (final tile in corridor.tiles) {
        blockedTiles.remove('${tile.col},${tile.row}');
        if (corridor.wide) {
          blockedTiles.remove('${tile.col + 1},${tile.row}');
        }
      }
    }
  }

  /// Tiles inside a placed room that are physically occupied by furniture
  /// the room draws (couches, tables, racks, ramps). Kept in sync with the
  /// visuals in [drawRoom] — if art changes, this should too.
  Iterable<TilePos> _roomInternalBlocks(PlacedRoom room) sync* {
    switch (room.type) {
      case RoomType.workstation:
        // Desk/seat already blocked via _extraStations.
        break;
      case RoomType.breakRoom:
        // 2×2: couch spans the bottom row.
        yield TilePos(room.col, room.row + 1);
        yield TilePos(room.col + 1, room.row + 1);
        break;
      case RoomType.meetingRoom:
        // 3×2: long table across the bottom row.
        for (int c = 0; c < 3; c++) {
          yield TilePos(room.col + c, room.row + 1);
        }
        break;
      case RoomType.serverRoom:
        // 2×2: two full-height racks.
        for (int c = 0; c < 2; c++) {
          yield TilePos(room.col + c, room.row);
          yield TilePos(room.col + c, room.row + 1);
        }
        break;
      case RoomType.lounge:
        // 3×2: beanbag on left-bottom, ramp on right column.
        yield TilePos(room.col, room.row + 1);
        yield TilePos(room.col + 2, room.row);
        yield TilePos(room.col + 2, room.row + 1);
        break;
      case RoomType.gym:
      case RoomType.cinema:
      case RoomType.pool:
      case RoomType.miniGolf:
        // Luxury rooms: treat the whole footprint as furniture — characters
        // can't walk through screens, water, greens or equipment.
        for (int r = 0; r < room.type.heightTiles; r++) {
          for (int c = 0; c < room.type.widthTiles; c++) {
            yield TilePos(room.col + c, room.row + r);
          }
        }
        break;
    }
  }

  void _buildWalkableTiles() {
    walkableTiles = [];
    for (int r = 0; r < gridRows; r++) {
      for (int c = 0; c < gridCols; c++) {
        if (_isWalkable(c, r, tileMap, blockedTiles)) {
          walkableTiles.add(TilePos(c, r));
        }
      }
    }
  }

  /// True when both the desk and seat tiles of [station] fit inside the inner
  /// (non-wall) area of the current grid. Used to gate canonical station
  /// usage on small offices — if the desk doesn't fit, the character spawns
  /// on a walkable tile instead.
  bool _stationFitsGrid(DeskStation station) {
    bool fits(int c, int r) =>
        c >= 1 && r >= 1 && c < gridCols - 1 && r < gridRows - 1;
    return fits(station.deskCol, station.deskRow) &&
        fits(station.seatCol, station.seatRow);
  }

  /// Sync the hired roster from the game economy into the render characters.
  ///
  /// [hiredIds] carries every hired instanceId (e.g. "coder#1", "coder#2"). This
  /// function creates a [GameCharacter] per instance and disposes of any whose
  /// instance no longer exists, so multiple instances of the same role render
  /// as distinct sprites. The first instance of each role claims that role's
  /// canonical desk station; extras get `seat: null` and wander freely until
  /// additional seats are added (see office-expansion work).
  /// Sync hired agents into the canvas character map.
  ///
  /// Returns the list of instanceIds that transitioned from [CharState.waiting]
  /// to a real seat this call — i.e. agents that just received a workstation.
  /// Callers should persist this by calling `assignWorkplace` on the provider.
  List<String> syncHiredAgents(
    List<String> hiredIds, [
    Map<String, HardwareTier>? hardwareMap,
    Map<String, WorkplaceStatus>? workplaceStatusMap,
  ]) {
    final hiredSet = hiredIds.toSet();

    // 1. Drop characters whose instance is no longer hired.
    characters.removeWhere((id, _) => !hiredSet.contains(id));

    // 2. Assign seat ownership — first appearance of each role in hiredIds
    //    takes the role's canonical station. Others go seatless.
    final seatOwner = <String, String>{}; // roleType → instanceId that sits there
    for (final id in hiredIds) {
      final roleType = roleTypeFromInstanceId(id);
      seatOwner.putIfAbsent(roleType, () => id);
    }

    // 3. Create characters for any newly hired instance.
    for (final id in hiredIds) {
      if (characters.containsKey(id)) continue;
      final roleType = roleTypeFromInstanceId(id);
      final isSeatOwner = seatOwner[roleType] == id;
      final isUnassigned =
          (workplaceStatusMap?[id] ?? WorkplaceStatus.assigned) ==
          WorkplaceStatus.unassigned;

      // Unassigned agents skip canonical desks — they wait in the lobby zone
      // until the player builds and assigns a Workstation Room.
      final canonical = (!isUnassigned && isSeatOwner)
          ? kStations
              .where((s) => s.agentId == roleType)
              .cast<DeskStation?>()
              .firstWhere((_) => true, orElse: () => null)
          : null;
      final station = (canonical != null && _stationFitsGrid(canonical))
          ? canonical
          : null;

      // Unassigned agents spawn in the lobby zone (bottom-left corner).
      // Assigned seatless hires get a random walkable tile.
      int spawnCol, spawnRow;
      if (station != null) {
        spawnCol = station.seatCol;
        spawnRow = station.seatRow;
      } else if (isUnassigned) {
        spawnCol = 2;
        spawnRow = (gridRows - 2).clamp(1, gridRows - 1);
      } else if (walkableTiles.isNotEmpty) {
        final t = walkableTiles[_rng.nextInt(walkableTiles.length)];
        spawnCol = t.col;
        spawnRow = t.row;
      } else {
        spawnCol = 2;
        spawnRow = 2;
      }

      characters[id] = GameCharacter(
        instanceId: id,
        roleType: roleType,
        seat: station,
        tileCol: spawnCol,
        tileRow: spawnRow,
        state: isUnassigned
            ? CharState.waiting
            : (station != null ? CharState.typing : CharState.idle),
        seatTimer: _randomRange(8.0, 25.0),
      );
    }

    // 4. Keep seat assignment in sync with the current owner list — e.g. if
    //    the original primary was fired, the next instance should inherit
    //    the desk. isHired stays true for everyone in hiredIds.
    for (final ch in characters.values) {
      ch.isHired = true;
      final shouldOwnSeat = seatOwner[ch.roleType] == ch.instanceId;
      if (shouldOwnSeat && (ch.seat == null || ch.seat!.isExtra)) {
        final canonical = kStations
            .where((s) => s.agentId == ch.roleType)
            .cast<DeskStation?>()
            .firstWhere((_) => true, orElse: () => null);
        // Only claim the canonical desk if it exists and fits — otherwise
        // leave seat null and fall through to the extras loop below.
        if (canonical != null && _stationFitsGrid(canonical)) {
          ch.seat = canonical;
        }
      } else if (!shouldOwnSeat && ch.seat != null && !ch.seat!.isExtra) {
        ch.seat = null;
      }
    }

    // 4b. Assign seatless characters to free extra workstation stations.
    // Track waiting agents before assignment so we can report who just got a desk.
    final waitingBeforeAssign = {
      for (final ch in characters.values)
        if (ch.state == CharState.waiting && ch.seat == null) ch.instanceId,
    };

    final occupiedExtra = <DeskStation>{
      for (final ch in characters.values)
        if (ch.seat != null && ch.seat!.isExtra) ch.seat!,
    };
    for (final ch in characters.values) {
      if (ch.seat != null) continue;
      for (final s in _extraStations) {
        if (!occupiedExtra.contains(s)) {
          ch.seat = s;
          occupiedExtra.add(s);
          break;
        }
      }
    }

    // Collect agents that just received a seat (were waiting, now seated).
    final newlyAssigned = <String>[
      for (final id in waitingBeforeAssign)
        if (characters[id]?.seat != null) id,
    ];

    // 5. Apply per-instance hardware tier.
    if (hardwareMap != null) {
      for (final entry in hardwareMap.entries) {
        final ch = characters[entry.key];
        if (ch != null) ch.hardware = entry.value;
      }
    }

    return newlyAssigned;
  }

  /// Serialize current character positions for cross-device sync.
  Map<String, Map<String, dynamic>> serializePositions() {
    return {
      for (final ch in characters.values)
        if (ch.isHired)
          ch.instanceId: {
            'col': ch.tileCol,
            'row': ch.tileRow,
            'state': ch.state.name,
            'dir': ch.dir.name,
            'onSkateboard': ch.isOnSkateboard,
          },
    };
  }

  /// Apply remote character positions received from another device.
  /// Only moves idle/wandering characters — active (typing) characters
  /// are driven by agent_status and left untouched.
  void applyRemotePositions(
    Map<String, ({int col, int row, String state, String dir, bool onSkateboard})>
        remote,
  ) {
    for (final entry in remote.entries) {
      final ch = characters[entry.key];
      if (ch == null || !ch.isHired || ch.isActive || ch.isChatting) continue;
      final r = entry.value;

      // Mirror skateboard flag so followers render the skateboard sprite and
      // move at skate speed. The mount/dismount animations are intentionally
      // skipped on followers — those are cosmetic, and replaying them would
      // desync against the source's live tile snapshots.
      if (ch.isOnSkateboard != r.onSkateboard) {
        ch.isOnSkateboard = r.onSkateboard;
      }

      if (ch.tileCol == r.col && ch.tileRow == r.row) continue;
      // Pathfind to the remote tile so the character walks there naturally
      final path = _findPathForCharacter(ch, r.col, r.row);
      if (path.isNotEmpty) {
        ch.path = path;
        ch.moveProgress = 0;
        ch.state = CharState.walk;
        ch.frame = 0;
        ch.frameTimer = 0;
      }
    }
  }

  /// Sync agent states from the provider into game characters.
  ///
  /// [agentStates] is keyed by instanceId — one-to-one with our character map.
  void syncAgents(Map<String, AgentState> agentStates) {
    for (final ch in characters.values) {
      final agentState = agentStates[ch.instanceId];
      if (agentState == null) continue;

      final isNowActive = agentState.status != AgentStatus.idle;
      final wasActive = ch.isActive;

      ch.isReading = agentState.status == AgentStatus.reading;
      ch.displayStatus = agentState.status;

      if (isNowActive && !wasActive) {
        ch.isActive = true;
        _activateCharacter(ch);
      } else if (!isNowActive && wasActive) {
        ch.isActive = false;
        ch.seatTimer = -1; // sentinel: skip long rest on arrival
        ch.path = [];
        ch.moveProgress = 0;
      }
    }
  }

  void _activateCharacter(GameCharacter ch) {
    ch.isOnSkateboard = false;
    // Any activation cancels an in-progress chat — the character has work
    // to do. The partner is cleaned up on its next update tick.
    if (ch.isChatting) {
      ch.isChatting = false;
      ch.chatTimer = 0;
      ch.chatPartnerId = null;
    }
    if (ch.seat == null) {
      // Seatless extras (e.g. second instance of a role) don't have a desk
      // to type at. Keep them walking around the office instead of snapping
      // into a mid-floor typing pose, which looks off.
      if (ch.state == CharState.walk) return;
      ch.state = CharState.idle;
      ch.frame = 0;
      ch.frameTimer = 0;
      ch.wanderTimer = _randomRange(0.3, 1.5);
      return;
    }

    if (ch.tileCol == ch.seat!.seatCol && ch.tileRow == ch.seat!.seatRow) {
      ch.state = CharState.typing;
      ch.dir = ch.seat!.facingDir;
      ch.frame = 0;
      ch.frameTimer = 0;
      return;
    }

    final path =
        _findPathForCharacter(ch, ch.seat!.seatCol, ch.seat!.seatRow);
    if (path.isNotEmpty) {
      ch.path = path;
      ch.moveProgress = 0;
      ch.state = CharState.walk;
      ch.frame = 0;
      ch.frameTimer = 0;
    } else {
      ch.state = CharState.typing;
      ch.dir = ch.seat!.facingDir;
      ch.frame = 0;
      ch.frameTimer = 0;
    }
  }

  List<TilePos> _findPathForCharacter(
    GameCharacter ch, int endCol, int endRow,
  ) {
    final ownSeatKey = ch.seat != null
        ? '${ch.seat!.seatCol},${ch.seat!.seatRow}'
        : null;
    if (ownSeatKey != null) blockedTiles.remove(ownSeatKey);
    final path =
        _findPath(ch.tileCol, ch.tileRow, endCol, endRow, tileMap, blockedTiles);
    if (ownSeatKey != null) blockedTiles.add(ownSeatKey);
    return path;
  }

  /// Build a long skate path that chains several far-apart waypoints so the
  /// character laps around the office instead of rolling a handful of tiles.
  /// Each waypoint is chosen by sampling random walkable tiles and keeping
  /// the farthest from the current leg origin.
  List<TilePos> _buildSkateLoopPath(GameCharacter ch) {
    if (walkableTiles.isEmpty) return const [];

    final ownSeatKey = ch.seat != null
        ? '${ch.seat!.seatCol},${ch.seat!.seatRow}'
        : null;
    if (ownSeatKey != null) blockedTiles.remove(ownSeatKey);

    final path = <TilePos>[];
    int curCol = ch.tileCol;
    int curRow = ch.tileRow;

    for (int i = 0; i < kSkateWaypointCount; i++) {
      TilePos? best;
      int bestDist = -1;
      for (int k = 0; k < kSkateWaypointSamples; k++) {
        final c = walkableTiles[_rng.nextInt(walkableTiles.length)];
        if (c.col == curCol && c.row == curRow) continue;
        final d = (c.col - curCol).abs() + (c.row - curRow).abs();
        if (d > bestDist) {
          bestDist = d;
          best = c;
        }
      }
      if (best == null) break;
      final segment =
          _findPath(curCol, curRow, best.col, best.row, tileMap, blockedTiles);
      if (segment.isEmpty) continue;
      path.addAll(segment);
      curCol = best.col;
      curRow = best.row;
    }

    if (ownSeatKey != null) blockedTiles.add(ownSeatKey);
    return path;
  }

  void _snapToTile(GameCharacter ch) {
    ch.x = ch.tileCol * kTileSize + kTileSize / 2;
    ch.y = ch.tileRow * kTileSize + kTileSize / 2;
  }

  /// Main game loop update. Call every frame with delta time (seconds).
  void update(double dt) {
    for (final ch in characters.values) {
      if (!ch.isHired) continue;
      _updateCharacter(ch, dt);
    }
    _chatScanAccum += dt;
    if (_chatScanAccum >= kChatScanInterval) {
      _chatScanAccum -= kChatScanInterval;
      _maybeStartChats(kChatScanInterval);
    }
    _updateCat(dt);
    _updatePlants(dt);
    _updateCoffeeMachine(dt);
  }

  /// Walk the roster and let nearby wandering characters strike up a chat
  /// occasionally. Both sides enter chat state together so the partner
  /// actually stops and turns to face back.
  void _maybeStartChats(double interval) {
    final startChance = kChatStartChancePerSec * interval;
    final chars = characters.values.where(_canChat).toList();
    for (int i = 0; i < chars.length; i++) {
      final a = chars[i];
      if (!_canChat(a)) continue; // may have been paired this iteration
      if (_rng.nextDouble() >= startChance) continue;
      for (int j = 0; j < chars.length; j++) {
        if (i == j) continue;
        final b = chars[j];
        if (!_canChat(b)) continue;
        final dx = (a.tileCol - b.tileCol).abs();
        final dy = (a.tileRow - b.tileRow).abs();
        // Adjacent (incl. diagonal) — close enough to notice each other.
        if (dx <= 1 && dy <= 1 && (dx + dy) > 0) {
          _startChat(a, b);
          break;
        }
      }
    }
  }

  bool _canChat(GameCharacter ch) {
    if (!ch.isHired) return false;
    if (ch.isActive) return false;
    if (ch.isChatting) return false;
    if (ch.isOnSkateboard) return false;
    if (ch.chatCooldown > 0) return false;
    // Must be on foot in the office floor, not sitting at a desk or waiting.
    if (ch.state == CharState.typing) return false;
    if (ch.state == CharState.waiting) return false;
    if (ch.state == CharState.skateMount ||
        ch.state == CharState.skateDismount) {
      return false;
    }
    return true;
  }

  void _startChat(GameCharacter a, GameCharacter b) {
    final duration = _randomRange(kChatMinDuration, kChatMaxDuration);
    for (final ch in [a, b]) {
      ch.isChatting = true;
      ch.chatTimer = duration;
      ch.state = CharState.idle;
      ch.path = [];
      ch.moveProgress = 0;
      ch.frame = 0;
      ch.frameTimer = 0;
    }
    a.chatPartnerId = b.instanceId;
    b.chatPartnerId = a.instanceId;
    // Face each other.
    a.dir = _directionBetween(a.tileCol, a.tileRow, b.tileCol, b.tileRow);
    b.dir = _directionBetween(b.tileCol, b.tileRow, a.tileCol, a.tileRow);
  }

  void _endChat(GameCharacter ch) {
    ch.isChatting = false;
    ch.chatTimer = 0;
    ch.chatPartnerId = null;
    ch.chatCooldown = _randomRange(kChatCooldownMin, kChatCooldownMax);
    // Give them a beat before resuming random motion.
    ch.wanderTimer = _randomRange(0.5, 2.0);
  }

  void _updateCharacter(GameCharacter ch, double dt) {
    ch.frameTimer += dt;

    // Count down coffee timer while typing
    if (ch.hasCoffee && ch.state == CharState.typing) {
      ch.coffeeTimer -= dt;
      if (ch.coffeeTimer <= 0) {
        ch.hasCoffee = false;
        ch.coffeeTimer = 0;
      }
    }

    // Cool-down between chats so the same pair doesn't immediately re-engage.
    if (!ch.isChatting && ch.chatCooldown > 0) {
      ch.chatCooldown -= dt;
      if (ch.chatCooldown < 0) ch.chatCooldown = 0;
    }

    // Chatting overrides regular FSM — stand still, animate bubble, wait it out.
    if (ch.isChatting) {
      ch.chatTimer -= dt;
      final partner = ch.chatPartnerId != null
          ? characters[ch.chatPartnerId]
          : null;
      // If partner vanished (fired) or got activated, end early.
      if (partner == null || !partner.isHired || partner.isActive) {
        _endChat(ch);
      } else if (ch.chatTimer <= 0) {
        _endChat(ch);
      } else {
        // Idle sway: toggle frame slowly so the sprite breathes a little.
        if (ch.frameTimer >= kTypeFrameDuration * 2) {
          ch.frameTimer -= kTypeFrameDuration * 2;
          ch.frame = (ch.frame + 1) % 2;
        }
        return;
      }
    }

    switch (ch.state) {
      case CharState.typing:
        if (ch.frameTimer >= kTypeFrameDuration) {
          ch.frameTimer -= kTypeFrameDuration;
          ch.frame = (ch.frame + 1) % 2;
        }
        if (!ch.isActive) {
          if (ch.seatTimer > 0) {
            ch.seatTimer -= dt;
            break;
          }
          ch.seatTimer = 0;
          ch.state = CharState.idle;
          ch.frame = 0;
          ch.frameTimer = 0;
          ch.wanderTimer = _randomRange(kWanderPauseMin, kWanderPauseMax);
          ch.wanderCount = 0;
          ch.wanderLimit = _randomInt(kWanderMovesMin, kWanderMovesMax);
        }
        break;

      case CharState.idle:
        ch.frame = 0;
        if (ch.seatTimer < 0) ch.seatTimer = 0;

        if (ch.isActive) {
          _activateCharacter(ch);
          break;
        }

        ch.wanderTimer -= dt;
        if (ch.wanderTimer <= 0) {
          // Return to seat when done wandering
          if (ch.wanderCount >= ch.wanderLimit && ch.seat != null) {
            final path = _findPathForCharacter(
              ch, ch.seat!.seatCol, ch.seat!.seatRow,
            );
            if (path.isNotEmpty) {
              ch.path = path;
              ch.moveProgress = 0;
              ch.state = CharState.walk;
              ch.frame = 0;
              ch.frameTimer = 0;
              break;
            }
          }

          // Chance to go get coffee instead of random wander
          if (!ch.hasCoffee && _rng.nextDouble() < kCoffeeWalkChance) {
            final coffeePath = _findPathToCoffeeArea(ch);
            if (coffeePath.isNotEmpty) {
              ch.path = coffeePath;
              ch.moveProgress = 0;
              ch.state = CharState.walk;
              ch.frame = 0;
              ch.frameTimer = 0;
              ch.wanderCount++;
              break;
            }
          }

          if (walkableTiles.isNotEmpty) {
            final wantSkate = ch.hasCoffee
                ? _rng.nextDouble() < kCoffeeSkateChance
                : _rng.nextDouble() < kSkateboardChance;

            List<TilePos> path = const [];
            bool skate = false;
            if (wantSkate) {
              path = _buildSkateLoopPath(ch);
              skate = path.isNotEmpty;
            }
            if (path.isEmpty) {
              // Lounge bias: 40% chance to wander toward lounge when it exists.
              final lc = _loungeCenterTile;
              if (lc != null && _rng.nextDouble() < 0.4) {
                path = _findPathForCharacter(ch, lc.col, lc.row);
              }
              if (path.isEmpty) {
                final target =
                    walkableTiles[_rng.nextInt(walkableTiles.length)];
                path = _findPathForCharacter(ch, target.col, target.row);
              }
            }

            if (path.isNotEmpty) {
              ch.path = path;
              ch.moveProgress = 0;
              ch.wanderCount++;
              if (skate) {
                ch.isOnSkateboard = true;
                ch.state = CharState.skateMount;
              } else {
                ch.state = CharState.walk;
              }
              ch.frame = 0;
              ch.frameTimer = 0;
            }
          }
          ch.wanderTimer = _randomRange(kWanderPauseMin, kWanderPauseMax);
        }
        break;

      case CharState.skateMount:
        // Wait for mount animation, then start riding
        if (ch.frameTimer >= kSkateMountDuration) {
          ch.state = CharState.walk;
          ch.frame = 0;
          ch.frameTimer = 0;
        }
        // Cancel mount if activated
        if (ch.isActive) {
          ch.isOnSkateboard = false;
          _activateCharacter(ch);
        }
        break;

      case CharState.skateDismount:
        // Wait for dismount animation, then go idle
        if (ch.frameTimer >= kSkateDismountDuration) {
          ch.isOnSkateboard = false;
          _afterDismount(ch);
        }
        // Cancel dismount if activated
        if (ch.isActive) {
          ch.isOnSkateboard = false;
          _activateCharacter(ch);
        }
        break;

      case CharState.walk:
        final frameDuration =
            ch.isOnSkateboard ? kSkateRideFrameDuration : kWalkFrameDuration;
        final frameCount = ch.isOnSkateboard ? 2 : 4;
        if (ch.frameTimer >= frameDuration) {
          ch.frameTimer -= frameDuration;
          ch.frame = (ch.frame + 1) % frameCount;
        }

        if (ch.path.isEmpty) {
          _snapToTile(ch);
          _onPathComplete(ch);
          break;
        }

        final nextTile = ch.path.first;
        ch.dir = _directionBetween(
          ch.tileCol, ch.tileRow, nextTile.col, nextTile.row,
        );
        final walkSpeed = (ch.isOnSkateboard ? kSkateboardSpeed : kWalkSpeedPxPerSec) * _speedBonus;
        ch.moveProgress += (walkSpeed / kTileSize) * dt;

        final fromX = ch.tileCol * kTileSize + kTileSize / 2;
        final fromY = ch.tileRow * kTileSize + kTileSize / 2;
        final toX = nextTile.col * kTileSize + kTileSize / 2;
        final toY = nextTile.row * kTileSize + kTileSize / 2;
        final t = ch.moveProgress.clamp(0.0, 1.0);
        ch.x = fromX + (toX - fromX) * t;
        ch.y = fromY + (toY - fromY) * t;

        if (ch.moveProgress >= 1.0) {
          ch.tileCol = nextTile.col;
          ch.tileRow = nextTile.row;
          ch.x = toX;
          ch.y = toY;
          ch.path.removeAt(0);
          ch.moveProgress = 0;
        }

        // Repath to seat if became active while wandering
        if (ch.isActive && ch.seat != null) {
          ch.isOnSkateboard = false;
          final lastStep = ch.path.isNotEmpty ? ch.path.last : null;
          if (lastStep == null ||
              lastStep.col != ch.seat!.seatCol ||
              lastStep.row != ch.seat!.seatRow) {
            final newPath = _findPathForCharacter(
              ch, ch.seat!.seatCol, ch.seat!.seatRow,
            );
            if (newPath.isNotEmpty) {
              ch.path = newPath;
              ch.moveProgress = 0;
            }
          }
        }
        break;

      case CharState.waiting:
        // Agent is hired but has no workstation yet. Stands in the lobby zone
        // with a slow 2-frame breath: alternate frame 0/1 every ~0.8 s.
        if (ch.frameTimer >= 0.8) {
          ch.frameTimer = 0;
          ch.frame = 1 - ch.frame; // toggle 0 ↔ 1
        }
        // Once a seat is assigned externally, transition to normal idle/typing.
        if (ch.seat != null) {
          ch.state = CharState.idle;
          ch.frame = 0;
          ch.frameTimer = 0;
          ch.wanderTimer = _randomRange(kWanderPauseMin, kWanderPauseMax);
        }
        break;
    }
  }

  /// Find a path to a tile adjacent to the coffee machine.
  List<TilePos> _findPathToCoffeeArea(GameCharacter ch) {
    // Try tiles adjacent to the coffee machine
    for (final d in const [(0, 1), (1, 0), (-1, 0), (0, -1)]) {
      final tc = kCoffeeMachineCol + d.$1;
      final tr = kCoffeeMachineRow + d.$2;
      if (_isWalkable(tc, tr, tileMap, blockedTiles)) {
        final path = _findPathForCharacter(ch, tc, tr);
        if (path.isNotEmpty) return path;
      }
    }
    return [];
  }

  void _onPathComplete(GameCharacter ch) {
    // Check if arrived near coffee machine → get coffee
    if (!ch.hasCoffee) {
      final dc = (ch.tileCol - kCoffeeMachineCol).abs();
      final dr = (ch.tileRow - kCoffeeMachineRow).abs();
      if (dc + dr == 1) {
        ch.hasCoffee = true;
        ch.coffeeTimer = kCoffeeDrinkDuration;
        coffeeMachineBrewing = true;
        _coffeeBrewTimer = kCoffeeBrewDuration;
      }
    }

    // If on skateboard, dismount first
    if (ch.isOnSkateboard) {
      ch.state = CharState.skateDismount;
      ch.frame = 0;
      ch.frameTimer = 0;
      return;
    }

    _afterDismount(ch);
  }

  /// Called after skateboard dismount (or directly if not on skateboard).
  void _afterDismount(GameCharacter ch) {
    ch.isOnSkateboard = false;
    if (ch.isActive) {
      if (ch.seat != null &&
          ch.tileCol == ch.seat!.seatCol &&
          ch.tileRow == ch.seat!.seatRow) {
        ch.state = CharState.typing;
        ch.dir = ch.seat!.facingDir;
      } else {
        ch.state = CharState.idle;
      }
    } else {
      if (ch.seat != null &&
          ch.tileCol == ch.seat!.seatCol &&
          ch.tileRow == ch.seat!.seatRow) {
        ch.state = CharState.typing;
        ch.dir = ch.seat!.facingDir;
        if (ch.seatTimer < 0) {
          ch.seatTimer = 0;
        } else {
          ch.seatTimer = _randomRange(kSeatRestMin, kSeatRestMax) * _seatRestMultiplier;
        }
        ch.wanderCount = 0;
        ch.wanderLimit = _randomInt(kWanderMovesMin, kWanderMovesMax);
      } else {
        ch.state = CharState.idle;
        ch.wanderTimer = _randomRange(kWanderPauseMin, kWanderPauseMax);
      }
    }
    ch.frame = 0;
    ch.frameTimer = 0;
  }

  // ─── Cat AI ──────────────────────────────────────────────────────────────

  void _updateCat(double dt) {
    final c = cat;
    c.frameTimer += dt;

    switch (c.state) {
      case CatAction.idle:
        c.stateTimer -= dt;
        if (c.stateTimer <= 0) {
          // Decide: sleep on a desk or wander?
          if (c.wanderCount > 2 || _rng.nextDouble() < kCatSleepOnDeskChance) {
            _catGoToDesk();
          } else {
            _catWander();
          }
        }

      case CatAction.walk:
        if (c.frameTimer >= kCatWalkFrameDuration) {
          c.frameTimer -= kCatWalkFrameDuration;
          c.frame = (c.frame + 1) % 4;
        }
        if (c.path.isEmpty) {
          _catSnapToTile();
          _catOnPathComplete();
          break;
        }
        final nextTile = c.path.first;
        c.dir = _directionBetween(c.tileCol, c.tileRow, nextTile.col, nextTile.row);
        c.moveProgress += (kCatWalkSpeed / kTileSize) * dt;
        final fromX = c.tileCol * kTileSize + kTileSize / 2;
        final fromY = c.tileRow * kTileSize + kTileSize / 2;
        final toX = nextTile.col * kTileSize + kTileSize / 2;
        final toY = nextTile.row * kTileSize + kTileSize / 2;
        final t = c.moveProgress.clamp(0.0, 1.0);
        c.x = fromX + (toX - fromX) * t;
        c.y = fromY + (toY - fromY) * t;
        if (c.moveProgress >= 1.0) {
          c.tileCol = nextTile.col;
          c.tileRow = nextTile.row;
          c.x = toX;
          c.y = toY;
          c.path.removeAt(0);
          c.moveProgress = 0;
        }

      case CatAction.sleep:
        c.stateTimer -= dt;
        if (c.stateTimer <= 0) {
          c.sleepDeskAgent = null;
          c.state = CatAction.idle;
          c.stateTimer = _randomRange(kCatIdlePauseMin, kCatIdlePauseMax);
          c.wanderCount = 0;
          // Snap back to the walkable tile (above the desk)
          _catSnapToTile();
        }
    }
  }

  void _catSnapToTile() {
    cat.x = cat.tileCol * kTileSize + kTileSize / 2;
    cat.y = cat.tileRow * kTileSize + kTileSize / 2;
  }

  void _catWander() {
    if (walkableTiles.isEmpty) return;
    final target = walkableTiles[_rng.nextInt(walkableTiles.length)];
    final path = _findPath(cat.tileCol, cat.tileRow, target.col, target.row, tileMap, blockedTiles);
    if (path.isNotEmpty) {
      cat.path = path;
      cat.moveProgress = 0;
      cat.state = CatAction.walk;
      cat.frame = 0;
      cat.frameTimer = 0;
      cat.sleepDeskAgent = null;
      cat.wanderCount++;
    } else {
      cat.stateTimer = _randomRange(kCatIdlePauseMin, kCatIdlePauseMax);
    }
  }

  void _catGoToDesk() {
    // Pick a random desk whose role has at least one hired instance
    final hiredRoles = <String>{
      for (final c in characters.values) if (c.isHired) c.roleType,
    };
    final hiredStations =
        kStations.where((s) => hiredRoles.contains(s.agentId)).toList();
    if (hiredStations.isEmpty) {
      _catWander();
      return;
    }
    final station = hiredStations[_rng.nextInt(hiredStations.length)];
    // Walk to tile above the desk (deskRow - 1)
    final targetRow = station.deskRow - 1;
    final targetCol = station.deskCol;
    final path = _findPath(cat.tileCol, cat.tileRow, targetCol, targetRow, tileMap, blockedTiles);
    if (path.isNotEmpty) {
      cat.path = path;
      cat.moveProgress = 0;
      cat.state = CatAction.walk;
      cat.frame = 0;
      cat.frameTimer = 0;
      cat.sleepDeskAgent = station.agentId;
    } else {
      _catWander();
    }
  }

  void _catOnPathComplete() {
    if (cat.sleepDeskAgent != null) {
      // Jump onto desk to sleep
      final station = kStations.firstWhere((s) => s.agentId == cat.sleepDeskAgent);
      cat.state = CatAction.sleep;
      // Visual position on the desk surface
      cat.x = station.deskCol * kTileSize + kTileSize / 2;
      cat.y = station.deskRow * kTileSize + kTileSize / 2;
      cat.dir = CharDirection.down;
      cat.frame = 0;
      cat.frameTimer = 0;
      cat.stateTimer = _randomRange(kCatSleepMin, kCatSleepMax);
    } else {
      cat.state = CatAction.idle;
      cat.stateTimer = _randomRange(kCatIdlePauseMin, kCatIdlePauseMax);
    }
  }

  // ─── Plant easter egg ────────────────────────────────────────────────────

  void _updatePlants(double dt) {
    final expired = <String>[];
    for (final entry in plantEasterEgg.activeTimers.entries) {
      plantEasterEgg.activeTimers[entry.key] = entry.value - dt;
      if (entry.value - dt <= 0) expired.add(entry.key);
    }
    for (final k in expired) {
      plantEasterEgg.activeTimers.remove(k);
    }
  }

  /// Trigger the bounce animation for a plant at tile (col, row).
  void activatePlant(int col, int row) {
    plantEasterEgg.activeTimers['$col,$row'] = kPlantAnimDuration;
  }

  List<FurniturePlacement> get placedFurniture =>
      List.unmodifiable(_placedFurniture);

  // ─── Coffee machine ─────────────────────────────────────────────────────

  void _updateCoffeeMachine(double dt) {
    if (coffeeMachineBrewing) {
      _coffeeBrewTimer -= dt;
      if (_coffeeBrewTimer <= 0) {
        coffeeMachineBrewing = false;
      }
      return;
    }
    // Trigger brewing when a character walks adjacent to the machine
    for (final ch in characters.values) {
      if (!ch.isHired || ch.state != CharState.walk) continue;
      final dc = (ch.tileCol - kCoffeeMachineCol).abs();
      final dr = (ch.tileRow - kCoffeeMachineRow).abs();
      if (dc + dr == 1) {
        coffeeMachineBrewing = true;
        _coffeeBrewTimer = kCoffeeBrewDuration;
        break;
      }
    }
  }
}
