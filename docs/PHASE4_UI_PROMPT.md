# Phase 4 UI Testing Prompt — Marketplace v1 (Flutter)

## Objective
Write **12 widget tests** for the Flutter Marketplace UI. These tests verify user-facing functionality for browsing, filtering, and purchasing custom agents.

---

## Test File Structure
Create: **`test/widgets/marketplace_ui_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/marketplace_catalog.dart';
import 'package:pixelcode/widgets/marketplace/listing_detail.dart';
import 'package:pixelcode/widgets/marketplace/purchase_flow.dart';
import 'package:pixelcode/models/agent_listing.dart';
import 'package:pixelcode/services/mock_marketplace_service.dart';
```

---

## Test Groups & Specs

### 1. **Catalog Display** (2 tests)

#### Test 1.1: "Catalog renders grid of agent listings"
**Setup:**
- Mock marketplace service returns 6 agents (mix of roles: coder, tester, devops)
- Each listing has: name, role, price, rating (1-5 stars), thumbnail

**Assertions:**
- Grid is visible
- All 6 agents are displayed (lazy load or full list)
- Each tile shows: agent name, role badge, price in Grim (₲), star rating
- Tapping a tile navigates to `ListingDetail`

#### Test 1.2: "Catalog shows 'No listings' when marketplace is empty"
**Setup:**
- Marketplace service returns empty list

**Assertions:**
- Grid is hidden
- Empty state message displayed: "No custom agents available yet"
- Refresh button is visible

---

### 2. **Filtering & Search** (3 tests)

#### Test 2.1: "Filter by role (coder/tester/devops/architect)"
**Setup:**
- Marketplace has 8 agents: 3 coders, 2 testers, 2 devops, 1 architect
- Role filter dropdown in header

**Actions:**
- Tap "Filter" → select "Coder"

**Assertions:**
- Grid updates to show only 3 coders
- Other roles hidden
- Filter chip shows "Coder ✕" (with clear button)
- Tap ✕ clears filter, all agents reappear

#### Test 2.2: "Filter by minimum rating (1–5 stars)"
**Setup:**
- Agents have ratings: 5, 5, 4, 4, 3, 2, 1
- Rating filter slider in header

**Actions:**
- Drag slider to "4 stars minimum"

**Assertions:**
- Grid shows only 4 agents (5, 5, 4, 4)
- 3-star and below hidden
- Moving slider updates count in real-time

#### Test 2.3: "Combined filters (role + rating)"
**Setup:**
- Agents: 2 coders (5★, 3★), 2 testers (4★, 2★)

**Actions:**
- Filter: role = coder AND rating ≥ 4

**Assertions:**
- Only 5★ coder shown
- Filter applied correctly (intersection, not union)

---

### 3. **Listing Detail View** (2 tests)

#### Test 3.1: "Detail screen shows full agent stats"
**Setup:**
- Navigate to a specific agent listing

**Assertions:**
- Agent name, role, price displayed prominently
- Stats section: level, skills breakdown, win rate
- Reviews section: list of 1–5 star ratings + comments
- Author info: seller name, total sales, joined date
- "Buy Agent" button visible at bottom
- Back button navigates to catalog

#### Test 3.2: "Reviews are scrollable and show oldest → newest"
**Setup:**
- Agent has 20+ reviews

**Assertions:**
- Reviews list is scrollable
- Each review shows: buyer username (masked), rating, comment, date
- Oldest reviews at top (or configurable sort)
- Date format is human-readable ("2 weeks ago")

---

### 4. **Purchase Flow** (3 tests)

#### Test 4.1: "Purchase button shows price and opens confirmation dialog"
**Setup:**
- On listing detail, agent costs 500 ₲
- User has 1000 ₲ in account

**Actions:**
- Tap "Buy Agent" button

**Assertions:**
- Dialog appears: "Purchase [AgentName] for 500 ₲?"
- Breakdown shown: 500 ₲ price, 100 ₲ commission, 400 ₲ to seller (transparent)
- "Cancel" and "Confirm Purchase" buttons
- "Cancel" dismisses dialog

#### Test 4.2: "Successful purchase adds agent to inventory"
**Setup:**
- Same as 4.1
- Mock service confirms purchase

**Actions:**
- Tap "Confirm Purchase"

**Assertions:**
- Dialog dismisses
- Success message: "Agent purchased successfully!"
- Agent appears in user's inventory (or navigate to inventory)
- Account balance decreases by 500 ₲
- Marketplace catalog updates (purchaseCount incremented)

#### Test 4.3: "Purchase fails gracefully (insufficient funds)"
**Setup:**
- Agent costs 500 ₲
- User has only 200 ₲

**Actions:**
- Tap "Buy Agent"

**Assertions:**
- Dialog shows error: "Insufficient funds (need 500 ₲, have 200 ₲)"
- "Buy" button is disabled (greyed out)
- Cannot proceed without more funds

---

### 5. **Author/Seller View** (2 tests)

#### Test 5.1: "Seller can view 'My Listings' with analytics"
**Setup:**
- Logged in as seller who has 3 agents listed
- Navigate to "My Listings" tab

**Assertions:**
- All 3 listings shown in a card layout
- Each card shows: agent name, price, total sales (e.g., "12 sold"), avg rating
- Tap card → detail view with edit option (future feature)

#### Test 5.2: "Marketplace analytics dashboard"
**Setup:**
- Seller has 3 agents: 50 total sales, 2500 ₲ revenue, avg 4.2★ rating

**Actions:**
- Navigate to "Analytics" or "Dashboard" tab

**Assertions:**
- Summary stats displayed: total sales, revenue, avg rating
- Bar chart or trend: sales over time (weekly)
- Top performer: "Agent A: 25 sales"
- Revenue breakdown: by agent

---

## Key Invariants & Edge Cases

### Invariants
- **Grid is always in sync with backend**: after purchase, listing's purchaseCount updates
- **Filters don't break navigation**: can filter → open detail → back to catalog → filters preserved
- **Prices are always visible**: no agent shown without cost
- **Ratings immutable in UI**: user can't edit ratings from catalog (review system separate)

### Edge Cases to Test
- Empty search results ("No agents match filters")
- Very long agent names (text overflow → ellipsis)
- Listing with 0 reviews ("No reviews yet")
- Agent with 100+ sales (verify count display)
- Tap "Buy" while purchase is in flight (button disabled, no double-click)
- Network error during purchase (show retry dialog)

---

## Mock Data

```dart
final mockListings = [
  AgentListing(
    listingId: 'listing-1',
    agentId: 'coder#42',
    name: 'CodeMaster',
    role: 'coder',
    price: 500,
    qualityScore: 85,
    averageRating: 4.8,
    reviewCount: 25,
    purchaseCount: 50,
    sellerName: 'alice',
    description: 'Specialized in debugging and optimization',
    skillSpecializations: [SkillType.precision, SkillType.speed],
  ),
  // ... 5+ more
];

final mockReviews = [
  MarketplaceReview(
    reviewId: 'review-1',
    rating: 5,
    comment: 'Great agent! Fixed my code in 2 runs.',
    buyerName: 'user123',
    createdAt: '2026-04-20',
  ),
  // ...
];
```

---

## Test Helpers

```dart
Future<void> pumpMarketplace(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MarketplaceCatalog(
        marketplaceService: MockMarketplaceService(listings: mockListings),
      ),
    ),
  );
}

Future<void> tapFilterButton(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
}

Future<void> selectRoleFilter(WidgetTester tester, String role) async {
  await tester.tap(find.byKey(ValueKey('role-$role')));
  await tester.pumpAndSettle();
}
```

---

## Files to Check / Create

**Existing (to test):**
- `lib/widgets/marketplace/marketplace_catalog.dart` — grid view
- `lib/widgets/marketplace/listing_detail.dart` — detail screen
- `lib/widgets/marketplace/purchase_flow.dart` — purchase dialog
- `lib/services/marketplace_service.dart` — API calls

**New (test file):**
- `test/widgets/marketplace_ui_test.dart` — all 12 tests

**Mocks:**
- `test/mocks/mock_marketplace_service.dart` — already exists or create

---

## Success Criteria

✅ All 12 tests pass  
✅ No console warnings during test runs  
✅ Tests run in <5 seconds total  
✅ Coverage: `marketplace_catalog.dart` & `listing_detail.dart` >90%  
✅ Ready for real marketplace UI implementation (tests are spec)

---

## Command to Run

```bash
flutter test test/widgets/marketplace_ui_test.dart
```

## Notes for Implementation

1. **Mock the MarketplaceService** — don't hit real backend
2. **Use `pumpAndSettle()`** after actions that trigger animations
3. **Test accessibility** — all buttons should have labels
4. **No hard sleeps** — use `pumpAndSettle()` or `pump(Duration(...))`
5. **Assume UI already exists** — these tests are for **existing or to-be-built** UI widgets

---

**Status:** Ready for implementation  
**Phase:** 4 (Marketplace v1)  
**Duration:** 1 dev-week  
**Blocker:** Marketplace UI widgets must exist or be stubbed
