/// Persists the office canvas zoom + pan — the [InteractiveViewer] transform
/// driven by [AgentCanvas]'s TransformationController.
///
/// Two things destroy that controller's state, and this provider survives both:
///   1. Switching hub tabs. The hub keys each view with `ValueKey(_viewIndex)`,
///      so leaving and re-entering the office disposes and recreates
///      `AgentCanvas` — and with it a fresh, un-zoomed TransformationController.
///   2. Restarting the app. The in-memory transform is mirrored to
///      SharedPreferences so the office reopens exactly where the player left it.
///
/// Only the normal (non-build) office view is persisted. Build mode resets the
/// transform to identity on entry and restores this saved view on exit, so a
/// build-mode pan never leaks into the persisted value.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

const _keyOfficeView = 'office_view_transform';

/// Kept in sync with the InteractiveViewer min/max scale in [AgentCanvas].
const double _kMinScale = 1.0;
const double _kMaxScale = 3.0;

class OfficeViewNotifier extends Notifier<Matrix4> {
  @override
  Matrix4 build() {
    final raw = ref.read(sharedPrefsProvider).getString(_keyOfficeView);
    return _decode(raw);
  }

  /// Persist the current canvas transform. Pass [Matrix4.identity] (or any
  /// matrix at scale ≤ 1) to clear a saved zoom.
  void save(Matrix4 transform) {
    final normalized = _normalize(transform);
    if (normalized == state) return;
    state = normalized;
    final prefs = ref.read(sharedPrefsProvider);
    if (normalized.isIdentity()) {
      prefs.remove(_keyOfficeView);
    } else {
      prefs.setString(_keyOfficeView, _encode(normalized));
    }
  }

  void reset() => save(Matrix4.identity());

  /// Drop the translation when effectively un-zoomed, and clamp the scale into
  /// the viewer's allowed range so a corrupt or stale value can never strand
  /// the office off-screen.
  static Matrix4 _normalize(Matrix4 transform) {
    final scale =
        transform.getMaxScaleOnAxis().clamp(_kMinScale, _kMaxScale).toDouble();
    if (scale <= _kMinScale + 0.01) return Matrix4.identity();
    final t = transform.getTranslation();
    return _compose(scale, t.x, t.y);
  }

  /// Builds a uniform-scale + 2D-translation matrix directly in column-major
  /// order — equivalent to translate(tx,ty)·scale(s) without the deprecated
  /// Matrix4 mutators. Matches the shape of an [InteractiveViewer] transform.
  static Matrix4 _compose(double scale, double tx, double ty) => Matrix4(
        scale, 0, 0, 0, //
        0, scale, 0, 0, //
        0, 0, scale, 0, //
        tx, ty, 0, 1, //
      );

  static String _encode(Matrix4 m) {
    final t = m.getTranslation();
    return '${m.getMaxScaleOnAxis()},${t.x},${t.y}';
  }

  static Matrix4 _decode(String? raw) {
    if (raw == null) return Matrix4.identity();
    final parts = raw.split(',');
    if (parts.length != 3) return Matrix4.identity();
    final scale = double.tryParse(parts[0]);
    final tx = double.tryParse(parts[1]);
    final ty = double.tryParse(parts[2]);
    if (scale == null || tx == null || ty == null) return Matrix4.identity();
    return _normalize(_compose(scale, tx, ty));
  }
}

final officeViewProvider =
    NotifierProvider<OfficeViewNotifier, Matrix4>(OfficeViewNotifier.new);
