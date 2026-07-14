import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/widgets/canvas/agent_canvas.dart';

void main() {
  group('buildModeCursor', () {
    test('defers when build mode is inactive', () {
      expect(
        buildModeCursor(
          buildActive: false,
          hasGhost: false,
          ghostValid: false,
          isGrabbing: false,
        ),
        MouseCursor.defer,
      );
    });

    test('grab when build active, empty-handed, idle', () {
      expect(
        buildModeCursor(
          buildActive: true,
          hasGhost: false,
          ghostValid: false,
          isGrabbing: false,
        ),
        SystemMouseCursors.grab,
      );
    });

    test('grabbing when build active, empty-handed, pointer down', () {
      expect(
        buildModeCursor(
          buildActive: true,
          hasGhost: false,
          ghostValid: false,
          isGrabbing: true,
        ),
        SystemMouseCursors.grabbing,
      );
    });

    test('cell when ghost is over a valid tile', () {
      expect(
        buildModeCursor(
          buildActive: true,
          hasGhost: true,
          ghostValid: true,
          isGrabbing: false,
        ),
        SystemMouseCursors.cell,
      );
    });

    test('forbidden when ghost overlaps or fails a bounds/cap guard', () {
      expect(
        buildModeCursor(
          buildActive: true,
          hasGhost: true,
          ghostValid: false,
          isGrabbing: false,
        ),
        SystemMouseCursors.forbidden,
      );
    });

    test('grab survives stray isGrabbing flag when ghost is in hand', () {
      // Defensive: a leftover _isGrabbing flag must never override the
      // ghost-validity cursor — otherwise the player sees "grab" over an
      // invalid drop and thinks the tap will succeed.
      expect(
        buildModeCursor(
          buildActive: true,
          hasGhost: true,
          ghostValid: true,
          isGrabbing: true,
        ),
        SystemMouseCursors.cell,
      );
    });
  });
}
