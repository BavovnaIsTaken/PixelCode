import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/widgets/canvas/agent_canvas.dart';

void main() {
  group('ghostInvalidReasonLabel', () {
    test('falls back to generic label when reason is null', () {
      expect(ghostInvalidReasonLabel(null), 'не вміщується');
    });

    test('outOfBounds → за межами офісу', () {
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.outOfBounds),
        'за межами офісу',
      );
    });

    test('overlap → перекриває кімнату', () {
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.overlap),
        'перекриває кімнату',
      );
    });

    test('blocked → на меблях чи персоналі', () {
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.blocked),
        'на меблях чи персоналі',
      );
    });

    test('tierCeiling label tells the player to upgrade', () {
      // The actionable detail — without this hint the player thinks the editor
      // is broken when they hit the tier cap; the only fix is buying a tier
      // upgrade in the shop, which has no surface from inside Build Mode.
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.tierCeiling),
        'потрібен апгрейд офісу',
      );
    });

    test('bufferOverrun label tells the player to drag closer', () {
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.bufferOverrun),
        'занадто далеко — підсуньте ближче',
      );
    });

    test('insufficientGrymni → не вистачає ₲', () {
      expect(
        ghostInvalidReasonLabel(GhostInvalidReason.insufficientGrymni),
        'не вистачає ₲',
      );
    });

    test('every enum value has a non-empty label', () {
      // Future-proofing: if someone adds a new reason and forgets to handle it
      // in the switch, the test surfaces the gap before it reaches users.
      for (final reason in GhostInvalidReason.values) {
        final label = ghostInvalidReasonLabel(reason);
        expect(label, isNotEmpty,
            reason: 'GhostInvalidReason.$reason has empty label');
        expect(label, isNot('не вміщується'),
            reason:
                'GhostInvalidReason.$reason fell through to generic fallback');
      }
    });
  });
}
