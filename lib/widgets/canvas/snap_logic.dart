import 'dart:math' as math;

import '../../models/game_economy.dart';

const int kSnapRadius = 2;

/// Returns the snapped column for a ghost room being placed.
///
/// Checks whether the ghost's right or left edge is within [kSnapRadius] tiles
/// of an existing room's left or right edge, with a y-axis overlap requirement.
int snapGhostCol(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
    List<PlacedRoom> placedRooms) {
  int bestSnapCol = ghostCol;
  double bestDist = double.infinity;

  final ghostRight = ghostCol + ghostCols;
  final ghostTop = ghostRow;
  final ghostBottom = ghostRow + ghostRows;

  for (final room in placedRooms) {
    final roomCols = room.type.widthTiles;
    final roomRows = room.type.heightTiles;
    final roomLeft = room.col;
    final roomRight = room.col + roomCols;
    final roomTop = room.row;
    final roomBottom = room.row + roomRows;

    final gapRight = roomLeft - ghostRight;
    if (gapRight.abs() <= kSnapRadius) {
      final yOverlap = snapOverlap(ghostTop, ghostBottom, roomTop, roomBottom);
      if (yOverlap > 0) {
        final snapCol = roomLeft - ghostCols;
        final dist = snapGhostDist(snapCol, ghostRow, ghostCols, ghostRows, room);
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
        final dist = snapGhostDist(snapCol, ghostRow, ghostCols, ghostRows, room);
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
/// of an existing room's top or bottom edge, with an x-axis overlap requirement.
int snapGhostRow(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
    List<PlacedRoom> placedRooms) {
  int bestSnapRow = ghostRow;
  double bestDist = double.infinity;

  final ghostLeft = ghostCol;
  final ghostRight = ghostCol + ghostCols;
  final ghostBottom = ghostRow + ghostRows;

  for (final room in placedRooms) {
    final roomCols = room.type.widthTiles;
    final roomRows = room.type.heightTiles;
    final roomLeft = room.col;
    final roomRight = room.col + roomCols;
    final roomTop = room.row;
    final roomBottom = room.row + roomRows;

    final gapBottom = roomTop - ghostBottom;
    if (gapBottom.abs() <= kSnapRadius) {
      final xOverlap = snapOverlap(ghostLeft, ghostRight, roomLeft, roomRight);
      if (xOverlap > 0) {
        final snapRow = roomTop - ghostRows;
        final dist = snapGhostDist(ghostCol, snapRow, ghostCols, ghostRows, room);
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
        final dist = snapGhostDist(ghostCol, snapRow, ghostCols, ghostRows, room);
        if (dist < bestDist) {
          bestDist = dist;
          bestSnapRow = snapRow;
        }
      }
    }
  }

  return bestSnapRow;
}

/// Returns the overlap length between two 1D ranges [a1, a2) and [b1, b2).
int snapOverlap(int a1, int a2, int b1, int b2) {
  final start = math.max(a1, b1);
  final end = math.min(a2, b2);
  return (end - start).clamp(0, double.infinity).toInt();
}

/// Euclidean distance from ghost center to placed room center.
double snapGhostDist(int ghostCol, int ghostRow, int ghostCols, int ghostRows,
    PlacedRoom room) {
  final ghostCenterX = ghostCol + ghostCols / 2.0;
  final ghostCenterY = ghostRow + ghostRows / 2.0;
  final roomCenterX = room.col + room.type.widthTiles / 2.0;
  final roomCenterY = room.row + room.type.heightTiles / 2.0;
  final dx = ghostCenterX - roomCenterX;
  final dy = ghostCenterY - roomCenterY;
  return math.sqrt(dx * dx + dy * dy);
}
