/// Pure Build-Mode placement logic — ghost validity + anchor math, extracted
/// from `agent_canvas.dart` so that:
///   * "green ghost == placeable" parity is enforced in ONE place and is unit
///     testable (the old split between the ghost color and the commit gate is
///     what produced the "it's green but Place does nothing" bug — most
///     visibly the per-type room cap);
///   * the cursor→tile anchor rule is shared and testable.
///
/// No Flutter / Riverpod imports — primitives in, value objects out.
library;

import 'dart:math' as math;

import '../../models/game_economy.dart';

/// Why a build-mode ghost can't be placed. Drives the red ghost tint and the
/// Place-bar reason text.
enum GhostInvalidReason {
  /// Ghost lies wholly or partly outside the tier's fixed lot (any edge).
  outOfBounds,

  /// Ghost overlaps an already-placed room.
  overlap,

  /// Ghost overlaps a blocked tile (chair, foreman, decor) inside the grid.
  blocked,

  /// Already placed the maximum number of this room type for the office.
  atCap,

  /// Player doesn't have enough grymni to pay for the room.
  insufficientGrymni,
}

/// Ghost validity used by build mode.
///
/// - `valid` — fits inside the tier's fixed lot, no overlap, affordable.
/// - `invalid` — `reason` holds the specific cause for the Place Bar.
///
/// Stage 4 (fixed-tier shells) removed the `pendingExpand` state: there is no
/// foundation buffer or per-tile expansion anymore — the lot is a fixed size
/// per tier, so a ghost either fits or it doesn't.
class GhostStatus {
  final bool valid;
  final GhostInvalidReason? reason;

  const GhostStatus.valid()
      : valid = true,
        reason = null;

  const GhostStatus.invalid(this.reason) : valid = false;
}

/// Immutable snapshot fed to [computeGhostStatus]. The caller resolves the
/// rotation-aware footprint, the per-type cap, and the cost the commit will
/// charge (room cost or template bundle cost).
class BuildGhostInput {
  /// Footprint top-left tile.
  final int col;
  final int row;

  /// Rotation-aware footprint size in tiles.
  final int width;
  final int height;

  /// Fixed lot size for the current tier, INCLUDING the 1-tile wall border on
  /// each side.
  final int gridCols;
  final int gridRows;

  /// Occupied tiles (chairs, foreman, blocking furniture, room internals).
  final Set<String> blockedTiles;

  /// Already-placed rooms (for footprint overlap).
  final List<PlacedRoom> rooms;

  /// How many of the selected room type are already placed, and the cap.
  final int roomCount;
  final int maxPerOffice;

  /// Player balance and the cost the commit will charge.
  final int grymni;
  final int roomCost;

  const BuildGhostInput({
    required this.col,
    required this.row,
    required this.width,
    required this.height,
    required this.gridCols,
    required this.gridRows,
    required this.blockedTiles,
    required this.rooms,
    required this.roomCount,
    required this.maxPerOffice,
    required this.grymni,
    required this.roomCost,
  });
}

/// The single source of truth for whether a room/template ghost can be placed.
/// Used by BOTH the ghost color/Place-bar enable AND (transitively) the commit
/// gate, so the two can never disagree.
GhostStatus computeGhostStatus(BuildGhostInput i) {
  final gc = i.col;
  final gr = i.row;
  final gw = i.width;
  final gh = i.height;

  // 1. Per-type cap — the headline "green but Place does nothing" fix.
  if (i.roomCount >= i.maxPerOffice) {
    return const GhostStatus.invalid(GhostInvalidReason.atCap);
  }

  // 2. Bounds — the ghost must fit entirely inside the tier's fixed lot
  //    (the playable area between the 1-tile walls on every side).
  if (gc < 1 ||
      gr < 1 ||
      gc + gw > i.gridCols - 1 ||
      gr + gh > i.gridRows - 1) {
    return const GhostStatus.invalid(GhostInvalidReason.outOfBounds);
  }

  // 3. Overlap with existing rooms (rotation-aware footprints).
  for (final r in i.rooms) {
    final ox = gc < r.col + r.footprintWidth && gc + gw > r.col;
    final oy = gr < r.row + r.footprintHeight && gr + gh > r.row;
    if (ox && oy) {
      return const GhostStatus.invalid(GhostInvalidReason.overlap);
    }
  }

  // 4. Blocked-tile overlap (desks, seats, foreman, blocking furniture).
  for (int dc = 0; dc < gw; dc++) {
    for (int dr = 0; dr < gh; dr++) {
      if (i.blockedTiles.contains('${gc + dc},${gr + dr}')) {
        return const GhostStatus.invalid(GhostInvalidReason.blocked);
      }
    }
  }

  // 5. Affordability — must be gated here too, else an unaffordable room shows
  //    green and silently fails on commit.
  if (i.grymni < i.roomCost) {
    return const GhostStatus.invalid(GhostInvalidReason.insufficientGrymni);
  }
  return const GhostStatus.valid();
}

/// Footprint top-left so a [width]×[height] item is centred under the cursor
/// tile [cursorCol],[cursorRow]. For 1×1 items this is the cursor tile itself;
/// for multi-tile rooms it stops the footprint growing down-and-right of the
/// pointer (the old top-left anchor was the main "snaps somewhere unclear").
({int col, int row}) ghostTopLeft({
  required int cursorCol,
  required int cursorRow,
  required int width,
  required int height,
}) =>
    (col: cursorCol - (width ~/ 2), row: cursorRow - (height ~/ 2));

/// Human-readable Ukrainian reason for why a ghost can't be placed.
String ghostInvalidReasonLabel(GhostInvalidReason? reason) {
  if (reason == null) return 'не вміщується';
  switch (reason) {
    case GhostInvalidReason.outOfBounds:
      return 'за межами офісу';
    case GhostInvalidReason.overlap:
      return 'перекриває кімнату';
    case GhostInvalidReason.blocked:
      return 'на меблях чи персоналі';
    case GhostInvalidReason.atCap:
      return 'ліміт таких кімнат';
    case GhostInvalidReason.insufficientGrymni:
      return 'не вистачає ₲';
  }
}

/// An L-shaped 1-tile corridor path connecting a freshly-placed room footprint
/// (half-open: [footLeft,footRight) × [footTop,footBottom)) to the NEAREST
/// existing room. Empty when there are no rooms or the gap can't be bridged.
/// Pure so the preview the player SEES and the corridor actually BUILT are one
/// and the same path.
List<({int col, int row})> connectingCorridorPath({
  required int footLeft,
  required int footTop,
  required int footRight,
  required int footBottom,
  required List<PlacedRoom> rooms,
  required int gridCols,
  required int gridRows,
}) {
  if (rooms.isEmpty) return const [];
  final gcx = (footLeft + footRight) / 2.0;
  final gcy = (footTop + footBottom) / 2.0;
  PlacedRoom? nearest;
  var best = double.infinity;
  for (final r in rooms) {
    final rcx = r.col + r.footprintWidth / 2.0;
    final rcy = r.row + r.footprintHeight / 2.0;
    final d = (rcx - gcx).abs() + (rcy - gcy).abs();
    if (d < best) {
      best = d;
      nearest = r;
    }
  }
  if (nearest == null) return const [];
  final nrLeft = nearest.col;
  final nrTop = nearest.row;
  final nrRight = nearest.col + nearest.footprintWidth;
  final nrBottom = nearest.row + nearest.footprintHeight;

  // Corridor midlines inside the overlap of the two rects (clamped to the
  // playable inner area).
  final yMid =
      ((math.max(footTop, nrTop) + math.min(footBottom, nrBottom) - 1) / 2)
          .floor()
          .clamp(1, gridRows - 2);
  final xMid =
      ((math.max(footLeft, nrLeft) + math.min(footRight, nrRight) - 1) / 2)
          .floor()
          .clamp(1, gridCols - 2);

  // Horizontal gap segment between the rects' x-extents (none if overlapping).
  int hx1, hx2;
  if (footRight <= nrLeft) {
    hx1 = footRight;
    hx2 = nrLeft;
  } else if (nrRight <= footLeft) {
    hx1 = nrRight;
    hx2 = footLeft;
  } else {
    hx1 = hx2 = 0;
  }

  // Vertical gap segment between the rects' y-extents (none if overlapping).
  int vy1, vy2;
  if (footBottom <= nrTop) {
    vy1 = footBottom;
    vy2 = nrTop;
  } else if (nrBottom <= footTop) {
    vy1 = nrBottom;
    vy2 = footTop;
  } else {
    vy1 = vy2 = 0;
  }

  final tiles = <String, ({int col, int row})>{};
  if (hx2 > hx1) {
    for (var c = hx1; c < hx2; c++) {
      tiles['$c,$yMid'] = (col: c, row: yMid);
    }
  }
  if (vy2 > vy1) {
    for (var r = vy1; r < vy2; r++) {
      tiles['$xMid,$r'] = (col: xMid, row: r);
    }
  }
  return tiles.values.toList();
}
