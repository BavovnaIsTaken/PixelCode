/// Lightweight deep-link provider for navigating to a specific shop tab.
///
/// Set [shopDeepLinkProvider] to a tab index to:
///   1. Switch HubScreen to the Shop view.
///   2. Animate ShopPanel to that tab.
/// Both consumers clear the state after acting on it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indices in ShopPanel. Furniture tab was migrated to BuildMenu's
/// Decor section in Stage 2 of the Build System rework — its index is gone.
const shopTabOffice = 2;
const shopTabDonation = 4;

/// When non-null, consumers should navigate to the given shop tab index
/// and then reset this back to null.
final shopDeepLinkProvider = StateProvider<int?>((ref) => null);

/// Whether the furniture grid editor overlay is active.
final furnitureEditModeProvider = StateProvider<bool>((ref) => false);

/// The furniture item ID currently selected for placement (null = none).
final selectedFurnitureIdProvider = StateProvider<String?>((ref) => null);
