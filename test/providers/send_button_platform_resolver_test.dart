import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/send_button_style.dart';
import 'package:pixelcode/providers/theme_provider.dart';

void main() {
  group('resolveSendButtonVariantForPlatform', () {
    test('swaps pixelArcade for liquidGlass on Apple platforms', () {
      expect(
        resolveSendButtonVariantForPlatform(
          SendButtonVariant.pixelArcade,
          isApplePlatformOverride: true,
        ),
        SendButtonVariant.liquidGlass,
      );
    });

    test('keeps pixelArcade on non-Apple platforms', () {
      expect(
        resolveSendButtonVariantForPlatform(
          SendButtonVariant.pixelArcade,
          isApplePlatformOverride: false,
        ),
        SendButtonVariant.pixelArcade,
      );
    });

    test('passes other variants through untouched on Apple', () {
      for (final variant in [
        SendButtonVariant.classic,
        SendButtonVariant.neonPulse,
        SendButtonVariant.goldRocket,
        SendButtonVariant.liquidGlass,
      ]) {
        expect(
          resolveSendButtonVariantForPlatform(
            variant,
            isApplePlatformOverride: true,
          ),
          variant,
        );
      }
    });

    test('passes other variants through untouched on non-Apple', () {
      for (final variant in [
        SendButtonVariant.classic,
        SendButtonVariant.neonPulse,
        SendButtonVariant.goldRocket,
      ]) {
        expect(
          resolveSendButtonVariantForPlatform(
            variant,
            isApplePlatformOverride: false,
          ),
          variant,
        );
      }
    });
  });
}
