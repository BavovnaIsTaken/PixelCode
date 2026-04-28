import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/listing_detail.dart';
import 'test_fixtures.dart';

void main() {
  group('ListingDetail', () {
    testWidgets('renders listing name in app bar', (tester) async {
      final listing = mockAgentListing(name: 'SuperCoder');
      await tester.pumpWidget(MaterialApp(
        home: ListingDetail(
          listing: listing,
          reviews: const [],
          onPurchase: (_) {},
          onBack: () {},
        ),
      ));
      expect(find.text('SuperCoder'), findsWidgets);
    });

    testWidgets('tapping FAB calls onPurchase with listing id', (tester) async {
      final listing = mockAgentListing(listingId: 'buy-me', name: 'TestBot');
      String? purchasedId;
      await tester.pumpWidget(MaterialApp(
        home: ListingDetail(
          listing: listing,
          reviews: const [],
          onPurchase: (id) => purchasedId = id,
          onBack: () {},
        ),
      ));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(purchasedId, 'buy-me');
    });

    testWidgets('tapping back button calls onBack', (tester) async {
      final listing = mockAgentListing(name: 'BackBot');
      bool backCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: ListingDetail(
          listing: listing,
          reviews: const [],
          onPurchase: (_) {},
          onBack: () => backCalled = true,
        ),
      ));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(backCalled, isTrue);
    });
  });
}
