import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/build_mode_provider.dart';
import 'package:pixelcode/widgets/canvas/build_menu.dart';

void main() {
  late ProviderContainer c;

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('starts inactive with default rooms section', () {
    final s = c.read(buildModeProvider);
    expect(s.active, isFalse);
    expect(s.section, BuildSection.rooms);
    expect(s.selectedRoomType, isNull);
    expect(s.ghostCol, isNull);
    expect(s.ghostRow, isNull);
  });

  test('enter activates and resets to rooms section', () {
    c.read(buildModeProvider.notifier)
      ..setSection(BuildSection.decor)
      ..setGhost(col: 3, row: 4);
    expect(c.read(buildModeProvider).section, BuildSection.decor);

    c.read(buildModeProvider.notifier).enter();
    final s = c.read(buildModeProvider);
    expect(s.active, isTrue);
    expect(s.section, BuildSection.rooms);
    expect(s.ghostCol, isNull);
  });

  test('exit clears all transient state', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.workstation)
      ..setGhost(col: 5, row: 6);
    expect(c.read(buildModeProvider).active, isTrue);

    n.exit();
    final s = c.read(buildModeProvider);
    expect(s.active, isFalse);
    expect(s.selectedRoomType, isNull);
    expect(s.ghostCol, isNull);
    expect(s.ghostRow, isNull);
  });

  test('toggleRoom selects, then deselects on repeat', () {
    final n = c.read(buildModeProvider.notifier)..enter();

    n.toggleRoom(RoomType.workstation);
    expect(c.read(buildModeProvider).selectedRoomType, RoomType.workstation);

    n.toggleRoom(RoomType.workstation);
    expect(c.read(buildModeProvider).selectedRoomType, isNull);
  });

  test('toggleRoom switches selection without intermediate clear', () {
    final n = c.read(buildModeProvider.notifier)..enter();

    n.toggleRoom(RoomType.workstation);
    n.toggleRoom(RoomType.serverRoom);
    expect(c.read(buildModeProvider).selectedRoomType, RoomType.serverRoom);
  });

  test('setSection drops in-flight room pick — different section, '
      'different intent', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.workstation)
      ..setGhost(col: 2, row: 3);

    n.setSection(BuildSection.decor);
    final s = c.read(buildModeProvider);
    expect(s.section, BuildSection.decor);
    expect(s.selectedRoomType, isNull);
    expect(s.ghostCol, isNull);
  });

  test('clearSelection empties room + ghost without leaving build mode', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom)
      ..setGhost(col: 1, row: 1);

    n.clearSelection();
    final s = c.read(buildModeProvider);
    expect(s.active, isTrue);
    expect(s.selectedRoomType, isNull);
    expect(s.ghostCol, isNull);
  });
}
