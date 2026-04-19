# Office Expansion System — Design Document

> PixelCode game · single-floor Build Mode · v1.0

---

## 1. Overview

The office is both a visual stage and a functional resource. As the studio earns ₲, it can unlock larger tiers and spend money on placing rooms that boost throughput, morale, or unlock new mechanics.

**Core tension**: money spent on expansion is money not spent on hiring or hardware upgrades. Every room is a deliberate trade-off.

---

## 2. Office Tiers

Each tier defines the grid canvas and which features are available. The Garage is a scripted prologue; free Build Mode starts at Startup Loft.

| Tier | ID | Grid | Max agents | Build Mode | Upgrade cost |
|---|---|---|---|---|---|
| Гараж | `garage` | 20 × 14 (fixed) | 3 | — scripted — | — |
| Startup Loft | `smallOffice` | 28 × 16 | 5 | unlocked | ₲1 000 |
| Модерн офіс | `modernOffice` | 36 × 20 | 7 | unlocked | ₲5 000 |
| Тех хаб | `techHub` | 44 × 24 | 10 | unlocked | ₲20 000 |
| Кампус | `campus` | 52 × 28 | 14 | unlocked | ₲100 000 |

Grid is always 1 floor (no vertical stacking). Walls are auto-generated from the outer boundary; interior is open canvas.

---

## 3. Room Types — Phase 1 (Startup Loft launch)

Five room types ship with v1. Each has a tile footprint, a base cost, and a passive effect.

### 3.1 Workstation `workstation`
- **Size**: 2 × 2 (desk tile + seat tile + 2 surrounding walkable tiles)
- **Cost**: ₲400
- **Effect**: Provides one additional desk station. Extras of any role without a canonical seat will pathfind to the nearest free workstation instead of wandering seatless.
- **Limit**: Up to 6 extra workstations per office (canonical desks still take priority).
- **Sprite**: standard desk + monitor (same as existing desk sprites, rotated to face Down or Left depending on placement)

### 3.2 Break Room `breakRoom`
- **Size**: 3 × 2 area
- **Cost**: ₲600
- **Effect**: Characters passing through wander 20 % less (longer `seatTimer`), simulating a productivity micro-boost from a nearby rest spot. Contains a couch + small table.
- **Limit**: 2 per office.

### 3.3 Meeting Room `meetingRoom`
- **Size**: 4 × 3 enclosed area
- **Cost**: ₲1 200
- **Effect**: (Future) Speeds up Manager task-dispatch. For now: visual prestige + increases max active agents by 1 (agents treated as always partially active).
- **Limit**: 1 per office tier.

### 3.4 Server Room `serverRoom`
- **Size**: 3 × 2
- **Cost**: ₲2 000
- **Effect**: All agents get a +10 % speed bonus (stacks with hardware tier). Requires at least 1 hired Security agent to be "online" (otherwise bonus is halved).
- **Limit**: 1 per office.
- **Sprite**: server rack sprites from existing `pixel_sprites.dart` `serverRack` symbols.

### 3.5 Lounge / Recreation `lounge`
- **Size**: 4 × 3
- **Cost**: ₲800
- **Effect**: Unlocks the skate ramp easter egg — characters wander to the lounge and perform a skating loop rather than wandering randomly. Increases wander max distance by 30 %. Morale: agents spend less time idle, come back to desk faster.
- **Limit**: 1 per office.

---

## 4. Adjacency Bonuses & Penalties

Rooms placed next to specific neighbours receive bonuses. "Adjacent" = sharing a wall tile.

| Pair | Effect |
|---|---|
| `workstation` + `serverRoom` | +5 % speed on that workstation |
| `breakRoom` + `lounge` | synergy: morale boost doubles |
| `meetingRoom` + any `workstation` | Manager task latency −10 % |
| Two `serverRoom`s | Conflict: only one bonus applies (no stacking) |
| `serverRoom` far from any `workstation` (>8 tiles) | Penalty: −5 % speed (cable cost metaphor) |

Adjacency is computed once when a room is placed and recached on every Build Mode change.

---

## 5. Build Mode UI

Build Mode is a toggle available from the Hub screen settings or a floating button on the canvas.

### 5.1 Flow
1. Player taps **Build Mode** → canvas overlays a semi-transparent grid.
2. Left panel (or bottom sheet) shows a scrollable room catalog.
3. Player selects a room → ghost footprint follows pointer/drag.
4. Ghost turns green if valid placement (all tiles walkable, no overlap), red otherwise.
5. Tap to confirm → deduct ₲, place room, rebuild tile/blocked maps, animate a brief construction sequence (2-second pixelated "build" sprite).
6. Long-press placed room → context menu: **Move**, **Sell** (50 % refund).

### 5.2 Constraints
- Rooms cannot overlap each other or outer walls.
- At least one continuous walkable corridor (BFS reachability) must remain from spawn point to all occupied desks. Placement is rejected if it would isolate any agent.
- The canonical 7 Garage stations are always off-limits for room placement (locked zone in Garage tier; visible greyed-out rectangles at higher tiers).

### 5.3 Edit grid overlay
The grid overlay renders at 50 % opacity using the existing `kTileSize = 16 px` grid. Rooms show a coloured bounding box (green outline) when placed, with a small icon in the top-left corner (matching the room type icon).

---

## 6. Data Model

### 6.1 New enum `RoomType`
```dart
enum RoomType { workstation, breakRoom, meetingRoom, serverRoom, lounge }
```

### 6.2 New class `PlacedRoom`
```dart
class PlacedRoom {
  final String id;         // uuid-like, e.g. "room_1"
  final RoomType type;
  final int col;           // top-left tile column
  final int row;           // top-left tile row
  // implicit size from RoomType
}
```

### 6.3 `GameState` additions
```dart
final List<PlacedRoom> placedRooms;
```

### 6.4 `OfficeLevel` extensions
```dart
int get gridCols => switch (this) {
  OfficeLevel.garage       => 20,
  OfficeLevel.smallOffice  => 28,
  OfficeLevel.modernOffice => 36,
  OfficeLevel.techHub      => 44,
  OfficeLevel.campus       => 52,
};

int get gridRows => switch (this) {
  OfficeLevel.garage       => 14,
  OfficeLevel.smallOffice  => 16,
  OfficeLevel.modernOffice => 20,
  OfficeLevel.techHub      => 24,
  OfficeLevel.campus       => 28,
};
```

### 6.5 `OfficeGameState` changes
- `kGridCols` / `kGridRows` constants stay as Garage defaults; `OfficeGameState` accepts an `OfficeLevel` param and uses `level.gridCols` / `level.gridRows` for the actual map.
- `_buildBlockedTiles()` also marks all `PlacedRoom` tiles that `blocksPath == true`.
- `syncHiredAgents()` treats `PlacedRoom` workstations as extra `DeskStation` entries.

### 6.6 JSON schema version bump
`schemaVersion` → 3. `GameState.decode` rejects v2 as incompatible (no migration needed for early dev).

---

## 7. Room Effects — Implementation Notes

| Effect | Where |
|---|---|
| Speed bonus (server room) | `AgentGameData.totalSpeedModifier` — add `officeSpeedModifier(GameState)` helper |
| Wander timer boost (break room) | `kWanderPauseMin/Max` overridden per-character based on proximity to `breakRoom` tiles |
| Skate-to-lounge | `_updateCharacter` idle branch: if lounge placed, wander destination biased toward lounge tiles |
| Extra workstation desk | Dynamic `DeskStation` list built from `PlacedRoom.type == workstation`; appended to `kStations` view in `syncHiredAgents` |

---

## 8. Art & Sprites

Phase 1 uses **programmatic pixel-rect drawing** (same approach as `character_accessories.dart`) — no new sprite PNGs needed. Each room type gets a `drawRoom(Canvas, PlacedRoom, RoomTheme)` function in a new `room_sprites.dart` file:

- `workstation`: desk rectangle + monitor glyph, same pixel palette as existing desks.
- `breakRoom`: two couch rects + small table, warm palette.
- `meetingRoom`: long table + chair dots around it.
- `serverRoom`: rack columns with blinking LED pixels (uses tick for blink).
- `lounge`: ramp silhouette + bean-bag circles.

Sprites can be replaced by proper PNGs later without changing the data model.

---

## 9. Implementation Phases

### Phase 1 — Startup Loft + Build Mode scaffold (this sprint)
- [ ] `RoomType` enum + `PlacedRoom` class in `game_economy.dart`
- [ ] `gridCols` / `gridRows` on `OfficeLevel`
- [ ] `placedRooms` in `GameState` (serialization, schema v3)
- [ ] `OfficeGameState` accepts `OfficeLevel` + `List<PlacedRoom>`, uses dynamic grid
- [ ] Extra workstation → dynamic `DeskStation` injection in `syncHiredAgents`
- [ ] Build Mode toggle in the canvas; ghost placement; confirm/sell
- [ ] `room_sprites.dart` — programmatic drawing for 5 room types
- [ ] Passive effects: server room speed bonus, break room wander timer

### Phase 2 — Adjacency system + morale
- [ ] Adjacency bonus/penalty engine
- [ ] Lounge skate-to-lounge wander bias
- [ ] Meeting room Manager synergy

### Phase 3 — Higher tiers + art polish
- [ ] `techHub` / `campus` grid sizes
- [ ] Replace programmatic room art with PNG sprite sheets
- [ ] Room construction animation

---

## 10. Open Questions (post-Phase 1)

1. **Sound**: should placing a room play a construction sfx, or stay silent like the rest of the game?
2. **Tutorials**: should a first-time build popup explain the mechanic, or is it self-evident?
3. **Save migration**: when we bump to v3, do we attempt to migrate v2 saves or just reset?
4. **Extra workstation naming**: should placed workstations create named desk stations (e.g. "Стіл #2") visible in agent details, or remain anonymous?
