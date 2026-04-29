/// Tracks the [FacilitatorStyle] active for the current project. Powers
/// the lexicon-swap layer (ROADMAP §B Q3 2026) — kanban labels, activity
/// bubbles, and ceremony copy read from this single source of truth.
///
/// Persistence is per-project: style ids live under
/// `facilitator_style_id_<projectPath>` in SharedPreferences, so each
/// project keeps its chosen style across restarts independently.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/facilitator_style.dart';
import '../services/facilitator_style_loader.dart';
import 'project_provider.dart';
import 'settings_provider.dart';

class ActiveFacilitatorStyleNotifier
    extends AsyncNotifier<FacilitatorStyle?> {
  static String prefsKeyFor(String projectPath) =>
      'facilitator_style_id_$projectPath';

  /// Optional override for tests — bypasses asset-bundle loading.
  AssetLoader? _assetLoaderOverride;

  @override
  Future<FacilitatorStyle?> build() async {
    final project = ref.watch(projectProvider);
    if (project == null) return null;

    final prefs = ref.read(sharedPrefsProvider);
    final id = prefs.getString(prefsKeyFor(project.path));
    if (id == null || id.isEmpty) return null;

    try {
      final override = _assetLoaderOverride;
      return await (override == null
          ? FacilitatorStyleLoader.loadById(id)
          : FacilitatorStyleLoader.loadById(id, loader: override));
    } catch (_) {
      // A persisted id may point at an asset that no longer ships
      // (e.g. style was renamed). Fall back to "no style" rather than
      // surfacing the error — kanban will show canonical labels.
      return null;
    }
  }

  /// Persist the chosen style id and update state synchronously.
  Future<void> setStyle(FacilitatorStyle style) async {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(prefsKeyFor(project.path), style.id);
    state = AsyncData(style);
  }

  /// Clear the active style for the current project.
  Future<void> clear() async {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(prefsKeyFor(project.path));
    state = const AsyncData(null);
  }

  /// Test seam — overrides the asset loader used during [build].
  /// Call before reading the provider.
  void debugSetAssetLoader(AssetLoader loader) {
    _assetLoaderOverride = loader;
  }
}

final activeFacilitatorStyleProvider =
    AsyncNotifierProvider<ActiveFacilitatorStyleNotifier, FacilitatorStyle?>(
  ActiveFacilitatorStyleNotifier.new,
);
