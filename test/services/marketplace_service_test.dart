import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/marketplace_service.dart';

void main() {
  group('PurchaseStatus enum', () {
    test('exposes the four expected statuses', () {
      expect(PurchaseStatus.values.length, 4);
      expect(PurchaseStatus.values, containsAll(<PurchaseStatus>[
        PurchaseStatus.success,
        PurchaseStatus.insufficientFunds,
        PurchaseStatus.networkError,
        PurchaseStatus.unknown,
      ]));
    });

    test('success is the first variant', () {
      expect(PurchaseStatus.values.first, PurchaseStatus.success);
    });
  });

  group('PurchaseResult', () {
    test('carries status only when message and transactionId are omitted', () {
      final r = PurchaseResult(status: PurchaseStatus.success);
      expect(r.status, PurchaseStatus.success);
      expect(r.message, isNull);
      expect(r.transactionId, isNull);
    });

    test('carries message and transactionId when provided', () {
      final r = PurchaseResult(
        status: PurchaseStatus.success,
        message: 'ok',
        transactionId: 'tx_42',
      );
      expect(r.message, 'ok');
      expect(r.transactionId, 'tx_42');
    });

    test('failure variants typically carry a human message', () {
      final r = PurchaseResult(
        status: PurchaseStatus.insufficientFunds,
        message: 'Not enough Grim',
      );
      expect(r.status, PurchaseStatus.insufficientFunds);
      expect(r.message, 'Not enough Grim');
      expect(r.transactionId, isNull);
    });
  });

  group('SellerStats', () {
    test('stores all four fields verbatim', () {
      final s = SellerStats(
        sellerId: 's1',
        totalSales: 42,
        totalRevenue: 12000,
        averageRating: 4.7,
      );
      expect(s.sellerId, 's1');
      expect(s.totalSales, 42);
      expect(s.totalRevenue, 12000);
      expect(s.averageRating, 4.7);
    });

    test('zero-value seller is representable (no sales yet)', () {
      final s = SellerStats(
        sellerId: 'new',
        totalSales: 0,
        totalRevenue: 0,
        averageRating: 0.0,
      );
      expect(s.totalSales, 0);
      expect(s.totalRevenue, 0);
      expect(s.averageRating, 0.0);
    });
  });
}
