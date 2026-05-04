import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/send_button_style.dart';

void main() {
  group('sendButtonVariantForId', () {
    test('resolves known cosmetic IDs to their variants', () {
      expect(sendButtonVariantForId('send_neon_pulse'),
          SendButtonVariant.neonPulse);
      expect(sendButtonVariantForId('send_gold_rocket'),
          SendButtonVariant.goldRocket);
      expect(sendButtonVariantForId('send_pixel_arcade'),
          SendButtonVariant.pixelArcade);
    });

    test('falls back to classic for null', () {
      expect(sendButtonVariantForId(null), SendButtonVariant.classic);
    });

    test('falls back to classic for empty string', () {
      expect(sendButtonVariantForId(''), SendButtonVariant.classic);
    });

    test('falls back to classic for unknown id', () {
      expect(sendButtonVariantForId('send_unknown_glory'),
          SendButtonVariant.classic);
      expect(sendButtonVariantForId('classic'), SendButtonVariant.classic);
    });
  });

  group('SendButtonVariant enum', () {
    test('exposes all four expected variants', () {
      expect(SendButtonVariant.values.length, 4);
      expect(SendButtonVariant.values, containsAll(<SendButtonVariant>[
        SendButtonVariant.classic,
        SendButtonVariant.neonPulse,
        SendButtonVariant.goldRocket,
        SendButtonVariant.pixelArcade,
      ]));
    });

    test('classic is the first (default) variant', () {
      expect(SendButtonVariant.values.first, SendButtonVariant.classic);
    });
  });
}
