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
    this.ghostCol,
    this.ghostRow,
    this.ghostRotation = 0,
  });

  final bool active;
  final BuildSection section;
  final RoomType? selectedRoomType;
  final int? ghostCol;
  final int? ghostRow;
  /// Room rotation in degrees: 0 / 90 / 180 / 270.
  final int ghostRotation;

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
    int? ghostCol,
    int? ghostRow,
    int? ghostRotation,
    bool clearSelectedRoom = false,
    bool clearGhost = false,
    bool resetRotation = false,
  }) =>
      BuildModeState(
        active: active ?? this.active,
        section: section ?? this.section,
        selectedRoomType: clearSelectedRoom
            ? null
            : (selectedRoomType ?? this.selectedRoomType),
        ghostCol: clearGhost ? null : (ghostCol ?? this.ghostCol),
        ghostRow: clearGhost ? null : (ghostRow ?? this.ghostRow),
        ghostRotation: resetRotation ? 0 : (ghostRotation ?? this.ghostRotation),
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
      // Switching section abandons the in-flight room pick — different
      // section, different intent.
      clearSelectedRoom: true,
      clearGhost: true,
      resetRotation: true,
    );
  }

  /// Toggle a room type — picking the same one again clears the selection.
  void toggleRoom(RoomType type) {
    if (state.selectedRoomType == type) {
      state = state.copyWith(
          clearSelectedRoom: true, clearGhost: true, resetRotation: true);
    } else {
      state = state.copyWith(
        selectedRoomType: type,
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

  /// Drop the active room pick (e.g. when entering Edit mode, where the
  /// player is removing rooms instead of placing them).
  void clearSelection() {
    state = state.copyWith(
        clearSelectedRoom: true, clearGhost: true, resetRotation: true);
  }
}

final buildModeProvider =
    NotifierProvider<BuildModeNotifier, BuildModeState>(BuildModeNotifier.new);
