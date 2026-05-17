/// Geometric door computation: figures out which edge tiles of a placed room
/// are "open" (gap in the wall) because they touch another room or a corridor.
///
/// Doors aren't persisted — they emerge from the layout. When a room snaps
/// flush against an existing room, the shared-edge tiles automatically become
/// passages. Removing the neighbour reseals the wall.
library;

import '../../models/game_economy.dart';

/// Per-side sets of tile indices along the room's edge that should be drawn
/// as a gap instead of a solid wall.
///
/// - [top] / [bottom] are absolute COL indices along the corresponding edge
/// - [left] / [right] are absolute ROW indices along the corresponding edge
class RoomDoorSet {
  final Set<int> top;
  final Set<int> right;
  final Set<int> bottom;
  final Set<int> left;

  const RoomDoorSet({
    this.top = const {},
    this.right = const {},
    this.bottom = const {},
    this.left = const {},
  });

  bool get isEmpty =>
      top.isEmpty && right.isEmpty && bottom.isEmpty && left.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

/// Returns the set of edge tiles of [room] that are open because they touch
/// another room or a corridor tile.
///
/// Pass [neighborRooms] and [neighborCorridors] containing every placed room
/// (including [room] itself — it's filtered out by id) and every corridor.
///
/// Doors that the player has explicitly closed via `PlacedRoom.closedDoors`
/// are filtered out — those edge tiles render as solid wall again.
RoomDoorSet computeRoomDoors(
  PlacedRoom room,
  List<PlacedRoom> neighborRooms,
  List<PlacedCorridor> neighborCorridors,
) {
  final occupied = <int, Set<int>>{};

  void mark(int col, int row) {
    (occupied[row] ??= <int>{}).add(col);
  }

  bool isOccupied(int col, int row) =>
      occupied[row]?.contains(col) ?? false;

  for (final other in neighborRooms) {
    if (other.id == room.id) continue;
    for (int dc = 0; dc < other.footprintWidth; dc++) {
      for (int dr = 0; dr < other.footprintHeight; dr++) {
        mark(other.col + dc, other.row + dr);
      }
    }
  }

  for (final corridor in neighborCorridors) {
    for (final tile in corridor.tiles) {
      mark(tile.col, tile.row);
      if (corridor.wide) mark(tile.col + 1, tile.row);
    }
  }

  final top = <int>{};
  final bottom = <int>{};
  final left = <int>{};
  final right = <int>{};

  final w = room.footprintWidth;
  final h = room.footprintHeight;

  for (int dc = 0; dc < w; dc++) {
    final c = room.col + dc;
    if (isOccupied(c, room.row - 1)) top.add(c);
    if (isOccupied(c, room.row + h)) bottom.add(c);
  }
  for (int dr = 0; dr < h; dr++) {
    final r = room.row + dr;
    if (isOccupied(room.col - 1, r)) left.add(r);
    if (isOccupied(room.col + w, r)) right.add(r);
  }

  // Subtract player-closed doors. Each closedDoor coord is the interior
  // edge-tile (inside the room footprint) where the gap would have been.
  for (final d in room.closedDoors) {
    if (d.row == room.row) top.remove(d.col);
    if (d.row == room.row + h - 1) bottom.remove(d.col);
    if (d.col == room.col) left.remove(d.row);
    if (d.col == room.col + w - 1) right.remove(d.row);
  }

  return RoomDoorSet(top: top, right: right, bottom: bottom, left: left);
}
