import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_listing.dart';

AgentListing _baseListing() => AgentListing(
      listingId: 'L1',
      agentId: 'A1',
      name: 'Andriy',
      role: 'coder',
      priceGrim: 1500,
      qualityScore: 82.5,
      averageRating: 4.5,
      reviewCount: 12,
      purchaseCount: 7,
      sellerName: 'studio_one',
      description: 'Frontend specialist',
      skillSpecializations: const ['frontend', 'ui'],
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 15),
    );

void main() {
  group('AgentListing construction', () {
    test('stores every field verbatim, including optional updatedAt', () {
      final l = _baseListing();
      expect(l.listingId, 'L1');
      expect(l.agentId, 'A1');
      expect(l.name, 'Andriy');
      expect(l.role, 'coder');
      expect(l.priceGrim, 1500);
      expect(l.qualityScore, 82.5);
      expect(l.averageRating, 4.5);
      expect(l.reviewCount, 12);
      expect(l.purchaseCount, 7);
      expect(l.sellerName, 'studio_one');
      expect(l.description, 'Frontend specialist');
      expect(l.skillSpecializations, ['frontend', 'ui']);
      expect(l.createdAt, DateTime.utc(2026, 4, 1));
      expect(l.updatedAt, DateTime.utc(2026, 4, 15));
    });

    test('updatedAt defaults to null when omitted', () {
      final l = AgentListing(
        listingId: 'L1',
        agentId: 'A1',
        name: 'A',
        role: 'tester',
        priceGrim: 500,
        qualityScore: 50.0,
        averageRating: 3.0,
        reviewCount: 0,
        purchaseCount: 0,
        sellerName: 's',
        description: 'd',
        skillSpecializations: const [],
        createdAt: DateTime(2026),
      );
      expect(l.updatedAt, isNull);
    });
  });

  group('AgentListing.copyWith', () {
    test('without overrides matches every original field', () {
      final l = _baseListing();
      final clone = l.copyWith();

      expect(clone.listingId, l.listingId);
      expect(clone.agentId, l.agentId);
      expect(clone.name, l.name);
      expect(clone.role, l.role);
      expect(clone.priceGrim, l.priceGrim);
      expect(clone.qualityScore, l.qualityScore);
      expect(clone.averageRating, l.averageRating);
      expect(clone.reviewCount, l.reviewCount);
      expect(clone.purchaseCount, l.purchaseCount);
      expect(clone.sellerName, l.sellerName);
      expect(clone.description, l.description);
      expect(clone.skillSpecializations, l.skillSpecializations);
      expect(clone.createdAt, l.createdAt);
      expect(clone.updatedAt, l.updatedAt);
      expect(identical(clone, l), isFalse);
    });

    test('overrides only the fields provided', () {
      final l = _baseListing();
      final updated = l.copyWith(
        priceGrim: 2000,
        averageRating: 4.9,
        purchaseCount: 8,
      );

      expect(updated.priceGrim, 2000);
      expect(updated.averageRating, 4.9);
      expect(updated.purchaseCount, 8);
      // Untouched
      expect(updated.listingId, l.listingId);
      expect(updated.role, l.role);
      expect(updated.qualityScore, l.qualityScore);
      expect(updated.skillSpecializations, l.skillSpecializations);
    });

    test('can replace skillSpecializations with empty list', () {
      final l = _baseListing();
      final updated = l.copyWith(skillSpecializations: const []);
      expect(updated.skillSpecializations, isEmpty);
      // Original is unmodified
      expect(l.skillSpecializations, isNotEmpty);
    });

    test('can override every field at once', () {
      final l = _baseListing();
      final newCreated = DateTime.utc(2027);
      final newUpdated = DateTime.utc(2027, 1, 2);
      final updated = l.copyWith(
        listingId: 'L2',
        agentId: 'A2',
        name: 'Olya',
        role: 'tester',
        priceGrim: 999,
        qualityScore: 60.0,
        averageRating: 3.5,
        reviewCount: 100,
        purchaseCount: 50,
        sellerName: 'studio_two',
        description: 'QA specialist',
        skillSpecializations: const ['testing'],
        createdAt: newCreated,
        updatedAt: newUpdated,
      );

      expect(updated.listingId, 'L2');
      expect(updated.agentId, 'A2');
      expect(updated.name, 'Olya');
      expect(updated.role, 'tester');
      expect(updated.priceGrim, 999);
      expect(updated.qualityScore, 60.0);
      expect(updated.averageRating, 3.5);
      expect(updated.reviewCount, 100);
      expect(updated.purchaseCount, 50);
      expect(updated.sellerName, 'studio_two');
      expect(updated.description, 'QA specialist');
      expect(updated.skillSpecializations, ['testing']);
      expect(updated.createdAt, newCreated);
      expect(updated.updatedAt, newUpdated);
    });

    // copyWith uses `?? this.updatedAt`, so null cannot be re-introduced once
    // the original updatedAt is non-null. This test pins that behavior.
    test('cannot null-out updatedAt via copyWith (?? semantics)', () {
      final l = _baseListing();
      final updated = l.copyWith(updatedAt: null);
      expect(updated.updatedAt, l.updatedAt);
    });
  });
}
