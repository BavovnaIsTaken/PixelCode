/// A user review for an agent listing.
class MarketplaceReview {
  final String reviewId;
  final String listingId;
  final String buyerName; // masked/anonymized
  final int rating; // 1-5 stars
  final String comment;
  final DateTime createdAt;

  MarketplaceReview({
    required this.reviewId,
    required this.listingId,
    required this.buyerName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  MarketplaceReview copyWith({
    String? reviewId,
    String? listingId,
    String? buyerName,
    int? rating,
    String? comment,
    DateTime? createdAt,
  }) {
    return MarketplaceReview(
      reviewId: reviewId ?? this.reviewId,
      listingId: listingId ?? this.listingId,
      buyerName: buyerName ?? this.buyerName,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
