import 'package:pixelcode/models/agent_listing.dart';
import 'package:pixelcode/models/marketplace_review.dart';

/// Result of a purchase transaction.
enum PurchaseStatus {
  success,
  insufficientFunds,
  networkError,
  unknown,
}

class PurchaseResult {
  final PurchaseStatus status;
  final String? message;
  final String? transactionId;

  PurchaseResult({
    required this.status,
    this.message,
    this.transactionId,
  });
}

/// Abstract interface for marketplace operations.
abstract class MarketplaceService {
  /// Get all listings, optionally filtered by role.
  Future<List<AgentListing>> getListings({
    String? roleFilter,
    double? minRating,
  });

  /// Get a specific listing by ID.
  Future<AgentListing?> getListing(String listingId);

  /// Get reviews for a listing.
  Future<List<MarketplaceReview>> getReviews(String listingId);

  /// Purchase an agent. Returns transaction ID on success.
  Future<PurchaseResult> purchaseAgent(
    String listingId,
    String buyerId,
  );

  /// Get listings created by a seller.
  Future<List<AgentListing>> getSellerListings(String sellerId);

  /// Get seller statistics (total sales, revenue, avg rating).
  Future<SellerStats> getSellerStats(String sellerId);
}

class SellerStats {
  final String sellerId;
  final int totalSales;
  final int totalRevenue; // in Grim
  final double averageRating;

  SellerStats({
    required this.sellerId,
    required this.totalSales,
    required this.totalRevenue,
    required this.averageRating,
  });
}
