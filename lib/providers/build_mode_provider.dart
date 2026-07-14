/// Build Mode state lifted out of `AgentCanvas` so the hub can mount the
/// menu wherever the layout calls for it (desktop replaces the chat panel,
/// mobile keeps a bottom sheet over the canvas) without the canvas owning
/// the source of truth.
///
/// Holds: whether build mode is active, the selected section, the picked
/// room type, and the current ghost tile coordinates. Placement itself
/// still lives in `gameEconomyProvider` — this notifier only tracks UI
/// intent up to the moment of commit.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_economy.dart';
import '../widgets/canvas/build_menu.dart';

class BuildModeState {
  const BuildModeState({
    this.active = false,
    this.section = BuildSection.rooms,
    this.selectedRoomType,
    this.selectedTemplateId,
    this.selectedPlacedRoomId,
    this.ghostCol,
    this.ghostRow,
    this.ghostRotation = 0,
    this.corridorWide = false,
    this.corridorAnchorCol,
    this.corridorAnchorRow,
  });

  final bool active;
  final BuildSection section;
  final RoomType? selectedRoomType;

  /// When non-null, the player picked a room template (Stage 2). The base
  /// room type still flows through [selectedRoomType] for ghost preview
  /// dimensions; this id tells `placeRoomTemplate` which furniture bundle
  /// to drop in alongside the room.
  final String? selectedTemplateId;

  /// The id of a [PlacedRoom] the player has selected in Walls/Floors section
  /// for per-room skin assignment.
  final String? selectedPlacedRoomId;

  final int? ghostCol;
  final int? ghostRow;
  /// Room rotation in degrees: 0 / 90 / 180 / 270.
  final int ghostRotation;

  /// Whether the corridor being drawn is the 2-tile-wide variant (₲90/tile).
  final bool corridorWide;

  /// First clicked tile when drawing a corridor — null until first tap in
  /// Corridors section.
  final int? corridorAnchorCol;
  final int? corridorAnchorRow;

  /// Footprint width after rotation.
  int get ghostWidth => (ghostRotation == 90 || ghostRotation == 270)
      ? (selectedRoomType?.heightTiles ?? 0)
      : (selectedRoomType?.widthTiles ?? 0);

  /// Footprint height after rotation.
  int get ghostHeight => (ghostRotation == 90 || ghostRotation == 270)
      ? (selectedRoomType?.widthTiles ?? 0)
      : (selectedRoomType?.heightTiles ?? 0);

  BuildModeState copyWith({
    bool? active,
    BuildSection? section,
    RoomType? selectedRoomType,
    String? selectedTemplateId,
    String? selectedPlacedRoomId,
    int? ghostCol,
    int? ghostRow,
    int? ghostRotation,
    bool? corridorWide,
    int? corridorAnchorCol,
    int? corridorAnchorRow,
    bool clearSelectedRoom = false,
    bool clearTemplate = false,
    bool clearPlacedRoom = false,
    bool clearGhost = false,
    bool resetRotation = false,
    bool clearCorridorAnchor = false,
  }) =>
      BuildModeState(
        active: active ?? this.active,
        section: section ?? this.section,
        selectedRoomType: clearSelectedRoom
            ? null
            : (selectedRoomType ?? this.selectedRoomType),
        selectedTemplateId: clearTemplate
            ? null
            : (selectedTemplateId ?? this.selectedTemplateId),
        selectedPlacedRoomId: clearPlacedRoom
            ? null
            : (selectedPlacedRoomId ?? this.selectedPlacedRoomId),
        ghostCol: clearGhost ? null : (ghostCol ?? this.ghostCol),
        ghostRow: clearGhost ? null : (ghostRow ?? this.ghostRow),
        ghostRotation: resetRotation ? 0 : (ghostRotation ?? this.ghostRotation),
        corridorWide: corridorWide ?? this.corridorWide,
        corridorAnchorCol: clearCorridorAnchor
            ? null
            : (corridorAnchorCol ?? this.corridorAnchorCol),
        corridorAnchorRow: clearCorridorAnchor
            ? null
            : (corridorAnchorRow ?? this.corridorAnchorRow),
      );
}

class BuildModeNotifier extends Notifier<BuildModeState> {
  @override
  BuildModeState build() => const BuildModeState();

  /// Open Build Mode and reset transient pickers so prior session state
  /// doesn't bleed in.
  void enter() {
    state = const BuildModeState(
      active: true,
      section: BuildSection.rooms,
    );
  }

  /// Leave Build Mode and clear all transient state (ghost, selection).
  void exit() {
    state = const BuildModeState();
  }

  void setSection(BuildSection section) {
    state = state.copyWith(
      section: section,
      clearSelectedRoom: true,
      clearTemplate: true,
      clearPlacedRoom: true,
      clearGhost: true,
      resetRotation: true,
      clearCorridorAnchor: true,
    );
  }

  /// Select an already-placed room for skin assignment (Walls/Floors section).
  void selectPlacedRoom(String roomId) {
    state = state.copyWith(selectedPlacedRoomId: roomId);
  }

  /// Deselect the placed room (e.g. when switching away from Walls/Floors).
  void clearPlacedRoomSelection() {
    state = state.copyWith(clearPlacedRoom: true);
  }

  void toggleCorridorWide() {
    state = state.copyWith(corridorWide: !state.corridorWide);
  }

  /// Set the first tile of the corridor being drawn.
  void setCorridorAnchor(int col, int row) {
    state = state.copyWith(corridorAnchorCol: col, corridorAnchorRow: row);
  }

  void clearCorridorAnchor() {
    state = state.copyWith(clearCorridorAnchor: true, clearGhost: true);
  }

  /// Toggle a room type — picking the same one again clears the selection.
  /// Always clears any template pick: rooms and templates are mutually
  /// exclusive intents.
  void toggleRoom(RoomType type) {
    if (state.selectedRoomType == type && state.selectedTemplateId == null) {
      state = state.copyWith(
          clearSelectedRoom: true, clearGhost: true, resetRotation: true);
    } else {
      state = state.copyWith(
        selectedRoomType: type,
        clearTemplate: true,
        clearGhost: true,
        resetRotation: true,
      );
    }
  }

  /// Toggle a template pick — re-tap clears the selection. The ghost preview
  /// reuses [selectedRoomType] for its footprint, set here from the
  /// template's base room.
  void toggleTemplate(RoomTemplate template) {
    if (state.selectedTemplateId == template.id) {
      state = state.copyWith(
        clearSelectedRoom: true,
        clearTemplate: true,
        clearGhost: true,
        resetRotation: true,
      );
    } else {
      state = state.copyWith(
        selectedRoomType: template.baseRoom,
        selectedTemplateId: template.id,
        clearGhost: true,
        resetRotation: true,
      );
    }
  }

  void setGhost({required int col, required int row}) {
    state = state.copyWith(ghostCol: col, ghostRow: row);
  }

  void clearGhost() {
    state = state.copyWith(clearGhost: true);
  }

  void rotateClockwise() {
    state = state.copyWith(
        ghostRotation: (state.ghostRotation + 90) % 360, clearGhost: true);
  }

  void rotateCounterClockwise() {
    state = state.copyWith(
        ghostRotation: (state.ghostRotation + 270) % 360, clearGhost: true);
  }

  /// Drop the active room/template pick (e.g. when entering Edit mode,
  /// where the player is removing rooms instead of placing them). Also clears
  /// any half-drawn corridor anchor so Esc / Cancel reliably resets every
  /// transient placement state and the player can never get stuck mid-draw.
  void clearSelection() {
    state = state.copyWith(
        clearSelectedRoom: true,
        clearTemplate: true,
        clearPlacedRoom: true,
        clearGhost: true,
        clearCorridorAnchor: true,
        resetRotation: true);
  }
}

final buildModeProvider =
    NotifierProvider<BuildModeNotifier, BuildModeState>(BuildModeNotifier.new);
