import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/marketplace_review.dart';

MarketplaceReview _baseReview() => MarketplaceReview(
      reviewId: 'r1',
      listingId: 'L1',
      buyerName: 'anon-42',
      rating: 4,
      comment: 'solid agent',
      createdAt: DateTime.utc(2026, 5, 1, 10, 0),
    );

void main() {
  group('MarketplaceReview construction', () {
    test('stores all fields verbatim', () {
      final r = _baseReview();
      expect(r.reviewId, 'r1');
      expect(r.listingId, 'L1');
      expect(r.buyerName, 'anon-42');
      expect(r.rating, 4);
      expect(r.comment, 'solid agent');
      expect(r.createdAt, DateTime.utc(2026, 5, 1, 10, 0));
    });
  });

  group('MarketplaceReview.copyWith', () {
    test('returns identical contents when no overrides given', () {
      final r = _baseReview();
      final clone = r.copyWith();

      expect(clone.reviewId, r.reviewId);
      expect(clone.listingId, r.listingId);
      expect(clone.buyerName, r.buyerName);
      expect(clone.rating, r.rating);
      expect(clone.comment, r.comment);
      expect(clone.createdAt, r.createdAt);
      expect(identical(clone, r), isFalse);
    });

    test('overrides only the fields provided', () {
      final r = _baseReview();
      final updated = r.copyWith(rating: 5, comment: 'amazing');

      expect(updated.rating, 5);
      expect(updated.comment, 'amazing');
      expect(updated.reviewId, r.reviewId);
      expect(updated.listingId, r.listingId);
      expect(updated.buyerName, r.buyerName);
      expect(updated.createdAt, r.createdAt);
    });

    test('can override every field independently', () {
      final r = _baseReview();
      final newDate = DateTime.utc(2026, 6, 1);
      final updated = r.copyWith(
        reviewId: 'r2',
        listingId: 'L2',
        buyerName: 'anon-7',
        rating: 1,
        comment: 'not great',
        createdAt: newDate,
      );

      expect(updated.reviewId, 'r2');
      expect(updated.listingId, 'L2');
      expect(updated.buyerName, 'anon-7');
      expect(updated.rating, 1);
      expect(updated.comment, 'not great');
      expect(updated.createdAt, newDate);
    });

    test('preserves rating bounds set by caller (model itself does not clamp)',
        () {
      final r = _baseReview();
      expect(r.copyWith(rating: 0).rating, 0);
      expect(r.copyWith(rating: 6).rating, 6);
    });
  });
}
