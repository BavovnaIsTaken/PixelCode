import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/marketplace_catalog.dart';
import 'package:pixelcode/widgets/marketplace/listing_tile.dart';
import 'test_fixtures.dart';

void main() {
  group('Marketplace Catalog', () {
    // ─── Test 1.1: Catalog renders grid of agent listings ───
    testWidgets('renders grid of agent listings', (tester) async {
      final mockListings = [
        mockAgentListing(
          listingId: 'listing-1',
          name: 'CodeMaster',
          role: 'coder',
          averageRating: 4.8,
        ),
        mockAgentListing(
          listingId: 'listing-2',
          name: 'TestWizard',
          role: 'tester',
          averageRating: 4.5,
        ),
        mockAgentListing(
          listingId: 'listing-3',
          name: 'DevOpsGuru',
          role: 'devops',
          averageRating: 4.2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: mockListings,
            onSelectListing: (_) {},
          ),
        ),
      );

      // Verify grid is visible with tiles
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListingTile), findsWidgets);

      // Verify price icons are displayed
      expect(find.byIcon(Icons.attach_money), findsWidgets);
    });

    // ─── Test 1.2: Catalog shows 'No listings' when marketplace is empty ───
    testWidgets('shows empty state when no listings available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: [],
            onSelectListing: (_) {},
          ),
        ),
      );

      // Grid should be hidden
      expect(find.byType(GridView), findsNothing);

      // Empty state message should be visible
      expect(
        find.text('No custom agents available yet'),
        findsOneWidget,
      );

      // Refresh button should be visible
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    // ─── Test 2.1: Filter by role ───
    testWidgets('displays filter button and role options', (tester) async {
      final mockListings = [
        mockAgentListing(listingId: 'listing-1', role: 'coder'),
        mockAgentListing(listingId: 'listing-2', role: 'tester'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: mockListings,
            onSelectListing: (_) {},
          ),
        ),
      );

      // Verify filter button exists
      expect(find.byIcon(Icons.tune), findsOneWidget);

      // Tap filter button to open panel
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      // Verify role filter options are displayed
      expect(find.text('coder'), findsWidgets);
      expect(find.text('tester'), findsWidgets);
      expect(find.text('devops'), findsOneWidget);
      expect(find.text('architect'), findsOneWidget);
    });

    // ─── Test 2.2: Filter by minimum rating ───
    testWidgets('displays rating filter slider', (tester) async {
      final mockListings = [
        mockAgentListing(listingId: 'listing-1', averageRating: 5.0),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: mockListings,
            onSelectListing: (_) {},
          ),
        ),
      );

      // Open filter panel
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      // Verify rating slider is displayed
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Minimum Rating'), findsOneWidget);
    });

    // ─── Test 2.3: Search functionality ───
    testWidgets('filters by search query', (tester) async {
      final mockListings = [
        mockAgentListing(listingId: 'listing-1', name: 'CodeMaster'),
        mockAgentListing(listingId: 'listing-2', name: 'TestWizard'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: mockListings,
            onSelectListing: (_) {},
          ),
        ),
      );

      // Find search field
      expect(find.byIcon(Icons.search), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'code');
      await tester.pumpAndSettle();

      // Only CodeMaster should be displayed
      expect(find.text('CodeMaster'), findsOneWidget);
      expect(find.text('TestWizard'), findsNothing);
    });

    // ─── Test 3.1: Listing selection callback ───
    testWidgets('invokes onSelectListing callback when tile is tapped',
        (tester) async {
      final mockListing = mockAgentListing(
        listingId: 'listing-1',
        name: 'CodeMaster',
        priceGrymni: 500,
      );

      String? selectedId;
      await tester.pumpWidget(
        MaterialApp(
          home: MarketplaceCatalog(
            listings: [mockListing],
            onSelectListing: (id) {
              selectedId = id;
            },
          ),
        ),
      );

      // Tap the listing tile
      await tester.tap(find.byType(ListingTile));
      await tester.pumpAndSettle();

      // Verify callback was invoked with correct ID
      expect(selectedId, 'listing-1');
    });

    // ─── Test 3.2: Listing tile displays all information ───
    testWidgets('listing tile shows agent name, role, rating, and price',
        (tester) async {
      final mockListing = mockAgentListing(
        listingId: 'listing-1',
        name: 'CodeMaster',
        role: 'coder',
        priceGrymni: 500,
        averageRating: 4.8,
        reviewCount: 25,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListingTile(
              listing: mockListing,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify all fields are displayed
      expect(find.text('CodeMaster'), findsOneWidget);
      expect(find.text('coder'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.attach_money), findsOneWidget);
    });
  });
}
