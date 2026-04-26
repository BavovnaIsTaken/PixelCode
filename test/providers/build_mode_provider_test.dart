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

  // ─── Rotation ────────────────────────────────────────────────────────────

  test('ghostRotation starts at 0', () {
    c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom);
    expect(c.read(buildModeProvider).ghostRotation, 0);
  });

  test('rotateClockwise increments by 90° and wraps at 360', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom);

    n.rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 90);
    n.rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 180);
    n.rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 270);
    n.rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 0);
  });

  test('rotateCounterClockwise decrements by 90° and wraps', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom);

    n.rotateCounterClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 270);
    n.rotateCounterClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 180);
  });

  test('ghostWidth/ghostHeight swap axes at 90° and 270° for non-square room', () {
    // meetingRoom is 3 wide × 2 tall
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom);

    var s = c.read(buildModeProvider);
    expect(s.ghostWidth, 3);
    expect(s.ghostHeight, 2);

    n.rotateClockwise(); // 90°
    s = c.read(buildModeProvider);
    expect(s.ghostWidth, 2);
    expect(s.ghostHeight, 3);

    n.rotateClockwise(); // 180°
    s = c.read(buildModeProvider);
    expect(s.ghostWidth, 3);
    expect(s.ghostHeight, 2);

    n.rotateClockwise(); // 270°
    s = c.read(buildModeProvider);
    expect(s.ghostWidth, 2);
    expect(s.ghostHeight, 3);
  });

  test('toggleRoom resets rotation to 0', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom)
      ..rotateClockwise()
      ..rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 180);

    // Switching to another room resets rotation.
    n.toggleRoom(RoomType.workstation);
    expect(c.read(buildModeProvider).ghostRotation, 0);
  });

  test('setSection resets rotation to 0', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom)
      ..rotateClockwise();
    expect(c.read(buildModeProvider).ghostRotation, 90);

    n.setSection(BuildSection.decor);
    expect(c.read(buildModeProvider).ghostRotation, 0);
  });

  test('clearSelection resets rotation to 0', () {
    final n = c.read(buildModeProvider.notifier)
      ..enter()
      ..toggleRoom(RoomType.meetingRoom)
      ..rotateClockwise();

    n.clearSelection();
    expect(c.read(buildModeProvider).ghostRotation, 0);
  });

  // ─── Templates ───────────────────────────────────────────────────────────

  test('toggleTemplate sets template id and base room', () {
    final n = c.read(buildModeProvider.notifier)..enter();
    final tpl = roomTemplateCatalog.first;

    n.toggleTemplate(tpl);
    final s = c.read(buildModeProvider);
    expect(s.selectedTemplateId, tpl.id);
    expect(s.selectedRoomType, tpl.baseRoom);
  });

  test('toggleTemplate twice clears the selection', () {
    final n = c.read(buildModeProvider.notifier)..enter();
    final tpl = roomTemplateCatalog.first;

    n.toggleTemplate(tpl);
    n.toggleTemplate(tpl);
    final s = c.read(buildModeProvider);
    expect(s.selectedTemplateId, isNull);
    expect(s.selectedRoomType, isNull);
  });

  test('toggleRoom clears any active template — exclusive intents', () {
    final n = c.read(buildModeProvider.notifier)..enter();
    final tpl = roomTemplateCatalog
        .firstWhere((t) => t.baseRoom == RoomType.workstation);

    n.toggleTemplate(tpl);
    n.toggleRoom(RoomType.serverRoom);
    final s = c.read(buildModeProvider);
    expect(s.selectedTemplateId, isNull);
    expect(s.selectedRoomType, RoomType.serverRoom);
  });

  test('setSection clears any active template', () {
    final n = c.read(buildModeProvider.notifier)..enter();
    n.toggleTemplate(roomTemplateCatalog.first);

    n.setSection(BuildSection.decor);
    expect(c.read(buildModeProvider).selectedTemplateId, isNull);
  });
}
