/// Tests for OfficeViewProvider — office zoom/pan persistence via
/// SharedPreferences, plus scale clamping and identity normalization.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/office_view_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

ProviderContainer _makeContainer(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

/// Builds the same shape of transform an [InteractiveViewer] produces:
/// uniform scale on the diagonal, 2D translation in the last column.
Matrix4 _transform(double scale, double tx, double ty) => Matrix4(
      scale, 0, 0, 0, //
      0, scale, 0, 0, //
      0, 0, scale, 0, //
      tx, ty, 0, 1, //
    );

void main() {
  group('OfficeViewNotifier initial state', () {
    test('defaults to identity when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      expect(container.read(officeViewProvider), Matrix4.identity());
    });

    test('restores a persisted zoom + pan on rebuild', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      container
          .read(officeViewProvider.notifier)
          .save(_transform(2.0, -40, -30));
      container.dispose();

      // A fresh container (simulating an app restart / tab re-entry) reads the
      // same prefs and must reconstruct the identical transform.
      final container2 = _makeContainer(prefs);
      addTearDown(container2.dispose);

      final restored = container2.read(officeViewProvider);
      expect(restored.getMaxScaleOnAxis(), closeTo(2.0, 1e-9));
      expect(restored.getTranslation().x, closeTo(-40, 1e-9));
      expect(restored.getTranslation().y, closeTo(-30, 1e-9));
    });
  });

  group('OfficeViewNotifier.save', () {
    test('normalizes a near-identity scale to identity (drops stale pan)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      // Scale ~1 but with a leftover translation — should collapse to identity.
      container.read(officeViewProvider.notifier).save(_transform(1.0, 50, 50));

      expect(container.read(officeViewProvider), Matrix4.identity());
      // Identity is cleared from prefs, not written.
      expect(prefs.getString('office_view_transform'), null);
    });

    test('clamps an over-scale value into the viewer range', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      container.read(officeViewProvider.notifier).save(_transform(9.0, 0, 0));

      expect(
        container.read(officeViewProvider).getMaxScaleOnAxis(),
        closeTo(3.0, 1e-9),
      );
    });

    test('reset() clears a previously saved zoom', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      final notifier = container.read(officeViewProvider.notifier);
      notifier.save(_transform(2.5, 10, 10));
      expect(prefs.getString('office_view_transform'), isNotNull);

      notifier.reset();
      expect(container.read(officeViewProvider), Matrix4.identity());
      expect(prefs.getString('office_view_transform'), null);
    });
  });

  group('OfficeViewNotifier corrupt-storage recovery', () {
    test('falls back to identity on malformed stored value', () async {
      SharedPreferences.setMockInitialValues(
        {'office_view_transform': 'not,a,matrix,really'},
      );
      final prefs = await SharedPreferences.getInstance();
      final container = _makeContainer(prefs);
      addTearDown(container.dispose);

      expect(container.read(officeViewProvider), Matrix4.identity());
    });
  });
}
