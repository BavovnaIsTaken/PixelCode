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

// ─── Constants ──────────────────────────────────────────────────────────────

const int kGridCols = 20;
const int kGridRows = 14;
const double kTileSize = 16.0;

/// Virtual canvas dimensions.
const double kCanvasWidth = kGridCols * kTileSize; // 320
const double kCanvasHeight = kGridRows * kTileSize; // 224

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
const double kCoffeeBrewDuration = 6.0;

// Skateboard
const double kSkateboardSpeed = 96.0;
const double kSkateboardChance = 0.2;
const double kSkateMountDuration = 0.8;
const double kSkateDismountDuration = 0.6;
const double kSkateRideFrameDuration = 0.25;

// Coffee
const double kCoffeeWalkChance = 0.15;
const double kCoffeeDrinkDuration = 20.0;
const double kCoffeeSkateChance = 0.05;

// Plant easter egg
const double kPlantAnimDuration = 3.0;
const double kPlantBounceSpeed = 8.0;

// Plant positions (corners)
const kPlantPositions = <(int, int)>[
  (2, 1), (17, 1),
  (2, 11), (17, 11),
];

// ─── Enums ──────────────────────────────────────────────────────────────────

enum TileType { wall, floor }

enum CharDirection { down, left, right, up }

enum CharState { idle, walk, typing, skateMount, skateDismount }

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

  const DeskStation({
    required this.agentId,
    required this.deskCol,
    required this.deskRow,
    required this.seatCol,
    required this.seatRow,
    required this.facingDir,
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

/// Agent → sprite palette index (0-5). 7th agent reuses palette 0.
const agentPaletteIndex = <String, int>{
  'manager': 0,
  'tech-lead': 1,
  'coder': 2,
  'reviewer': 3,
  'tester': 4,
  'security': 5,
  'ui-ux-designer': 0,
};

class GameCharacter {
  final String agentId;
  final int paletteIndex;
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

  GameCharacter({
    required this.agentId,
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
  })  : paletteIndex = agentPaletteIndex[agentId] ?? 0,
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
        displayStatus = AgentStatus.idle;
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
  final Map<int, double> activeTimers = {};
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
  late final List<List<TileType>> tileMap;
  late final Set<String> blockedTiles;
  late final List<TilePos> walkableTiles;
  final Map<String, GameCharacter> characters = {};
  late final OfficeCat cat;
  final PlantEasterEgg plantEasterEgg = PlantEasterEgg();
  bool coffeeMachineBrewing = false;
  double _coffeeBrewTimer = 0;

  OfficeGameState() {
    _buildTileMap();
    _buildBlockedTiles();
    _buildWalkableTiles();
    _initCharacters();
    cat = OfficeCat();
  }

  void _buildTileMap() {
    tileMap = List.generate(kGridRows, (row) {
      return List.generate(kGridCols, (col) {
        if (row == 0 ||
            row == kGridRows - 1 ||
            col == 0 ||
            col == kGridCols - 1) {
          return TileType.wall;
        }
        return TileType.floor;
      });
    });
  }

  void _buildBlockedTiles() {
    blockedTiles = {};
    for (final station in kStations) {
      blockedTiles.add('${station.deskCol},${station.deskRow}');
      blockedTiles.add('${station.seatCol},${station.seatRow}');
    }
    blockedTiles.add('$kCoffeeMachineCol,$kCoffeeMachineRow');
    blockedTiles.add('$kCoffeeMachineCol2,$kCoffeeMachineRow');
    blockedTiles.add('$kSnackTableCol,$kSnackTableRow');
  }

  void _buildWalkableTiles() {
    walkableTiles = [];
    for (int r = 0; r < kGridRows; r++) {
      for (int c = 0; c < kGridCols; c++) {
        if (_isWalkable(c, r, tileMap, blockedTiles)) {
          walkableTiles.add(TilePos(c, r));
        }
      }
    }
  }

  void _initCharacters() {
    for (final station in kStations) {
      characters[station.agentId] = GameCharacter(
        agentId: station.agentId,
        seat: station,
        seatTimer: _randomRange(8.0, 25.0),
      );
    }
  }

  /// Sync hired status and hardware tiers from game economy into characters.
  void syncHiredAgents(List<String> hiredIds, [Map<String, HardwareTier>? hardwareMap]) {
    final hiredSet = hiredIds.toSet();
    for (final ch in characters.values) {
      ch.isHired = hiredSet.contains(ch.agentId);
      if (hardwareMap != null && hardwareMap.containsKey(ch.agentId)) {
        ch.hardware = hardwareMap[ch.agentId]!;
      }
    }
  }

  /// Serialize current character positions for cross-device sync.
  Map<String, Map<String, dynamic>> serializePositions() {
    return {
      for (final ch in characters.values)
        if (ch.isHired)
          ch.agentId: {
            'col': ch.tileCol,
            'row': ch.tileRow,
            'state': ch.state.name,
            'dir': ch.dir.name,
          },
    };
  }

  /// Apply remote character positions received from another device.
  /// Only moves idle/wandering characters — active (typing) characters
  /// are driven by agent_status and left untouched.
  void applyRemotePositions(
    Map<String, ({int col, int row, String state, String dir})> remote,
  ) {
    for (final entry in remote.entries) {
      final ch = characters[entry.key];
      if (ch == null || !ch.isHired || ch.isActive) continue;
      final r = entry.value;
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
  void syncAgents(Map<String, AgentState> agentStates) {
    for (final station in kStations) {
      final ch = characters[station.agentId]!;
      final agentState = agentStates[station.agentId];

      if (agentState != null) {
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
  }

  void _activateCharacter(GameCharacter ch) {
    ch.isOnSkateboard = false;
    if (ch.seat == null) {
      ch.state = CharState.typing;
      ch.frame = 0;
      ch.frameTimer = 0;
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
    _updateCat(dt);
    _updatePlants(dt);
    _updateCoffeeMachine(dt);
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
            final target = walkableTiles[_rng.nextInt(walkableTiles.length)];
            final path = _findPathForCharacter(ch, target.col, target.row);
            if (path.isNotEmpty) {
              ch.path = path;
              ch.moveProgress = 0;
              ch.wanderCount++;
              // Decide if skateboarding
              final wantSkate = ch.hasCoffee
                  ? _rng.nextDouble() < kCoffeeSkateChance
                  : _rng.nextDouble() < kSkateboardChance;
              if (wantSkate) {
                // Enter mount phase before walking
                ch.isOnSkateboard = true;
                ch.state = CharState.skateMount;
                ch.frame = 0;
                ch.frameTimer = 0;
              } else {
                ch.state = CharState.walk;
                ch.frame = 0;
                ch.frameTimer = 0;
              }
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
        final walkSpeed = ch.isOnSkateboard ? kSkateboardSpeed : kWalkSpeedPxPerSec;
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
          ch.seatTimer = _randomRange(kSeatRestMin, kSeatRestMax);
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
    // Pick a random hired agent's desk
    final hiredStations = kStations.where((s) {
      final ch = characters[s.agentId];
      return ch != null && ch.isHired;
    }).toList();
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
    final expired = <int>[];
    for (final entry in plantEasterEgg.activeTimers.entries) {
      plantEasterEgg.activeTimers[entry.key] = entry.value - dt;
      if (entry.value - dt <= 0) expired.add(entry.key);
    }
    for (final k in expired) {
      plantEasterEgg.activeTimers.remove(k);
    }
  }

  void activatePlant(int index) {
    plantEasterEgg.activeTimers[index] = kPlantAnimDuration;
  }

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
