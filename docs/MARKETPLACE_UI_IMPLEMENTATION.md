# Marketplace UI Implementation Guide

## Overview
The marketplace is currently **backend-only** (Phase 4 server tests passed). This document specifies how to implement the Flutter UI widgets needed for Phase 4 UI testing.

---

## Current State

### ✅ What Exists
- **Server models** (TypeScript): `CommissionTx`, `AgentListing`, `MarketplaceReview` (tested)
- **Server APIs**: marketplace endpoints for listing, filtering, purchasing (mocked in tests)
- **Flutter models**: `AgentGameData` (individual agents the player owns)
- **Shop panel**: `lib/widgets/shop/shop_panel.dart` (hiring, skills, upgrades)

### ❌ What's Missing
```
lib/models/
  ├── agent_listing.dart          ← NEW (Agent metadata for marketplace)
  └── marketplace_review.dart      ← NEW (Ratings/reviews)

lib/widgets/marketplace/          ← NEW DIRECTORY
  ├── marketplace_catalog.dart     ← Main grid view
  ├── listing_detail.dart          ← Detail screen
  ├── listing_tile.dart            ← Grid item widget
  ├── purchase_dialog.dart         ← Confirmation dialog
  ├── listing_filter_bar.dart      ← Filters + search
  ├── rating_display.dart          ← Star rating widget
  └── seller_analytics.dart        ← Seller dashboard

lib/services/
  └── marketplace_service.dart     ← API client (calls server)

test/mocks/
  └── mock_marketplace_service.dart ← Test doubles
```

---

## Step 1: Create Data Models

### File: `lib/models/agent_listing.dart`

This is the Dart representation of the server's `AgentListing`.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_listing.freezed.dart';
part 'agent_listing.g.dart';

@freezed
class AgentListing with _$AgentListing {
  const factory AgentListing({
    required String listingId,
    required String agentId,
    required String sellerName,        // account/player name
    required String agentName,         // agent nickname
    required String role,              // "coder", "tester", etc.
    required int priceGrim,            // cost in Grim currency
    required double qualityScore,      // 0-100, from quality evaluation
    required double averageRating,     // 1-5 stars (0 if no reviews)
    required int reviewCount,
    required int purchaseCount,
    required String description,
    required List<int> skillSpecializations, // [0, 2, 4]
    required DateTime createdAt,
    required DateTime? updatedAt,
  }) = _AgentListing;

  factory AgentListing.fromJson(Map<String, dynamic> json) =>
      _$AgentListingFromJson(json);
}

@freezed
class MarketplaceReview with _$MarketplaceReview {
  const factory MarketplaceReview({
    required String reviewId,
    required String listingId,
    required String buyerName,         // masked/anonymized
    required int rating,               // 1-5
    required String comment,
    required DateTime createdAt,
  }) = _MarketplaceReview;

  factory MarketplaceReview.fromJson(Map<String, dynamic> json) =>
      _$MarketplaceReviewFromJson(json);
}
```

---

## Step 2: Create API Service

### File: `lib/services/marketplace_service.dart`

This talks to the server backend (or mock during development).

```dart
import 'package:flutter/foundation.dart';
import '../models/agent_listing.dart';

abstract class MarketplaceService {
  /// Get all listings with optional filters
  Future<List<AgentListing>> getListings({
    String? roleFilter,
    double? minRating,
    String? searchQuery,
  });

  /// Get a specific listing
  Future<AgentListing?> getListing(String listingId);

  /// Purchase an agent (deducts from player balance)
  Future<PurchaseResult> purchaseAgent(
    String listingId,
    String buyerId,
    int paymentGrim,
  );

  /// Get reviews for a listing
  Future<List<MarketplaceReview>> getReviews(String listingId);

  /// Submit a review (after purchase)
  Future<ReviewResult> submitReview(
    String listingId,
    String buyerId,
    int rating,
    String comment,
  );

  /// Get seller's listings (if logged in)
  Future<List<AgentListing>> getMyListings();

  /// Get seller stats
  Future<SellerStats> getSellerStats();
}

class PurchaseResult {
  final bool success;
  final String? error;
  final String? transactionId;

  PurchaseResult({
    required this.success,
    this.error,
    this.transactionId,
  });
}

class ReviewResult {
  final bool success;
  final String? error;

  ReviewResult({required this.success, this.error});
}

class SellerStats {
  final int totalListings;
  final int totalSales;
  final int totalRevenue;
  final double avgRating;

  SellerStats({
    required this.totalListings,
    required this.totalSales,
    required this.totalRevenue,
    required this.avgRating,
  });
}
```

### Implement with HTTP client (or stub)

```dart
class HttpMarketplaceService implements MarketplaceService {
  final String baseUrl;

  HttpMarketplaceService({required this.baseUrl});

  @override
  Future<List<AgentListing>> getListings({
    String? roleFilter,
    double? minRating,
    String? searchQuery,
  }) async {
    final params = <String, String>{
      if (roleFilter != null) 'role': roleFilter,
      if (minRating != null) 'minRating': minRating.toString(),
      if (searchQuery != null) 'search': searchQuery,
    };

    final uri = Uri.parse('$baseUrl/marketplace/listings').replace(
      queryParameters: params.isNotEmpty ? params : null,
    );

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as List;
      return json
          .map((e) => AgentListing.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load listings: ${response.body}');
  }

  // ... implement other methods similarly
}
```

---

## Step 3: Create Riverpod Providers

### File: `lib/providers/marketplace_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_listing.dart';
import '../services/marketplace_service.dart';

// Mock for development (real implementation uses HttpMarketplaceService)
final marketplaceServiceProvider = Provider<MarketplaceService>((ref) {
  return MockMarketplaceService(); // swap to HttpMarketplaceService later
});

// Filter state
class MarketplaceFilter {
  final String? roleFilter;
  final double? minRating;
  final String? searchQuery;

  MarketplaceFilter({
    this.roleFilter,
    this.minRating,
    this.searchQuery,
  });

  MarketplaceFilter copyWith({
    String? roleFilter,
    double? minRating,
    String? searchQuery,
  }) =>
      MarketplaceFilter(
        roleFilter: roleFilter ?? this.roleFilter,
        minRating: minRating ?? this.minRating,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

final marketplaceFilterProvider =
    StateProvider<MarketplaceFilter>((ref) => MarketplaceFilter());

// Listings fetcher
final marketplaceListingsProvider = FutureProvider<List<AgentListing>>((ref) {
  final service = ref.watch(marketplaceServiceProvider);
  final filter = ref.watch(marketplaceFilterProvider);

  return service.getListings(
    roleFilter: filter.roleFilter,
    minRating: filter.minRating,
    searchQuery: filter.searchQuery,
  );
});

// Current selected listing
final selectedListingProvider = StateProvider<AgentListing?>((ref) => null);

// Listing reviews
final listingReviewsProvider =
    FutureProvider.family<List<MarketplaceReview>, String>((ref, listingId) {
  final service = ref.watch(marketplaceServiceProvider);
  return service.getReviews(listingId);
});
```

---

## Step 4: Create UI Widgets

### File: `lib/widgets/marketplace/marketplace_catalog.dart`

Main grid view with filtering.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_listing.dart';
import '../../providers/marketplace_provider.dart';
import 'listing_tile.dart';
import 'listing_filter_bar.dart';

class MarketplaceCatalog extends ConsumerWidget {
  const MarketplaceCatalog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final filter = ref.watch(marketplaceFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter bar at top
          ListingFilterBar(
            onRoleChanged: (role) {
              ref.read(marketplaceFilterProvider.notifier).state =
                  filter.copyWith(roleFilter: role);
            },
            onRatingChanged: (rating) {
              ref.read(marketplaceFilterProvider.notifier).state =
                  filter.copyWith(minRating: rating);
            },
            onSearchChanged: (query) {
              ref.read(marketplaceFilterProvider.notifier).state =
                  filter.copyWith(searchQuery: query);
            },
          ),
          // Grid of listings
          Expanded(
            child: listingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (listings) {
                if (listings.isEmpty) {
                  return const Center(
                    child: Text('No custom agents available yet'),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: listings.length,
                  itemBuilder: (context, index) {
                    final listing = listings[index];
                    return ListingTile(listing: listing);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### File: `lib/widgets/marketplace/listing_tile.dart`

Individual grid item.

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/agent_listing.dart';
import 'rating_display.dart';

class ListingTile extends StatelessWidget {
  final AgentListing listing;

  const ListingTile({required this.listing, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/marketplace/listing/${listing.listingId}');
      },
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail / avatar
            Container(
              height: 100,
              color: Colors.grey[800],
              child: Center(
                child: Text(
                  listing.agentName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.agentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    listing.role,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 4),
                  RatingDisplay(
                    rating: listing.averageRating,
                    count: listing.reviewCount,
                  ),
                  const Spacer(),
                  Text(
                    '${listing.priceGrim} ₲',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### File: `lib/widgets/marketplace/listing_detail.dart`

Full detail screen.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_listing.dart';
import '../../providers/marketplace_provider.dart';
import 'rating_display.dart';
import 'purchase_dialog.dart';

class ListingDetail extends ConsumerWidget {
  final String listingId;

  const ListingDetail({required this.listingId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch the listing (you'd add a specific provider for this)
    // For now, assume it's passed via navigation state

    return Scaffold(
      appBar: AppBar(title: const Text('Agent Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: name, role, price
            Text('Agent Name', style: Theme.of(context).textTheme.headlineMedium),
            Text('Role: Coder', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),

            // Stats
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[700]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level: 5'),
                      Text('Quality: 85/100'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sales: 50'),
                      RatingDisplay(rating: 4.8, count: 25),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Description
            Text('About',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('Specialized in debugging and optimization...'),
            const SizedBox(height: 24),

            // Reviews section
            Text('Reviews (25)',
                style: Theme.of(context).textTheme.titleMedium),
            // TODO: List reviews
            const SizedBox(height: 24),

            // Author section
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sold by: alice'),
                  const Text('Total sales: 12'),
                  const Text('Member since: Apr 2026'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => const PurchaseDialog(
              agentName: 'CodeMaster',
              price: 500,
            ),
          );
        },
        label: const Text('Buy Agent'),
        icon: const Icon(Icons.shopping_cart),
      ),
    );
  }
}
```

### File: `lib/widgets/marketplace/purchase_dialog.dart`

Purchase confirmation.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/marketplace_provider.dart';

class PurchaseDialog extends ConsumerStatefulWidget {
  final String agentName;
  final int price;

  const PurchaseDialog({
    required this.agentName,
    required this.price,
    super.key,
  });

  @override
  ConsumerState<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends ConsumerState<PurchaseDialog> {
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final commission = (widget.price * 0.2).toInt();
    final sellerEarns = widget.price - commission;

    return AlertDialog(
      title: const Text('Purchase Agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Purchase "${widget.agentName}" for ${widget.price} ₲?'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[900],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Agent price:'),
                    Text('${widget.price} ₲'),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Platform commission:'),
                    Text('-$commission ₲'),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Seller receives:'),
                    Text('$sellerEarns ₲'),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red[400]),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handlePurchase,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm Purchase'),
        ),
      ],
    );
  }

  Future<void> _handlePurchase() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // TODO: Call marketplace service to purchase
      // final result = await service.purchaseAgent(...);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent purchased successfully!')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Purchase failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
```

### File: `lib/widgets/marketplace/rating_display.dart`

Star rating widget (reusable).

```dart
import 'package:flutter/material.dart';

class RatingDisplay extends StatelessWidget {
  final double rating; // 0-5
  final int count;

  const RatingDisplay({
    required this.rating,
    required this.count,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating % 1) > 0.5;

    return Row(
      children: [
        // Stars
        ...List.generate(5, (i) {
          if (i < fullStars) {
            return const Icon(Icons.star, size: 14, color: Colors.amber);
          } else if (i == fullStars && hasHalfStar) {
            return const Icon(Icons.star_half, size: 14, color: Colors.amber);
          } else {
            return const Icon(Icons.star_border, size: 14, color: Colors.grey);
          }
        }),
        const SizedBox(width: 4),
        // Rating text
        Text(
          '$rating ($count)',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
```

### File: `lib/widgets/marketplace/listing_filter_bar.dart`

Filter controls.

```dart
import 'package:flutter/material.dart';

class ListingFilterBar extends StatefulWidget {
  final Function(String?) onRoleChanged;
  final Function(double?) onRatingChanged;
  final Function(String) onSearchChanged;

  const ListingFilterBar({
    required this.onRoleChanged,
    required this.onRatingChanged,
    required this.onSearchChanged,
    super.key,
  });

  @override
  State<ListingFilterBar> createState() => _ListingFilterBarState();
}

class _ListingFilterBarState extends State<ListingFilterBar> {
  String? _selectedRole;
  double? _minRating = 0;
  final _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search agents...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 12),
          // Filters row
          Row(
            children: [
              // Role filter
              Expanded(
                child: DropdownButton<String?>(
                  value: _selectedRole,
                  isExpanded: true,
                  items: [null, 'coder', 'tester', 'devops', 'architect']
                      .map((role) => DropdownMenuItem(
                            value: role,
                            child: Text(role ?? 'All Roles'),
                          ))
                      .toList(),
                  onChanged: (role) {
                    setState(() => _selectedRole = role);
                    widget.onRoleChanged(role);
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Rating filter
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Min rating: ${_minRating?.toStringAsFixed(1) ?? '0'}'),
                    Slider(
                      value: _minRating ?? 0,
                      min: 0,
                      max: 5,
                      divisions: 10,
                      onChanged: (val) {
                        setState(() => _minRating = val);
                        widget.onRatingChanged(val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
```

---

## Step 5: Navigation Setup

### Update `lib/main.dart` or router config

Add routes for marketplace:

```dart
GoRoute(
  path: '/marketplace',
  builder: (context, state) => const MarketplaceCatalog(),
),
GoRoute(
  path: '/marketplace/listing/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    return ListingDetail(listingId: id);
  },
),
```

---

## Step 6: Test Mocks

### File: `test/mocks/mock_marketplace_service.dart`

```dart
import 'package:mockito/mockito.dart';
import '../../lib/services/marketplace_service.dart';
import '../../lib/models/agent_listing.dart';

class MockMarketplaceService extends Mock implements MarketplaceService {
  @override
  Future<List<AgentListing>> getListings({
    String? roleFilter,
    double? minRating,
    String? searchQuery,
  }) async {
    return [
      AgentListing(
        listingId: 'listing-1',
        agentId: 'coder#42',
        sellerName: 'alice',
        agentName: 'CodeMaster',
        role: 'coder',
        priceGrim: 500,
        qualityScore: 85,
        averageRating: 4.8,
        reviewCount: 25,
        purchaseCount: 50,
        description: 'Great coder',
        skillSpecializations: [0, 2],
        createdAt: DateTime.now(),
        updatedAt: null,
      ),
      // ... more
    ];
  }

  // Mock other methods similarly
}
```

---

## Implementation Checklist

### Phase 4A: Data Models (1–2 days)
- [ ] `lib/models/agent_listing.dart` (freezed)
- [ ] `lib/models/marketplace_review.dart` (freezed)
- [ ] Add to pubspec.yaml if using freezed

### Phase 4B: Services & Providers (2–3 days)
- [ ] `lib/services/marketplace_service.dart` (interface)
- [ ] `lib/services/impl/http_marketplace_service.dart` (HTTP client)
- [ ] `lib/providers/marketplace_provider.dart` (Riverpod providers)
- [ ] Mock implementation for testing

### Phase 4C: UI Widgets (3–5 days)
- [ ] `lib/widgets/marketplace/marketplace_catalog.dart`
- [ ] `lib/widgets/marketplace/listing_tile.dart`
- [ ] `lib/widgets/marketplace/listing_detail.dart`
- [ ] `lib/widgets/marketplace/purchase_dialog.dart`
- [ ] `lib/widgets/marketplace/listing_filter_bar.dart`
- [ ] `lib/widgets/marketplace/rating_display.dart`
- [ ] Navigation routes in router

### Phase 4D: UI Tests (1–2 days)
- [ ] `test/widgets/marketplace_ui_test.dart` (12 tests)
- [ ] Run: `flutter test test/widgets/marketplace_ui_test.dart`

### Phase 4E: Integration (1 day)
- [ ] Add marketplace tab to ShopPanel or create standalone nav
- [ ] Test end-to-end flow (browse → detail → purchase)
- [ ] Performance check (grid scrolling)

---

## Dependencies to Add

Update `pubspec.yaml`:

```yaml
dependencies:
  freezed_annotation: ^2.4.0
  json_serializable: ^6.7.0
  go_router: ^10.0.0  # if not already present

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.4.0
```

After adding freezed, run:
```bash
flutter pub get
dart run build_runner build
```

---

## Testing Strategy

**Mock-first approach:**
1. Write mocks for `MarketplaceService` with test data
2. Use mock in widget tests (no HTTP calls)
3. Tests verify UI logic, not backend communication
4. Later, real HTTP client can be swapped in

---

## Success Criteria

✅ All 3 models created and tested  
✅ All 6 widgets render without errors  
✅ Filters work: role, rating, search  
✅ Navigation routes resolve correctly  
✅ 12 widget tests pass  
✅ No console warnings  
✅ Grid scrolls smoothly with 50+ items  

---

**Timeline:** 2–3 weeks (1 dev, parallel with other Phase 4 work)  
**Owner:** Backend integration + frontend polish  
**Blocker:** None (can be developed independently)
