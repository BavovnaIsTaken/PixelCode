import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/screens/hub/hub_screen.dart';

void main() {
  group('hubOpenScale — never collapses content to invisible', () {
    test('value 0 (animation not started / ticker stuck) stays visible, not 0',
        () {
      final s = hubOpenScale(0.0, shuttingDown: false);
      expect(s, greaterThan(0.0),
          reason: 'a 0 scale squashes the whole UI to a black screen');
      expect(s, kHubOpenScaleFloor);
    });

    test('value 1 (animation complete) is full scale', () {
      expect(hubOpenScale(1.0, shuttingDown: false), 1.0);
    });

    test('shutdown is always full scale regardless of value', () {
      expect(hubOpenScale(0.0, shuttingDown: true), 1.0);
      expect(hubOpenScale(0.5, shuttingDown: true), 1.0);
    });

    test('the BLACK-SCREEN invariant: every value in [0,1] is >= floor (>0)',
        () {
      for (var i = 0; i <= 100; i++) {
        final s = hubOpenScale(i / 100, shuttingDown: false);
        expect(s, greaterThanOrEqualTo(kHubOpenScaleFloor));
        expect(s, lessThanOrEqualTo(1.0));
      }
    });

    test('out-of-range values are clamped (defensive)', () {
      expect(hubOpenScale(-1.0, shuttingDown: false), kHubOpenScaleFloor);
      expect(hubOpenScale(2.0, shuttingDown: false), 1.0);
    });

    test('monotonic: scale grows with the animation value', () {
      expect(hubOpenScale(0.25, shuttingDown: false),
          lessThan(hubOpenScale(0.75, shuttingDown: false)));
    });

    test('floor is high enough to read as visible content, not a sliver', () {
      // A floor near 1.0 means even the worst stuck case is barely letterboxed,
      // never the reported solid-black screen.
      expect(kHubOpenScaleFloor, greaterThanOrEqualTo(0.9));
    });
  });
}
