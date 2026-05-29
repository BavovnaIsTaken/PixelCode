import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/seller_listings_view.dart';
import 'package:pixelcode/widgets/marketplace/seller_analytics_view.dart';
import 'package:pixelcode/services/marketplace_service.dart';
import 'test_fixtures.dart';

void main() {
  group('Seller Listings View', () {
    // ─── Test 5.1: Seller can view 'My Listings' ───
    testWidgets('displays seller listings with sales and ratings', (tester) async {
      final mockListings = [
        mockAgentListing(
          listingId: 'listing-1',
          name: 'CodeMaster',
          sellerName: 'alice',
          priceGrymni: 500,
          purchaseCount: 12,
          averageRating: 4.8,
        ),
        mockAgentListing(
          listingId: 'listing-2',
          name: 'TestWizard',
          sellerName: 'alice',
          priceGrymni: 400,
          purchaseCount: 8,
          averageRating: 4.5,
        ),
        mockAgentListing(
          listingId: 'listing-3',
          name: 'DevOpsGuru',
          sellerName: 'alice',
          priceGrymni: 600,
          purchaseCount: 5,
          averageRating: 4.2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SellerListingsView(
            listings: mockListings,
            onSelectListing: (_) {},
          ),
        ),
      );

      // Verify title
      expect(find.text('My Listings'), findsOneWidget);

      // Verify all listings are displayed
      expect(find.text('CodeMaster'), findsOneWidget);
      expect(find.text('TestWizard'), findsOneWidget);
      expect(find.text('DevOpsGuru'), findsOneWidget);

      // Verify sales count is shown
      expect(find.text('12'), findsWidgets);
      expect(find.text('8'), findsWidgets);
      expect(find.text('5'), findsWidgets);

      // Verify ratings are shown
      expect(find.byIcon(Icons.star), findsWidgets);
    });

    // ─── Test 5.2: Seller analytics dashboard ───
    testWidgets('displays marketplace analytics with summary stats',
        (tester) async {
      final mockStats = SellerStats(
        sellerId: 'alice',
        totalSales: 50,
        totalRevenue: 2500,
        averageRating: 4.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SellerAnalyticsView(stats: mockStats),
        ),
      );

      // Verify title
      expect(find.text('Analytics'), findsOneWidget);

      // Verify stats are displayed
      expect(find.text('Total Sales'), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('Avg Rating'), findsOneWidget);
      expect(find.text('Marketplace Summary'), findsOneWidget);

      // Verify stat values are shown
      expect(find.text('50'), findsOneWidget);
    });

    // ─── Test 5.3: Empty seller listings state ───
    testWidgets('shows empty state when seller has no listings',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SellerListingsView(
            listings: [],
            onSelectListing: (_) {},
          ),
        ),
      );

      // Verify empty state message
      expect(find.text('No listings yet'), findsOneWidget);

      // Verify create listing button
      expect(find.text('Create Listing'), findsOneWidget);

      // Tapping "Create Listing" should not throw (callback is a no-op placeholder)
      await tester.tap(find.text('Create Listing'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ─── Test 5.4: Listing selection from seller view ───
    testWidgets('invokes callback when listing is tapped',
        (tester) async {
      final mockListings = [
        mockAgentListing(
          listingId: 'listing-1',
          name: 'CodeMaster',
          sellerName: 'alice',
        ),
      ];

      String? selectedId;

      await tester.pumpWidget(
        MaterialApp(
          home: SellerListingsView(
            listings: mockListings,
            onSelectListing: (id) {
              selectedId = id;
            },
          ),
        ),
      );

      // Find and tap listing card
      await tester.tap(find.text('CodeMaster'));
      await tester.pumpAndSettle();

      // Verify callback was invoked
      expect(selectedId, 'listing-1');
    });

    // ─── Test 5.5: Analytics with zero sales ───
    testWidgets('displays zero values gracefully', (tester) async {
      final mockStats = SellerStats(
        sellerId: 'bob',
        totalSales: 0,
        totalRevenue: 0,
        averageRating: 0.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SellerAnalyticsView(stats: mockStats),
        ),
      );

      // Should not crash and should display zeros
      expect(find.text('0'), findsWidgets);
    });
  });
}
