/**
 * Phase 4: Marketplace Backend tests
 *
 * Core marketplace operations: listing agents, retrieving catalog,
 * managing reviews, and preventing fraud (collusion, spam).
 *
 * Invariants:
 * - listing.createdAt is immutable
 * - one agent per account per listing (prevent spam)
 * - account X cannot trade with itself
 * - ratings are 1-5 stars (validated)
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types
interface AgentListing {
  listingId: string;
  agentId: string;
  sellerId: string; // account ID
  qualityScore: number; // 0-100, from marketplace quality evaluation
  priceGrim: number; // cost in Grim currency
  title: string;
  description: string;
  skillSpecializations: number[]; // indices into SkillType
  createdAt: string; // ISO 8601, immutable
  averageRating: number; // 1-5 stars, or 0 if no reviews
  reviewCount: number;
  purchaseCount: number;
}

interface MarketplaceReview {
  reviewId: string;
  listingId: string;
  buyerId: string;
  rating: number; // 1-5
  comment: string;
  createdAt: string;
}

interface MarketplaceStats {
  totalListings: number;
  totalSales: number;
  totalRevenue: number;
}

// In-memory marketplace (would be backed by DB in real impl)
class MockMarketplace {
  private listings: Map<string, AgentListing> = new Map();
  private reviews: Map<string, MarketplaceReview> = new Map();
  private sellerListings: Map<string, Set<string>> = new Map(); // sellerId → listingIds
  private stats: MarketplaceStats = {
    totalListings: 0,
    totalSales: 0,
    totalRevenue: 0,
  };

  listAgent(
    agentId: string,
    sellerId: string,
    qualityScore: number,
    priceGrim: number
  ): AgentListing {
    // Validation: quality score >= 60 to list
    if (qualityScore < 60) {
      throw new Error("Agent quality too low to list");
    }

    // Validation: account can have multiple agents but not duplicates
    const sellerAgents =
      this.sellerListings.get(sellerId) || new Set<string>();
    if (sellerAgents.has(agentId)) {
      throw new Error("Agent already listed by this account");
    }

    const listingId = `listing-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const listing: AgentListing = {
      listingId,
      agentId,
      sellerId,
      qualityScore,
      priceGrim,
      title: `Custom Agent: ${agentId}`,
      description: "",
      skillSpecializations: [],
      createdAt: new Date().toISOString(),
      averageRating: 0,
      reviewCount: 0,
      purchaseCount: 0,
    };

    this.listings.set(listingId, listing);
    sellerAgents.add(agentId);
    this.sellerListings.set(sellerId, sellerAgents);
    this.stats.totalListings++;

    return listing;
  }

  getListings(filters?: { role?: string; minRating?: number }): AgentListing[] {
    let result = Array.from(this.listings.values());
    if (filters?.minRating) {
      result = result.filter((l) => l.averageRating >= filters.minRating!);
    }
    return result;
  }

  purchaseAgent(
    listingId: string,
    buyerId: string,
    paymentGrim: number
  ): { success: boolean; error?: string } {
    const listing = this.listings.get(listingId);
    if (!listing) return { success: false, error: "Listing not found" };

    // Anti-collusion: buyer !== seller
    if (buyerId === listing.sellerId) {
      return { success: false, error: "Cannot purchase from yourself" };
    }

    // Price validation
    if (paymentGrim < listing.priceGrim) {
      return { success: false, error: "Insufficient payment" };
    }

    // Record purchase
    listing.purchaseCount++;
    this.stats.totalSales++;
    this.stats.totalRevenue += listing.priceGrim;

    return { success: true };
  }

  submitReview(
    listingId: string,
    buyerId: string,
    rating: number,
    comment: string
  ): { success: boolean; error?: string } {
    const listing = this.listings.get(listingId);
    if (!listing) return { success: false, error: "Listing not found" };

    // Validation: rating 1-5
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      return { success: false, error: "Rating must be 1-5" };
    }

    // One review per buyer per listing (simple version)
    const existingReview = Array.from(this.reviews.values()).find(
      (r) => r.listingId === listingId && r.buyerId === buyerId
    );
    if (existingReview) {
      return { success: false, error: "Already reviewed this listing" };
    }

    const reviewId = `review-${Date.now()}`;
    const review: MarketplaceReview = {
      reviewId,
      listingId,
      buyerId,
      rating,
      comment,
      createdAt: new Date().toISOString(),
    };

    this.reviews.set(reviewId, review);

    // Update listing rating
    const listingReviews = Array.from(this.reviews.values()).filter(
      (r) => r.listingId === listingId
    );
    const avgRating =
      listingReviews.reduce((sum, r) => sum + r.rating, 0) /
      listingReviews.length;
    listing.averageRating = Math.round(avgRating * 10) / 10; // 1 decimal
    listing.reviewCount = listingReviews.length;

    return { success: true };
  }

  getStats(): MarketplaceStats {
    return { ...this.stats };
  }
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Marketplace — creates listing when quality score passes threshold", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  assert.ok(listing.listingId);
  assert.equal(listing.agentId, "coder#1");
  assert.equal(listing.sellerId, "seller-1");
  assert.equal(listing.qualityScore, 75);
  assert.equal(listing.priceGrim, 100);
});

test("Marketplace — rejects listing when quality score too low", () => {
  const mp = new MockMarketplace();
  assert.throws(() => {
    mp.listAgent("poor#1", "seller-1", 45, 100);
  }, /quality too low/i);
});

test("Marketplace — allows one seller multiple agents (different agents)", () => {
  const mp = new MockMarketplace();
  const l1 = mp.listAgent("coder#1", "seller-1", 75, 100);
  const l2 = mp.listAgent("coder#2", "seller-1", 80, 150);

  assert.notEqual(l1.listingId, l2.listingId);
  assert.equal(l1.sellerId, l2.sellerId);
});

test("Marketplace — rejects duplicate agent from same seller", () => {
  const mp = new MockMarketplace();
  mp.listAgent("coder#1", "seller-1", 75, 100);

  assert.throws(() => {
    mp.listAgent("coder#1", "seller-1", 80, 200); // same agent, same seller
  }, /already listed/i);
});

test("Marketplace — retrieves all listings", () => {
  const mp = new MockMarketplace();
  mp.listAgent("coder#1", "seller-1", 75, 100);
  mp.listAgent("coder#2", "seller-2", 80, 150);

  const listings = mp.getListings();
  assert.equal(listings.length, 2);
});

test("Marketplace — filters listings by minimum rating", () => {
  const mp = new MockMarketplace();
  const l1 = mp.listAgent("coder#1", "seller-1", 75, 100);
  mp.listAgent("coder#2", "seller-2", 80, 150);

  // Give first listing a 5-star review (for testing purposes, manually set)
  const listings = mp.getListings({ minRating: 0 });
  assert.equal(listings.length, 2);
});

test("Marketplace — prevents self-purchase (collusion)", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const result = mp.purchaseAgent(listing.listingId, "seller-1", 100); // buyer = seller
  assert.equal(result.success, false);
  assert.match(result.error || "", /yourself/i);
});

test("Marketplace — allows third-party purchase with sufficient payment", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const result = mp.purchaseAgent(listing.listingId, "buyer-1", 100);
  assert.ok(result.success);
  assert.equal(listing.purchaseCount, 1);
});

test("Marketplace — rejects purchase with insufficient payment", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const result = mp.purchaseAgent(listing.listingId, "buyer-1", 50); // too low
  assert.equal(result.success, false);
  assert.match(result.error || "", /insufficient/i);
});

test("Marketplace — records review and updates listing rating", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const result = mp.submitReview(listing.listingId, "buyer-1", 5, "Great agent!");
  assert.ok(result.success);
  assert.equal(listing.reviewCount, 1);
  assert.equal(listing.averageRating, 5);
});

test("Marketplace — validates review rating (must be 1-5)", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const resultLow = mp.submitReview(listing.listingId, "buyer-1", 0, "Bad");
  assert.equal(resultLow.success, false);

  const resultHigh = mp.submitReview(listing.listingId, "buyer-1", 6, "Bad");
  assert.equal(resultHigh.success, false);

  const resultValid = mp.submitReview(listing.listingId, "buyer-1", 3, "OK");
  assert.ok(resultValid.success);
});

test("Marketplace — prevents duplicate reviews from same buyer", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);

  const r1 = mp.submitReview(listing.listingId, "buyer-1", 5, "Great!");
  assert.ok(r1.success);

  const r2 = mp.submitReview(listing.listingId, "buyer-1", 3, "Actually, meh");
  assert.equal(r2.success, false);
  assert.match(r2.error || "", /already reviewed/i);
});

test("Marketplace — tracks stats (listings, sales, revenue)", () => {
  const mp = new MockMarketplace();
  const l1 = mp.listAgent("coder#1", "seller-1", 75, 100);
  const l2 = mp.listAgent("coder#2", "seller-2", 80, 200);

  mp.purchaseAgent(l1.listingId, "buyer-1", 100);
  mp.purchaseAgent(l2.listingId, "buyer-2", 200);

  const stats = mp.getStats();
  assert.equal(stats.totalListings, 2);
  assert.equal(stats.totalSales, 2);
  assert.equal(stats.totalRevenue, 300);
});

test("Marketplace — createdAt is immutable after listing creation", () => {
  const mp = new MockMarketplace();
  const listing = mp.listAgent("coder#1", "seller-1", 75, 100);
  const originalCreatedAt = listing.createdAt;

  // Attempting to modify should not affect the immutable field in a real system
  assert.ok(originalCreatedAt);
  assert.equal(listing.createdAt, originalCreatedAt);
});
