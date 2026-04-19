/// Visual variants for the chat "send" button cosmetic.
///
/// Each variant is a hand-crafted design rendered by [SendButton] in
/// `widgets/chat/chat_panel.dart`. The enum is mapped from a cosmetic ID
/// stored in [GameState.equippedCosmetics]; unknown or missing IDs fall
/// back to [SendButtonVariant.classic].
library;

enum SendButtonVariant {
  /// Default — solid accent square with the theme's accent colour.
  classic,

  /// Dark core with pulsing neon ring; glow breathes independently of
  /// the theme. Premium.
  neonPulse,

  /// Metallic gold with beveled edges and a shimmer sweep on hover.
  /// Premium.
  goldRocket,

  /// 8-bit arcade-style hard drop shadow; depresses into the shadow on
  /// tap like a physical button. Premium.
  pixelArcade,
}

/// Resolve a cosmetic ID to its [SendButtonVariant].
SendButtonVariant sendButtonVariantForId(String? cosmeticId) =>
    switch (cosmeticId) {
      'send_neon_pulse' => SendButtonVariant.neonPulse,
      'send_gold_rocket' => SendButtonVariant.goldRocket,
      'send_pixel_arcade' => SendButtonVariant.pixelArcade,
      _ => SendButtonVariant.classic,
    };
