import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/utils/grymni_format.dart';

void main() {
  group('formatGrymni', () {
    test('plain integers under 1000', () {
      expect(formatGrymni(0), '0');
      expect(formatGrymni(7), '7');
      expect(formatGrymni(999), '999');
    });

    test('K-range with one decimal when not exact', () {
      expect(formatGrymni(1000), '1K');
      expect(formatGrymni(1500), '1.5K');
      expect(formatGrymni(2767), '2.8K');
      expect(formatGrymni(999_900), '999.9K');
    });

    test('promotes K→M before "1000.0K" rounding artifact appears', () {
      expect(formatGrymni(999_499), '999.5K');
      expect(formatGrymni(999_949), '999.9K');
      expect(formatGrymni(999_950), '1.0M');
      expect(formatGrymni(1_000_000), '1M');
      expect(formatGrymni(1_100_000), '1.1M');
      expect(formatGrymni(2_767_300), '2.8M');
    });

    test('promotes M→B at the rounding boundary', () {
      expect(formatGrymni(999_000_000), '999M');
      expect(formatGrymni(999_950_000), '1.0B');
      expect(formatGrymni(1_000_000_000), '1B');
      expect(formatGrymni(1_500_000_000), '1.5B');
    });

    test('handles negative values symmetrically', () {
      expect(formatGrymni(-1500), '-1.5K');
      expect(formatGrymni(-2_767_300), '-2.8M');
    });
  });
}
