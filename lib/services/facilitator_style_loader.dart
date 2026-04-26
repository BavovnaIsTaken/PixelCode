/// Loads `FacilitatorStyle` presets from bundled assets.
///
/// MVP defaults (Q3 2026): `game_master`, `marina`, `drill_sergeant`.
/// Marketplace styles (Q4 2026, Section E) will be loaded the same way
/// after being downloaded into a managed-styles directory — same shape,
/// different `AssetLoader` implementation.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/facilitator_style.dart';

/// Bundled style ids in MVP. Order matters — first id is the default
/// shown atop the picker.
const List<String> defaultStyleIds = [
  'game_master',
  'marina',
  'drill_sergeant',
];

/// Pluggable string loader so tests can inject in-memory JSON without
/// touching the asset bundle.
typedef AssetLoader = Future<String> Function(String key);

Future<String> _bundleLoader(String key) => rootBundle.loadString(key);

class FacilitatorStyleLoader {
  static const _assetPathPrefix = 'assets/facilitators/';

  /// Load a single style by id from bundled assets.
  static Future<FacilitatorStyle> loadById(
    String id, {
    AssetLoader loader = _bundleLoader,
  }) async {
    final raw = await loader('$_assetPathPrefix$id.json');
    return FacilitatorStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Load every default MVP style. Order matches `defaultStyleIds`.
  static Future<List<FacilitatorStyle>> loadDefaults({
    AssetLoader loader = _bundleLoader,
  }) async {
    final futures = defaultStyleIds.map((id) => loadById(id, loader: loader));
    return Future.wait(futures);
  }
}
