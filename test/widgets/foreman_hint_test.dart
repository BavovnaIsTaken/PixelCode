import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/widgets/canvas/foreman_overlay_painter.dart';

void main() {
  group('pickForemanHint priority', () {
    test('hover wins over everything else', () {
      expect(
        pickForemanHint(
          hovering: true,
          firstTimePrompt: true,
          attention: true,
        ),
        ForemanHint.hover,
      );
    });

    test('onboarding chevron beats affordability bubble', () {
      expect(
        pickForemanHint(
          hovering: false,
          firstTimePrompt: true,
          attention: true,
        ),
        ForemanHint.onboarding,
      );
    });

    test('attention bubble shows when no higher-priority hint is active', () {
      expect(
        pickForemanHint(
          hovering: false,
          firstTimePrompt: false,
          attention: true,
        ),
        ForemanHint.attention,
      );
    });

    test('none when all signals are off', () {
      expect(
        pickForemanHint(
          hovering: false,
          firstTimePrompt: false,
          attention: false,
        ),
        ForemanHint.none,
      );
    });

    test('hover beats onboarding even without affordability', () {
      // Pointer is over the foreman during a player\'s very first session —
      // surface the live tooltip, not the redundant chevron.
      expect(
        pickForemanHint(
          hovering: true,
          firstTimePrompt: true,
          attention: false,
        ),
        ForemanHint.hover,
      );
    });
  });
}
