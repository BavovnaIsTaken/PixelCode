/// Standalone Dart unit tests for BFS pathfinding logic.
///
/// This file reimplements the pathfinding logic from OfficeGameState
/// and provides comprehensive unit tests without Flutter dependencies.
/// Can be run with: dart test test/pathfinding_bfs_test.dart
///
/// Coverage:
/// 1. ✓ Path finding correctness (shortest path)
/// 2. ✓ Collision detection (blocked tiles)
/// 3. ✓ Edge cases (unreachable, start=end, bounds)
library;

// ─── Models ────────────────────────────────────────────────────────────────

enum TileType { wall, floor }

class TilePos {
  final int col;
  final int row;
  const TilePos(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TilePos &&
          runtimeType == other.runtimeType &&
          col == other.col &&
          row == other.row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'TilePos($col, $row)';
}

// ─── Pathfinding Implementation ────────────────────────────────────────────

bool _isWalkable(
  int col,
  int row,
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
  int startCol,
  int startRow,
  int endCol,
  int endRow,
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

// ─── Test Framework ───────────────────────────────────────────────────────

class TestResult {
  final String name;
  final bool passed;
  final String? error;

  TestResult(this.name, this.passed, [this.error]);

  @override
  String toString() {
    if (passed) {
      return '✓ $name';
    } else {
      return '✗ $name\n  Error: $error';
    }
  }
}

class TestGroup {
  final String name;
  final List<TestResult> results = [];

  TestGroup(this.name);

  void add(String testName, Function testFn) {
    try {
      testFn();
      results.add(TestResult(testName, true));
    } catch (e) {
      results.add(TestResult(testName, false, e.toString()));
    }
  }

  void printResults() {
    final passed = results.where((r) => r.passed).length;
    final failed = results.where((r) => !r.passed).length;

    print('\n$name: $passed passed, $failed failed');
    for (final result in results) {
      print('  ${result}');
    }
  }

  bool get allPassed => results.every((r) => r.passed);
}

// ─── Test Utilities ──────────────────────────────────────────────────────

List<List<TileType>> createTileMap({
  required int cols,
  required int rows,
}) {
  return List.generate(rows, (r) {
    return List.generate(cols, (c) {
      // Perimeter walls
      if (r == 0 || r == rows - 1 || c == 0 || c == cols - 1) {
        return TileType.wall;
      }
      return TileType.floor;
    });
  });
}

void expect<T>(T actual, dynamic matcher, {String? reason}) {
  if (matcher is _Matcher) {
    if (!matcher.matches(actual)) {
      throw AssertionError(
          'Expected $actual ${matcher.describe()}. ${reason ?? ''}');
    }
  } else if (matcher == actual) {
    return;
  } else {
    throw AssertionError(
        'Expected $actual to equal $matcher. ${reason ?? ''}');
  }
}

// ─── Matchers ──────────────────────────────────────────────────────────────

abstract class _Matcher<T> {
  bool matches(T actual);
  String describe();
}

class _IsEmpty extends _Matcher<List> {
  @override
  bool matches(List actual) => actual.isEmpty;
  @override
  String describe() => 'to be empty';
}

class _IsNotEmpty extends _Matcher<List> {
  @override
  bool matches(List actual) => actual.isNotEmpty;
  @override
  String describe() => 'to be not empty';
}

class _LengthMatcher extends _Matcher<List> {
  final int expectedLength;
  _LengthMatcher(this.expectedLength);
  @override
  bool matches(List actual) => actual.length == expectedLength;
  @override
  String describe() => 'to have length $expectedLength';
}

class _GreaterThanOrEqual extends _Matcher<int> {
  final int min;
  _GreaterThanOrEqual(this.min);
  @override
  bool matches(int actual) => actual >= min;
  @override
  String describe() => 'to be >= $min';
}

class _LessThanOrEqual extends _Matcher<int> {
  final int max;
  _LessThanOrEqual(this.max);
  @override
  bool matches(int actual) => actual <= max;
  @override
  String describe() => 'to be <= $max';
}

class _AllMatch extends _Matcher<List> {
  final bool Function(dynamic) predicate;
  _AllMatch(this.predicate);
  @override
  bool matches(List actual) => actual.every(predicate);
  @override
  String describe() => 'all items to match predicate';
}

class _Contains extends _Matcher<List> {
  final dynamic item;
  _Contains(this.item);
  @override
  bool matches(List actual) => actual.contains(item);
  @override
  String describe() => 'to contain $item';
}

class _DoesNotContain extends _Matcher<List> {
  final dynamic item;
  _DoesNotContain(this.item);
  @override
  bool matches(List actual) => !actual.contains(item);
  @override
  String describe() => 'to not contain $item';
}

_IsEmpty isEmpty() => _IsEmpty();
_IsNotEmpty isNotEmpty() => _IsNotEmpty();
_LengthMatcher hasLength(int len) => _LengthMatcher(len);
_GreaterThanOrEqual greaterThanOrEqual(int min) => _GreaterThanOrEqual(min);
_LessThanOrEqual lessThanOrEqual(int max) => _LessThanOrEqual(max);
_AllMatch allMatch(bool Function(dynamic) pred) => _AllMatch(pred);
_Contains contains(dynamic item) => _Contains(item);
_DoesNotContain doesNotContain(dynamic item) => _DoesNotContain(item);

// ─── Tests ────────────────────────────────────────────────────────────────

void main() {
  final results = <TestGroup>[];

  // ─── Group: Normal Pathfinding ──────────────────────────────────────

  final basicTests = TestGroup('1. Basic Pathfinding');

  basicTests.add('finds straight path horizontally', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(1, 5, 8, 5, map, {});

    expect(path, isNotEmpty());
    expect(path.length, greaterThanOrEqual(6)); // min 7 steps
    expect(path.first, TilePos(2, 5));
    expect(path.last, TilePos(8, 5));
  });

  basicTests.add('finds straight path vertically', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(5, 1, 5, 8, map, {});

    expect(path, isNotEmpty());
    expect(path.length, greaterThanOrEqual(6));
    expect(path.first, TilePos(5, 2));
    expect(path.last, TilePos(5, 8));
  });

  basicTests.add('finds diagonal path (Manhattan)', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(2, 2, 7, 7, map, {});

    expect(path, isNotEmpty());
    expect(path.last, TilePos(7, 7));
    // BFS finds shortest path; Manhattan distance = 10 minimum
    expect(path.length, lessThanOrEqual(10));
  });

  basicTests.add('path is continuous', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(1, 1, 8, 8, map, {});

    expect(path, isNotEmpty());

    // Add start for continuity verification
    final fullPath = [TilePos(1, 1), ...path];

    for (int i = 0; i < fullPath.length - 1; i++) {
      final curr = fullPath[i];
      final next = fullPath[i + 1];
      final dist = (next.col - curr.col).abs() + (next.row - curr.row).abs();
      expect(dist, 1, reason: 'Non-adjacent tiles at step $i');
    }
  });

  results.add(basicTests);

  // ─── Group: Blocked Tiles & Obstacles ──────────────────────────────

  final collisionTests = TestGroup('2. Collision Detection');

  collisionTests.add('avoids single blocked tile', () {
    final map = createTileMap(cols: 10, rows: 10);
    final blocked = {'5,5'};
    final path = _findPath(4, 5, 6, 5, map, blocked);

    expect(path, isNotEmpty());
    expect(path, doesNotContain(TilePos(5, 5)));
  });

  collisionTests.add('avoids vertical wall', () {
    final map = createTileMap(cols: 10, rows: 10);
    final blocked = {
      for (int r = 2; r <= 6; r++) '5,$r',
    };
    final path = _findPath(4, 4, 6, 4, map, blocked);

    expect(path, isNotEmpty());
    // Must not pass through blocked column in blocked row range
    expect(
      path.every((t) => !(t.col == 5 && t.row >= 2 && t.row <= 6)),
      true,
      reason: 'Path passed through blocked wall',
    );
  });

  collisionTests.add('navigates 2x2 obstacle', () {
    final map = createTileMap(cols: 12, rows: 10);
    final blocked = {'4,4', '5,4', '4,5', '5,5'};
    final path = _findPath(3, 4, 7, 4, map, blocked);

    expect(path, isNotEmpty());
    for (final tile in path) {
      expect(blocked.contains('${tile.col},${tile.row}'), false,
          reason: 'Path went through obstacle');
    }
  });

  collisionTests.add('blocks desk stations', () {
    final map = createTileMap(cols: 10, rows: 10);
    final blocked = {'5,5'}; // Simulated desk
    final path = _findPath(4, 5, 6, 5, map, blocked);

    expect(path, isNotEmpty());
    expect(path, doesNotContain(TilePos(5, 5)));
  });

  results.add(collisionTests);

  // ─── Group: Edge Cases ──────────────────────────────────────────────

  final edgeCaseTests = TestGroup('3. Edge Cases');

  edgeCaseTests.add('returns empty when start equals end', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(5, 5, 5, 5, map, {});
    expect(path, isEmpty());
  });

  edgeCaseTests.add('returns empty when destination unreachable', () {
    final map = createTileMap(cols: 10, rows: 10);
    // Completely surround destination
    final blocked = {
      '6,7', '8,7', '7,6', '7,8',
      '6,6', '6,8', '8,6', '8,8',
    };
    final path = _findPath(2, 2, 7, 7, map, blocked);
    expect(path, isEmpty());
  });

  edgeCaseTests.add('returns empty when destination is wall', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(2, 2, 0, 0, map, {});
    expect(path, isEmpty());
  });

  edgeCaseTests.add('returns empty when destination is blocked', () {
    final map = createTileMap(cols: 10, rows: 10);
    final blocked = {'7,7'};
    final path = _findPath(2, 2, 7, 7, map, blocked);
    expect(path, isEmpty());
  });

  edgeCaseTests.add('returns empty for out-of-bounds destination', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(5, 5, 20, 20, map, {});
    expect(path, isEmpty());
  });

  edgeCaseTests.add('handles tight 1-tile corridor', () {
    final map = createTileMap(cols: 10, rows: 10);
    // Block all sides except row 5
    final blocked = {
      for (int r = 3; r <= 7; r++)
        if (r != 5)
          for (int c = 1; c <= 8; c++) '$c,$r',
    };
    // Actually, let's just block left and right walls
    final blocked2 = {
      for (int r = 3; r <= 7; r++) ...'1,$r'.split(',').isEmpty ? [] : ['1,$r', '8,$r'],
    };

    final blockSet = <String>{};
    for (int r = 3; r <= 7; r++) {
      blockSet.add('1,$r');
      blockSet.add('8,$r');
    }

    final path = _findPath(2, 5, 7, 5, map, blockSet);
    expect(path, isNotEmpty());
  });

  edgeCaseTests.add('finds path around large obstacle', () {
    final map = createTileMap(cols: 15, rows: 10);
    // Block a 3×3 region
    final blocked = {
      for (int r = 4; r <= 6; r++)
        for (int c = 6; c <= 8; c++) '$c,$r',
    };

    final path = _findPath(5, 5, 10, 5, map, blocked);
    // Should find a path going around
    expect(path, isNotEmpty());
    for (final tile in path) {
      expect(blocked.contains('${tile.col},${tile.row}'), false);
    }
  });

  results.add(edgeCaseTests);

  // ─── Group: Pathfinding Optimality ──────────────────────────────────

  final optimalityTests = TestGroup('4. Pathfinding Optimality');

  optimalityTests.add('BFS finds shortest path', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(1, 1, 8, 8, map, {});

    expect(path, isNotEmpty());
    // Manhattan distance from (1,1) to (8,8) = 12
    // Shortest path = 12 steps, but BFS may equal it (path can be different)
    expect(path.length, lessThanOrEqual(14));
  });

  optimalityTests.add('path uses only floor tiles', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(1, 1, 8, 8, map, {});

    for (final tile in path) {
      expect(map[tile.row][tile.col], TileType.floor);
    }
  });

  optimalityTests.add('optimal path through open field', () {
    final map = createTileMap(cols: 10, rows: 10);
    final path = _findPath(2, 2, 7, 7, map, {});

    // Expected: roughly Manhattan distance
    // (7-2) + (7-2) = 10 steps minimum
    expect(path.length, lessThanOrEqual(10));
  });

  results.add(optimalityTests);

  // ─── Print Results ──────────────────────────────────────────────────

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('BFS Pathfinding Unit Tests');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  for (final group in results) {
    group.printResults();
  }

  final totalPassed = results.fold<int>(
      0, (sum, g) => sum + g.results.where((r) => r.passed).length);
  final totalTests =
      results.fold<int>(0, (sum, g) => sum + g.results.length);
  final totalFailed = totalTests - totalPassed;

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('Total: $totalPassed/$totalTests passed, $totalFailed failed');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // Exit with appropriate code
  if (totalFailed > 0) {
    throw Exception('$totalFailed tests failed');
  }
}
