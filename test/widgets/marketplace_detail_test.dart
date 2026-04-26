import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/listing_detail.dart';
import 'package:pixelcode/widgets/marketplace/purchase_dialog.dart';
import 'package:pixelcode/services/marketplace_service.dart';
import 'test_fixtures.dart';

void main() {
  group('Listing Detail View', () {
    // ─── Test 3.1: Detail screen shows full agent stats ───
    testWidgets('displays agent name, role, price, and stats', (tester) async {
      final mockListing = mockAgentListing(
        listingId: 'listing-1',
        name: 'CodeMaster',
        role: 'coder',
        priceGrim: 500,
        qualityScore: 85.0,
        averageRating: 4.8,
        reviewCount: 25,
        purchaseCount: 50,
        sellerName: 'alice',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ListingDetail(
            listing: mockListing,
            reviews: [],
            onPurchase: (_) {},
            onBack: () {},
          ),
        ),
      );

      // Verify basic info
      expect(find.text('CodeMaster'), findsWidgets);
      expect(find.text('coder'), findsOneWidget);
      expect(find.text('500 ₲'), findsOneWidget);

      // Verify stats section
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Quality Score'), findsOneWidget);
      expect(find.text('Total Sales'), findsOneWidget);
      expect(find.text('Seller'), findsOneWidget);

      // Verify buy button
      expect(find.text('Buy Agent'), findsOneWidget);
    });

    // ─── Test 3.2: Reviews are displayed with ratings and dates ───
    testWidgets('displays reviews with ratings and user names', (tester) async {
      final mockListing = mockAgentListing(listingId: 'listing-1');
      final mockReviews = [
        mockMarketplaceReview(
          reviewId: 'review-1',
          buyerName: 'user-1',
          rating: 5,
          comment: 'Great agent! Fixed my code.',
        ),
        mockMarketplaceReview(
          reviewId: 'review-2',
          buyerName: 'user-2',
          rating: 4,
          comment: 'Good but could be faster.',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ListingDetail(
            listing: mockListing,
            reviews: mockReviews,
            onPurchase: (_) {},
            onBack: () {},
          ),
        ),
      );

      // Verify reviews section
      expect(find.text('Reviews'), findsOneWidget);

      // Verify review content
      expect(find.text('user-1'), findsOneWidget);
      expect(find.text('user-2'), findsOneWidget);
      expect(find.text('Great agent! Fixed my code.'), findsOneWidget);
      expect(find.text('Good but could be faster.'), findsOneWidget);

      // Verify star ratings are shown
      expect(find.byIcon(Icons.star), findsWidgets);
    });

    // ─── Test 3.3: Back button navigates back ───
    testWidgets('back button invokes onBack callback', (tester) async {
      final mockListing = mockAgentListing(listingId: 'listing-1');
      bool backPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ListingDetail(
            listing: mockListing,
            reviews: [],
            onPurchase: (_) {},
            onBack: () {
              backPressed = true;
            },
          ),
        ),
      );

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(backPressed, true);
    });

    // ─── Test 3.4: Empty reviews state ───
    testWidgets('shows "No reviews yet" when listing has no reviews',
        (tester) async {
      final mockListing = mockAgentListing(
        listingId: 'listing-1',
        reviewCount: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ListingDetail(
            listing: mockListing,
            reviews: [],
            onPurchase: (_) {},
            onBack: () {},
          ),
        ),
      );

      expect(find.text('No reviews yet'), findsOneWidget);
    });
  });

  group('Purchase Dialog', () {
    // ─── Test 4.1: Purchase dialog shows price breakdown ───
    testWidgets('displays price breakdown with commission',
        (tester) async {
      final mockListing = mockAgentListing(
        name: 'CodeMaster',
        priceGrim: 500,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PurchaseDialog(
                listing: mockListing,
                userBalance: 1000,
                onPurchaseResult: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify dialog title
      expect(find.text('Purchase CodeMaster?'), findsOneWidget);

      // Verify breakdown
      expect(find.text('Agent Price'), findsOneWidget);
      expect(find.text('500 ₲'), findsOneWidget);
      expect(find.text('Platform Commission (20%)'), findsOneWidget);
      expect(find.text('100 ₲'), findsOneWidget);
      expect(find.text('Seller Receives'), findsOneWidget);
      expect(find.text('400 ₲'), findsOneWidget);

      // Verify balance
      expect(find.text('Your Balance:'), findsOneWidget);

      // Verify buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm Purchase'), findsOneWidget);
    });

    // ─── Test 4.2: Successful purchase ───
    testWidgets('completes purchase successfully with sufficient funds',
        (tester) async {
      final mockListing = mockAgentListing(
        name: 'CodeMaster',
        priceGrim: 500,
      );

      PurchaseResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PurchaseDialog(
                listing: mockListing,
                userBalance: 1000,
                onPurchaseResult: (r) {
                  result = r;
                },
              ),
            ),
          ),
        ),
      );

      // Verify purchase button is enabled
      final confirmBtn = find.text('Confirm Purchase');
      expect(confirmBtn, findsOneWidget);
      final confirmButtonWidget = find.ancestor(
        of: confirmBtn,
        matching: find.byType(ElevatedButton),
      );
      expect(confirmButtonWidget, findsOneWidget);

      // Tap confirm
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify purchase succeeded
      expect(result, isNotNull);
      expect(result!.status, PurchaseStatus.success);
      expect(result!.transactionId, isNotNull);
    });

    // ─── Test 4.3: Insufficient funds error ───
    testWidgets('shows error when user has insufficient funds',
        (tester) async {
      final mockListing = mockAgentListing(
        name: 'CodeMaster',
        priceGrim: 500,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PurchaseDialog(
                listing: mockListing,
                userBalance: 200,
                onPurchaseResult: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify error message
      expect(
        find.text(
          'Insufficient funds (need 500 ₲, have 200 ₲)',
        ),
        findsOneWidget,
      );

      // Verify confirm button is disabled
      final confirmBtn = find.byType(ElevatedButton);
      expect(confirmBtn, findsOneWidget);
      // Button should be visually disabled (grayed out)
    });

    // ─── Test 4.4: Cancel purchase ───
    testWidgets('cancel button closes dialog without purchase',
        (tester) async {
      final mockListing = mockAgentListing(priceGrim: 500);
      bool purchased = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PurchaseDialog(
                listing: mockListing,
                userBalance: 1000,
                onPurchaseResult: (_) {
                  purchased = true;
                },
              ),
            ),
          ),
        ),
      );

      // Tap cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be closed and no purchase should occur
      expect(purchased, false);
    });
  });
}
