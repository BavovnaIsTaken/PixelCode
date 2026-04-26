/// Marketplace listing for a custom agent.
class AgentListing {
  final String listingId;
  final String agentId;
  final String name;
  final String role; // 'coder', 'tester', 'devops', 'architect'
  final int priceGrim;
  final double qualityScore; // 0-100
  final double averageRating; // 1-5
  final int reviewCount;
  final int purchaseCount;
  final String sellerName;
  final String description;
  final List<String> skillSpecializations;
  final DateTime createdAt;
  final DateTime? updatedAt;

  AgentListing({
    required this.listingId,
    required this.agentId,
    required this.name,
    required this.role,
    required this.priceGrim,
    required this.qualityScore,
    required this.averageRating,
    required this.reviewCount,
    required this.purchaseCount,
    required this.sellerName,
    required this.description,
    required this.skillSpecializations,
    required this.createdAt,
    this.updatedAt,
  });

  /// Create a copy with optional field overrides (for testing).
  AgentListing copyWith({
    String? listingId,
    String? agentId,
    String? name,
    String? role,
    int? priceGrim,
    double? qualityScore,
    double? averageRating,
    int? reviewCount,
    int? purchaseCount,
    String? sellerName,
    String? description,
    List<String>? skillSpecializations,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentListing(
      listingId: listingId ?? this.listingId,
      agentId: agentId ?? this.agentId,
      name: name ?? this.name,
      role: role ?? this.role,
      priceGrim: priceGrim ?? this.priceGrim,
      qualityScore: qualityScore ?? this.qualityScore,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      sellerName: sellerName ?? this.sellerName,
      description: description ?? this.description,
      skillSpecializations: skillSpecializations ?? this.skillSpecializations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
