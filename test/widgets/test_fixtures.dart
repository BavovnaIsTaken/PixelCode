import 'package:pixelcode/models/agent_listing.dart';
import 'package:pixelcode/models/marketplace_review.dart';

/// Create a mock AgentListing with sensible defaults for testing.
AgentListing mockAgentListing({
  String? listingId,
  String? agentId,
  String? name,
  String? role,
  int? priceGrymni,
  double? qualityScore,
  double? averageRating,
  int? reviewCount,
  int? purchaseCount,
  String? sellerName,
  String? description,
  List<String>? skillSpecializations,
  DateTime? createdAt,
}) {
  return AgentListing(
    listingId: listingId ?? 'listing-${DateTime.now().millisecondsSinceEpoch}',
    agentId: agentId ?? 'agent-1',
    name: name ?? 'Test Agent',
    role: role ?? 'coder',
    priceGrymni: priceGrymni ?? 500,
    qualityScore: qualityScore ?? 85.0,
    averageRating: averageRating ?? 4.5,
    reviewCount: reviewCount ?? 10,
    purchaseCount: purchaseCount ?? 5,
    sellerName: sellerName ?? 'seller-1',
    description: description ?? 'A test agent listing',
    skillSpecializations: skillSpecializations ?? ['precision', 'speed'],
    createdAt: createdAt ?? DateTime.now(),
  );
}

/// Create a mock MarketplaceReview with sensible defaults for testing.
MarketplaceReview mockMarketplaceReview({
  String? reviewId,
  String? listingId,
  String? buyerName,
  int? rating,
  String? comment,
  DateTime? createdAt,
}) {
  return MarketplaceReview(
    reviewId: reviewId ?? 'review-${DateTime.now().millisecondsSinceEpoch}',
    listingId: listingId ?? 'listing-1',
    buyerName: buyerName ?? 'user-123',
    rating: rating ?? 5,
    comment: comment ?? 'Great agent! Fixed my code in 2 runs.',
    createdAt: createdAt ?? DateTime.now(),
  );
}
