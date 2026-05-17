import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/send_button_style.dart';

void main() {
  group('sendButtonVariantForId', () {
    test('maps each catalog ID to its variant', () {
      expect(sendButtonVariantForId('send_classic'), SendButtonVariant.classic);
      expect(sendButtonVariantForId('send_neon_pulse'),
          SendButtonVariant.neonPulse);
      expect(sendButtonVariantForId('send_gold_rocket'),
          SendButtonVariant.goldRocket);
      expect(sendButtonVariantForId('send_pixel_arcade'),
          SendButtonVariant.pixelArcade);
      expect(sendButtonVariantForId('send_liquid_glass'),
          SendButtonVariant.liquidGlass);
      expect(sendButtonVariantForId('send_cloud_drift'),
          SendButtonVariant.cloudDrift);
    });

    test('falls back to classic for unknown or null IDs', () {
      expect(sendButtonVariantForId(null), SendButtonVariant.classic);
      expect(sendButtonVariantForId(''), SendButtonVariant.classic);
      expect(sendButtonVariantForId('send_does_not_exist'),
          SendButtonVariant.classic);
    });
  });

  group('cosmeticCatalog send-button entries', () {
    test('exposes pixel arcade and liquid glass as separate items', () {
      final ids = cosmeticCatalog
          .where((c) => c.type == CosmeticType.sendButtonStyle)
          .map((c) => c.id)
          .toSet();
      expect(ids, containsAll(<String>{
        'send_classic',
        'send_neon_pulse',
        'send_gold_rocket',
        'send_pixel_arcade',
        'send_liquid_glass',
        'send_cloud_drift',
      }));
    });
  });
}
