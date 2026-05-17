import 'dart:math' as math;

import '../../models/game_economy.dart';

const int kSnapRadius = 2;

/// Returns the snapped column for a ghost room being placed.
///
/// Checks whether the ghost's right or left edge is within [kSnapRadius] tiles
/// of an existing room or corridor anchor, with a y-axis overlap requirement.
/// Snap priority: room edges first, then corridor tiles. Uses rotation-aware
/// `footprintWidth/Height` so rotated targets snap correctly.
int snapGhostCol(
  int ghostCol,
  int ghostRow,
  int ghostCols,
  int ghostRows,
  List<PlacedRoom> placedRooms, {
  List<PlacedCorridor> placedCorridors = const [],
}) {
  int bestSnapCol = ghostCol;
  double bestDist = double.infinity;

  final ghostRight = ghostCol + ghostCols;
  final ghostTop = ghostRow;
  final ghostBottom = ghostRow + ghostRows;

  for (final room in placedRooms) {
    final roomLeft = room.col;
    final roomRight = room.col + room.footprintWidth;
    final roomTop = room.row;
    final roomBottom = room.row + room.footprintHeight;

    final gapRight = roomLeft - ghostRight;
    if (gapRight.abs() <= kSnapRadius) {
      final yOverlap = snapOverlap(ghostTop, ghostBottom, roomTop, roomBottom);
      if (yOverlap > 0) {
        final snapCol = roomLeft - ghostCols;
        final dist =
            snapGhostDistToRoom(snapCol, ghostRow, ghostCols, ghostRows, room);
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapCol = snapCol;
        }
      }
    }

    final gapLeft = roomRight - ghostCol;
    if (gapLeft.abs() <= kSnapRadius) {
      final yOverlap = snapOverlap(ghostTop, ghostBottom, roomTop, roomBottom);
      if (yOverlap > 0) {
        final snapCol = roomRight;
        final dist =
            snapGhostDistToRoom(snapCol, ghostRow, ghostCols, ghostRows, room);
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapCol = snapCol;
        }
      }
    }
  }

  // Corridor snap — lower priority via `+kCorridorSnapPenalty` distance bias
  // so room-edges always win ties. A corridor tile is treated as a 1×1 anchor.
  for (final corridor in placedCorridors) {
    for (final tile in corridor.tiles) {
      if (tile.row < ghostTop || tile.row >= ghostBottom) continue;

      final gapRight = tile.col - ghostRight;
      if (gapRight.abs() <= kSnapRadius) {
        final snapCol = tile.col - ghostCols;
        final dist = snapGhostDistToTile(
                snapCol, ghostRow, ghostCols, ghostRows, tile.col, tile.row) +
            kCorridorSnapPenalty;
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapCol = snapCol;
        }
      }

      final gapLeft = (tile.col + 1) - ghostCol;
      if (gapLeft.abs() <= kSnapRadius) {
        final snapCol = tile.col + 1;
        final dist = snapGhostDistToTile(
                snapCol, ghostRow, ghostCols, ghostRows, tile.col, tile.row) +
            kCorridorSnapPenalty;
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapCol = snapCol;
        }
      }
    }
  }

  return bestSnapCol;
}

/// Returns the snapped row for a ghost room being placed.
///
/// Checks whether the ghost's bottom or top edge is within [kSnapRadius] tiles
/// of an existing room or corridor tile, with an x-axis overlap requirement.
int snapGhostRow(
  int ghostCol,
  int ghostRow,
  int ghostCols,
  int ghostRows,
  List<PlacedRoom> placedRooms, {
  List<PlacedCorridor> placedCorridors = const [],
}) {
  int bestSnapRow = ghostRow;
  double bestDist = double.infinity;

  final ghostLeft = ghostCol;
  final ghostRight = ghostCol + ghostCols;
  final ghostBottom = ghostRow + ghostRows;

  for (final room in placedRooms) {
    final roomLeft = room.col;
    final roomRight = room.col + room.footprintWidth;
    final roomTop = room.row;
    final roomBottom = room.row + room.footprintHeight;

    final gapBottom = roomTop - ghostBottom;
    if (gapBottom.abs() <= kSnapRadius) {
      final xOverlap = snapOverlap(ghostLeft, ghostRight, roomLeft, roomRight);
      if (xOverlap > 0) {
        final snapRow = roomTop - ghostRows;
        final dist =
            snapGhostDistToRoom(ghostCol, snapRow, ghostCols, ghostRows, room);
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapRow = snapRow;
        }
      }
    }

    final gapTop = roomBottom - ghostRow;
    if (gapTop.abs() <= kSnapRadius) {
      final xOverlap = snapOverlap(ghostLeft, ghostRight, roomLeft, roomRight);
      if (xOverlap > 0) {
        final snapRow = roomBottom;
        final dist =
            snapGhostDistToRoom(ghostCol, snapRow, ghostCols, ghostRows, room);
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapRow = snapRow;
        }
      }
    }
  }

  for (final corridor in placedCorridors) {
    for (final tile in corridor.tiles) {
      if (tile.col < ghostLeft || tile.col >= ghostRight) continue;

      final gapBottom = tile.row - ghostBottom;
      if (gapBottom.abs() <= kSnapRadius) {
        final snapRow = tile.row - ghostRows;
        final dist = snapGhostDistToTile(
                ghostCol, snapRow, ghostCols, ghostRows, tile.col, tile.row) +
            kCorridorSnapPenalty;
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapRow = snapRow;
        }
      }

      final gapTop = (tile.row + 1) - ghostRow;
      if (gapTop.abs() <= kSnapRadius) {
        final snapRow = tile.row + 1;
        final dist = snapGhostDistToTile(
                ghostCol, snapRow, ghostCols, ghostRows, tile.col, tile.row) +
            kCorridorSnapPenalty;
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapRow = snapRow;
        }
      }
    }
  }

  return bestSnapRow;
}

/// Bias added to corridor-snap distance so room-edge snaps win ties. Big
/// enough to outrank any in-radius room candidate but small enough that pure
/// corridor-only snap still latches.
const double kCorridorSnapPenalty = 100.0;

/// Returns the overlap length between two 1D ranges [a1, a2) and [b1, b2).
int snapOverlap(int a1, int a2, int b1, int b2) {
  final start = math.max(a1, b1);
  final end = math.min(a2, b2);
  return (end - start).clamp(0, double.infinity).toInt();
}

/// Euclidean distance from ghost center to placed room center, using
/// rotation-aware footprint.
double snapGhostDistToRoom(int ghostCol, int ghostRow, int ghostCols,
    int ghostRows, PlacedRoom room) {
  final ghostCenterX = ghostCol + ghostCols / 2.0;
  final ghostCenterY = ghostRow + ghostRows / 2.0;
  final roomCenterX = room.col + room.footprintWidth / 2.0;
  final roomCenterY = room.row + room.footprintHeight / 2.0;
  final dx = ghostCenterX - roomCenterX;
  final dy = ghostCenterY - roomCenterY;
  return math.sqrt(dx * dx + dy * dy);
}

/// Euclidean distance from ghost center to a single corridor tile center.
double snapGhostDistToTile(int ghostCol, int ghostRow, int ghostCols,
    int ghostRows, int tileCol, int tileRow) {
  final ghostCenterX = ghostCol + ghostCols / 2.0;
  final ghostCenterY = ghostRow + ghostRows / 2.0;
  final dx = ghostCenterX - (tileCol + 0.5);
  final dy = ghostCenterY - (tileRow + 0.5);
  return math.sqrt(dx * dx + dy * dy);
}

/// Backwards-compat alias kept for any older call sites; new code should use
/// [snapGhostDistToRoom] directly.
double snapGhostDist(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
        PlacedRoom room) =>
    snapGhostDistToRoom(ghostCol, ghostRow, ghostCols, ghostRows, room);
