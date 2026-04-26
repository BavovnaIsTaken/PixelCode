/**
 * Phase 4: Marketplace Commission tests
 *
 * Track marketplace revenue from agent sales, calculate seller payouts,
 * and handle commission splits (15–20% platform take, 80–85% to seller).
 *
 * Invariants:
 * - commission_rate is constant (e.g., 20%)
 * - seller_payout + platform_commission = sale_price
 * - total_commission = sum of all sale commissions
 * - commission audit trail is immutable
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types
interface CommissionTx {
  txId: string;
  salePrice: number; // in Grim
  sellerPayout: number;
  platformCommission: number;
  commissionRate: number; // e.g., 0.20 (20%)
  sellerId: string;
  buyerId: string;
  listingId: string;
  timestamp: string; // ISO 8601
}

interface MarketplaceCommissionStats {
  totalSales: number;
  totalRevenue: number; // total sale prices
  totalCommission: number; // sum of platform takes
  totalPayouts: number; // sum of seller payouts
  avgCommissionRate: number;
}

const COMMISSION_RATE = 0.20; // 20% to platform, 80% to seller

// In-memory commission tracker (would be backed by DB in real impl)
class MockCommissionTracker {
  private transactions: Map<string, CommissionTx> = new Map();
  private stats: MarketplaceCommissionStats = {
    totalSales: 0,
    totalRevenue: 0,
    totalCommission: 0,
    totalPayouts: 0,
    avgCommissionRate: COMMISSION_RATE,
  };

  recordSale(
    salePrice: number,
    sellerId: string,
    buyerId: string,
    listingId: string
  ): CommissionTx {
    if (salePrice < 0) {
      throw new Error("Sale price cannot be negative");
    }

    const platformCommission = Math.round(salePrice * COMMISSION_RATE);
    const sellerPayout = salePrice - platformCommission;

    const txId = `tx-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const tx: CommissionTx = {
      txId,
      salePrice,
      sellerPayout,
      platformCommission,
      commissionRate: COMMISSION_RATE,
      sellerId,
      buyerId,
      listingId,
      timestamp: new Date().toISOString(),
    };

    this.transactions.set(txId, tx);

    // Update stats
    this.stats.totalSales++;
    this.stats.totalRevenue += salePrice;
    this.stats.totalCommission += platformCommission;
    this.stats.totalPayouts += sellerPayout;

    return tx;
  }

  getTransaction(txId: string): CommissionTx | undefined {
    return this.transactions.get(txId);
  }

  getSellerEarnings(sellerId: string): number {
    let total = 0;
    for (const tx of this.transactions.values()) {
      if (tx.sellerId === sellerId) {
        total += tx.sellerPayout;
      }
    }
    return total;
  }

  getBuyerSpent(buyerId: string): number {
    let total = 0;
    for (const tx of this.transactions.values()) {
      if (tx.buyerId === buyerId) {
        total += tx.salePrice;
      }
    }
    return total;
  }

  getStats(): MarketplaceCommissionStats {
    return { ...this.stats };
  }

  getAllTransactions(): CommissionTx[] {
    return Array.from(this.transactions.values());
  }
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Commission — records sale with correct payout split", () => {
  const tracker = new MockCommissionTracker();
  const tx = tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");

  assert.equal(tx.salePrice, 1000);
  assert.equal(tx.commissionRate, 0.2);
  assert.equal(tx.platformCommission, 200); // 20%
  assert.equal(tx.sellerPayout, 800); // 80%
});

test("Commission — payout + commission always equals sale price", () => {
  const tracker = new MockCommissionTracker();
  const testCases = [1, 10, 100, 1000, 5000];

  for (const price of testCases) {
    const tx = tracker.recordSale(price, "seller-1", "buyer-1", "listing-1");
    assert.equal(
      tx.sellerPayout + tx.platformCommission,
      tx.salePrice,
      `invariant violated for price ${price}`
    );
  }
});

test("Commission — rejects negative sale price", () => {
  const tracker = new MockCommissionTracker();
  assert.throws(() => {
    tracker.recordSale(-100, "seller-1", "buyer-1", "listing-1");
  }, /cannot be negative/i);
});

test("Commission — tracks seller earnings across multiple sales", () => {
  const tracker = new MockCommissionTracker();
  tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");
  tracker.recordSale(500, "seller-1", "buyer-2", "listing-2");
  tracker.recordSale(2000, "seller-2", "buyer-3", "listing-3");

  const seller1Earnings = tracker.getSellerEarnings("seller-1");
  const seller2Earnings = tracker.getSellerEarnings("seller-2");

  assert.equal(seller1Earnings, 800 + 400); // 80% of each sale
  assert.equal(seller2Earnings, 1600); // 80% of 2000
});

test("Commission — tracks buyer spending across purchases", () => {
  const tracker = new MockCommissionTracker();
  tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");
  tracker.recordSale(500, "seller-2", "buyer-1", "listing-2");
  tracker.recordSale(300, "seller-3", "buyer-2", "listing-3");

  const buyer1Spent = tracker.getBuyerSpent("buyer-1");
  const buyer2Spent = tracker.getBuyerSpent("buyer-2");

  assert.equal(buyer1Spent, 1500); // 1000 + 500
  assert.equal(buyer2Spent, 300);
});

test("Commission — aggregates stats: total revenue and commission", () => {
  const tracker = new MockCommissionTracker();
  tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");
  tracker.recordSale(2000, "seller-2", "buyer-2", "listing-2");
  tracker.recordSale(500, "seller-3", "buyer-3", "listing-3");

  const stats = tracker.getStats();

  assert.equal(stats.totalSales, 3);
  assert.equal(stats.totalRevenue, 3500); // 1000 + 2000 + 500
  assert.equal(stats.totalCommission, 700); // 20% of 3500
  assert.equal(stats.totalPayouts, 2800); // 80% of 3500
  assert.equal(
    stats.totalCommission + stats.totalPayouts,
    stats.totalRevenue,
    "commission + payout = revenue"
  );
});

test("Commission — generates immutable transaction IDs", () => {
  const tracker = new MockCommissionTracker();
  const tx1 = tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");
  const tx2 = tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");

  assert.notEqual(
    tx1.txId,
    tx2.txId,
    "different transactions should have unique IDs"
  );
  assert.ok(tx1.txId.startsWith("tx-"), "txId should have prefix");
});

test("Commission — transaction is immutable (retrieve and verify)", () => {
  const tracker = new MockCommissionTracker();
  const originalTx = tracker.recordSale(
    1000,
    "seller-1",
    "buyer-1",
    "listing-1"
  );

  const retrievedTx = tracker.getTransaction(originalTx.txId);
  assert.deepEqual(retrievedTx, originalTx, "transaction should be unchanged");
});

test("Commission — handles zero-value sales (e.g., free agents)", () => {
  const tracker = new MockCommissionTracker();
  const tx = tracker.recordSale(0, "seller-1", "buyer-1", "listing-1");

  assert.equal(tx.salePrice, 0);
  assert.equal(tx.platformCommission, 0);
  assert.equal(tx.sellerPayout, 0);
});

test("Commission — large sales maintain precision (e.g., 1M Grim)", () => {
  const tracker = new MockCommissionTracker();
  const largePrice = 1000000;
  const tx = tracker.recordSale(largePrice, "seller-1", "buyer-1", "listing-1");

  assert.equal(tx.platformCommission, 200000); // 20%
  assert.equal(tx.sellerPayout, 800000); // 80%
  assert.equal(tx.platformCommission + tx.sellerPayout, largePrice);
});

test("Commission — monotonicity: more expensive agents → more commission revenue", () => {
  const tracker = new MockCommissionTracker();
  const tx1 = tracker.recordSale(100, "seller-1", "buyer-1", "listing-1");
  const tx2 = tracker.recordSale(1000, "seller-2", "buyer-2", "listing-2");
  const tx3 = tracker.recordSale(10000, "seller-3", "buyer-3", "listing-3");

  assert.ok(tx1.platformCommission <= tx2.platformCommission);
  assert.ok(tx2.platformCommission <= tx3.platformCommission);
});

test("Commission — all transactions auditable (retrieve any tx)", () => {
  const tracker = new MockCommissionTracker();
  const tx1 = tracker.recordSale(1000, "seller-1", "buyer-1", "listing-1");
  const tx2 = tracker.recordSale(2000, "seller-2", "buyer-2", "listing-2");
  const tx3 = tracker.recordSale(500, "seller-3", "buyer-3", "listing-3");

  const allTxs = tracker.getAllTransactions();
  assert.equal(allTxs.length, 3);
  assert.ok(allTxs.some((tx) => tx.txId === tx1.txId));
  assert.ok(allTxs.some((tx) => tx.txId === tx2.txId));
  assert.ok(allTxs.some((tx) => tx.txId === tx3.txId));
});
