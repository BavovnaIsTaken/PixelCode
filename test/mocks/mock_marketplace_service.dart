import 'package:pixelcode/models/agent_listing.dart';
import 'package:pixelcode/models/marketplace_review.dart';
import 'package:pixelcode/services/marketplace_service.dart';

/// In-memory mock implementation for testing marketplace UI without network calls.
class MockMarketplaceService implements MarketplaceService {
  final List<AgentListing> _listings;
  final Map<String, List<MarketplaceReview>> _reviews;
  final Set<String> _purchasedListingIds;

  MockMarketplaceService({
    List<AgentListing>? listings,
    Map<String, List<MarketplaceReview>>? reviews,
  })  : _listings = listings ?? [],
        _reviews = reviews ?? {},
        _purchasedListingIds = {};

  @override
  Future<List<AgentListing>> getListings({
    String? roleFilter,
    double? minRating,
  }) async {
    var result = List<AgentListing>.from(_listings);

    if (roleFilter != null) {
      result = result.where((l) => l.role == roleFilter).toList();
    }

    if (minRating != null) {
      result = result.where((l) => l.averageRating >= minRating).toList();
    }

    return result;
  }

  @override
  Future<AgentListing?> getListing(String listingId) async {
    try {
      return _listings.firstWhere((l) => l.listingId == listingId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<MarketplaceReview>> getReviews(String listingId) async {
    return _reviews[listingId] ?? [];
  }

  @override
  Future<PurchaseResult> purchaseAgent(
    String listingId,
    String buyerId,
  ) async {
    // Simulate purchase success
    _purchasedListingIds.add(listingId);
    final listing = await getListing(listingId);
    if (listing == null) {
      return PurchaseResult(
        status: PurchaseStatus.unknown,
        message: 'Listing not found',
      );
    }
    return PurchaseResult(
      status: PurchaseStatus.success,
      transactionId: 'tx-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  @override
  Future<List<AgentListing>> getSellerListings(String sellerId) async {
    return _listings.where((l) => l.sellerName == sellerId).toList();
  }

  @override
  Future<SellerStats> getSellerStats(String sellerId) async {
    final sellerListings =
        _listings.where((l) => l.sellerName == sellerId).toList();
    final totalSales =
        sellerListings.fold<int>(0, (sum, l) => sum + l.purchaseCount);
    final totalRevenue = sellerListings.fold<int>(0, (sum, l) {
      final sellerShare = (l.priceGrymni * 0.8).floor();
      return sum + (sellerShare * l.purchaseCount);
    });
    final avgRating = sellerListings.isNotEmpty
        ? (sellerListings.fold<double>(0, (sum, l) => sum + l.averageRating) /
            sellerListings.length)
        : 0.0;

    return SellerStats(
      sellerId: sellerId,
      totalSales: totalSales,
      totalRevenue: totalRevenue,
      averageRating: avgRating,
    );
  }

  bool wasPurchased(String listingId) => _purchasedListingIds.contains(listingId);
}
