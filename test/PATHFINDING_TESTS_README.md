# Pathfinding BFS Unit Tests

## Overview

This directory contains comprehensive unit tests for the **BFS (Breadth-First Search) pathfinding algorithm** used in `OfficeGameState.calculatePath()`.

The tests verify three critical properties:

### 1. **Correct Path Finding** ✓
- Finds shortest paths in open fields
- Handles orthogonal movement (up, down, left, right)
- Maintains path continuity (each step is adjacent)
- Uses only walkable floor tiles

### 2. **Collision & Obstacle Detection** ✓
- Respects blocked tiles (desks, seats, furniture)
- Navigates around walls and multi-tile obstacles
- Prevents pathfinding through occupied spaces
- Handles tight corridors and complex room layouts

### 3. **Edge Cases & Robustness** ✓
- Returns empty path when start equals destination
- Returns empty path for unreachable destinations
- Rejects paths to walls or blocked tiles
- Handles out-of-bounds coordinates gracefully

---

## Test Files

### `test/pathfinding_bfs_test.dart`
**Standalone Dart test suite** (no Flutter dependencies)

- **18 test cases** across 4 groups
- Can be run directly: `dart test/pathfinding_bfs_test.dart`
- **Status**: All 18/18 tests passing ✓

**Test Groups:**
1. **Basic Pathfinding** (4 tests)
   - Horizontal & vertical movement
   - Diagonal (Manhattan) paths
   - Path continuity verification

2. **Collision Detection** (4 tests)
   - Single blocked tile avoidance
   - Vertical wall navigation
   - 2×2 obstacle handling
   - Desk station blocking

3. **Edge Cases** (7 tests)
   - Start equals end
   - Unreachable destinations
   - Wall destinations
   - Blocked destinations
   - Out-of-bounds handling
   - Tight corridor navigation
   - Large obstacle circumnavigation

4. **Pathfinding Optimality** (3 tests)
   - Shortest path verification
   - Floor-only tile usage
   - Open field optimality

### `test/widgets/canvas/office_game_state_pathfinding_test.dart`
**Flutter widget test suite** (requires Flutter)

- Mirrors `pathfinding_bfs_test.dart` with Flutter testing conventions
- Integration tests with `OfficeGameState` instance
- Tests blocked desk stations and game map verification
- Verifies tile map layout respects room geometry
- Path continuity and walkability assertions

---

## Running the Tests

### Standalone Dart Tests (Recommended for CI/CD)
```bash
cd /path/to/PixelCode
dart test/pathfinding_bfs_test.dart
```

**Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BFS Pathfinding Unit Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Basic Pathfinding: 4 passed, 0 failed
2. Collision Detection: 4 passed, 0 failed
3. Edge Cases: 7 passed, 0 failed
4. Pathfinding Optimality: 3 passed, 0 failed

Total: 18/18 passed, 0 failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Flutter Widget Tests
```bash
flutter test test/widgets/canvas/office_game_state_pathfinding_test.dart
```

---

## Algorithm Details

### BFS Pathfinding Implementation
Located in `lib/widgets/canvas/office_game_state.dart` (lines 359–402)

```dart
List<TilePos> _findPath(
  int startCol, int startRow,
  int endCol, int endRow,
  List<List<TileType>> tileMap,
  Set<String> blocked,
)
```

**Key Features:**
- **Orthogonal Movement**: Up, down, left, right (4-directional)
- **Walkability Check**: Respects walls and blocked tiles
- **Shortest Path Guarantee**: BFS explores all tiles at distance N before distance N+1
- **Parent Tracking**: Reconstructs path by backtracking from destination to start
- **Early Exit**: Returns empty path if destination unreachable

### Helper Function
```dart
bool _isWalkable(int col, int row, List<List<TileType>> tileMap, Set<String> blocked)
```
Validates if a tile is:
- Within grid bounds
- Not a wall (`TileType.wall`)
- Not in the blocked set (desks, seats, furniture, etc.)

---

## Test Coverage Matrix

| Scenario | Test | Status |
|----------|------|--------|
| Straight horizontal path | `finds straight path horizontally` | ✓ |
| Straight vertical path | `finds straight path vertically` | ✓ |
| Diagonal movement | `finds diagonal path (Manhattan)` | ✓ |
| Path continuity | `path is continuous` | ✓ |
| Single obstacle avoidance | `avoids single blocked tile` | ✓ |
| Vertical wall avoidance | `avoids vertical wall` | ✓ |
| Multi-tile obstacle | `navigates 2x2 obstacle` | ✓ |
| Desk station blocking | `blocks desk stations` | ✓ |
| Start = end | `returns empty when start equals end` | ✓ |
| Unreachable destination | `returns empty when destination unreachable` | ✓ |
| Wall destination | `returns empty when destination is wall` | ✓ |
| Blocked destination | `returns empty when destination is blocked` | ✓ |
| Out-of-bounds destination | `returns empty for out-of-bounds destination` | ✓ |
| Tight corridor | `handles tight 1-tile corridor` | ✓ |
| Large obstacle | `finds path around large obstacle` | ✓ |
| Shortest path | `BFS finds shortest path` | ✓ |
| Floor-only tiles | `path uses only floor tiles` | ✓ |
| Open field optimality | `optimal path through open field` | ✓ |

---

## Integration with OfficeGameState

### Character Pathfinding
Characters use pathfinding via:
- `_findPathForCharacter()`: Temporarily removes character's own seat from blocked set
- `_buildSkateLoopPath()`: Chains multiple waypoints for skateboard routes
- `_findPathToCoffeeArea()`: Pathfinds to adjacent tiles near coffee machine

### Blocked Tiles Sources
1. **Desk Stations**: All seats and desks
2. **Coffee Machine**: Located at (13, 1) and (14, 1)
3. **Snack Table**: At (15, 1)
4. **Foreman Zone**: Bottom-right corner (blocks upper tile)
5. **Placed Furniture**: Items marked with `blocksPath`
6. **Room Internals**: Couches, tables, racks within room footprints

---

## Future Enhancements

- [ ] Diagonal movement support (8-directional)
- [ ] Path smoothing (reduce zigzag artifacts)
- [ ] A* heuristic for performance on large maps
- [ ] Dynamic obstacle avoidance (moving characters)
- [ ] Path caching for repeated start→end pairs

---

## Known Issues & Limitations

1. **Path Reconstruction**: Uses string keys (`"col,row"`) which is slower than integer hashing
2. **No Diagonal Movement**: BFS only explores 4 directions (Manhattan distance)
3. **No Path Optimization**: Returns raw BFS path without smoothing or pruning
4. **Blocked Set Overhead**: Set lookup is O(1) but allocation is O(n) per pathfind call

---

## References

- **BFS Algorithm**: Classic uninformed search; optimal for unweighted graphs
- **Tile Map Layout**: `OfficeGameState._buildTileMap()` (line 739)
- **Blocked Tiles**: `OfficeGameState._buildBlockedTiles()` (line 766)
- **Game Constants**: Top of `office_game_state.dart` (kGridCols, kGridRows, etc.)
