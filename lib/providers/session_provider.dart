// lib/providers/session_provider.dart

/// Manages session profiles — CRUD, persistence, active profile switching.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_profile.dart';
import 'settings_provider.dart';

const _keyProfiles = 'session_profiles';
const _keyActiveProfileId = 'session_active_profile_id';

class SessionState {
  final List<SessionProfile> profiles;
  final String? activeProfileId;

  const SessionState({this.profiles = const [], this.activeProfileId});

  SessionProfile? get activeProfile {
    if (activeProfileId == null) return null;
    final idx = profiles.indexWhere((p) => p.id == activeProfileId);
    return idx >= 0 ? profiles[idx] : null;
  }

  SessionState copyWith({
    List<SessionProfile>? profiles,
    String? Function()? activeProfileId,
  }) =>
      SessionState(
        profiles: profiles ?? this.profiles,
        activeProfileId: activeProfileId != null
            ? activeProfileId()
            : this.activeProfileId,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final prefs = ref.read(sharedPrefsProvider);
    return _load(prefs);
  }

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  SessionState _load(SharedPreferences prefs) {
    final raw = prefs.getString(_keyProfiles);
    final profiles =
        raw != null ? SessionProfile.decodeList(raw) : <SessionProfile>[];
    final activeId = prefs.getString(_keyActiveProfileId);
    return SessionState(profiles: profiles, activeProfileId: activeId);
  }

  Future<void> _save() async {
    await _prefs.setString(
      _keyProfiles,
      SessionProfile.encodeList(state.profiles),
    );
    final activeId = state.activeProfileId;
    if (activeId != null) {
      await _prefs.setString(_keyActiveProfileId, activeId);
    } else {
      await _prefs.remove(_keyActiveProfileId);
    }
  }

  Future<void> addProfile(SessionProfile profile) async {
    state = state.copyWith(profiles: [...state.profiles, profile]);
    // Auto-activate if it's the first profile
    if (state.profiles.length == 1) {
      state = state.copyWith(activeProfileId: () => profile.id);
    }
    await _save();
  }

  Future<void> updateProfile(SessionProfile profile) async {
    state = state.copyWith(
      profiles: [
        for (final p in state.profiles)
          if (p.id == profile.id) profile else p,
      ],
    );
    await _save();
  }

  Future<void> deleteProfile(String id) async {
    state = state.copyWith(
      profiles: state.profiles.where((p) => p.id != id).toList(),
      activeProfileId: () =>
          state.activeProfileId == id ? null : state.activeProfileId,
    );
    await _save();
  }

  Future<void> setActive(String id) async {
    state = state.copyWith(activeProfileId: () => id);
    await _save();
  }

  /// Create a default "Local" session on desktop if no profiles exist.
  Future<void> ensureDefaultDesktopProfile() async {
    if (state.profiles.isNotEmpty) return;
    final profile = SessionProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Локально',
      host: 'localhost',
    );
    await addProfile(profile);
  }

  /// Migrate from the old single-URL setting if no profiles exist yet.
  Future<void> migrateFromLegacy() async {
    if (state.profiles.isNotEmpty) return;
    final prefs = _prefs;
    final oldUrl = prefs.getString('settings_server_url');
    if (oldUrl == null || oldUrl.isEmpty) return;

    // Parse ws://host:port
    final uri = Uri.tryParse(oldUrl);
    if (uri == null) return;

    final profile = SessionProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Default',
      host: uri.host,
      port: uri.port > 0 ? uri.port : 9720,
    );
    await addProfile(profile);
    await prefs.remove('settings_server_url');
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
