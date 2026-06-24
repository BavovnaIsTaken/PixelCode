/// Active-account state — the portable team identity.
///
/// Holds the [AccountProfile] whose team this client operates as, persists it,
/// and declares it to the server (`set_account`) on every (re)connect so the
/// server scopes the team to the account rather than the project. Today there
/// is a single default account, so the declaration is effectively inert — but
/// it is the seam multi-account and "take my team to another machine" grow
/// into.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account_profile.dart';
import '../services/account_persistence_service.dart';
import 'settings_provider.dart';
import 'ws_provider.dart';

class AccountNotifier extends Notifier<AccountProfile> {
  StreamSubscription<bool>? _connSub;

  @override
  AccountProfile build() {
    final prefs = ref.read(sharedPrefsProvider);
    final loaded = AccountPersistenceService.load(prefs);
    final account = loaded ?? AccountProfile.local();
    // First run: persist the default so the id is stable from here on.
    if (loaded == null) {
      unawaited(AccountPersistenceService.save(prefs, account));
    }

    // Declare our account on every (re)connect. The connectionStatus stream
    // yields the current value immediately, so this also fires if we are
    // already connected when the provider is first built.
    final ws = ref.watch(wsServiceProvider);
    _connSub?.cancel();
    _connSub = ws.connectionStatus.listen((connected) {
      if (connected) ws.setAccount(state.id);
    });
    ref.onDispose(() => _connSub?.cancel());

    return account;
  }

  /// Rename the active account (cosmetic — the id, and thus the team scope, is
  /// unchanged). Persisted immediately.
  void rename(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == state.name) return;
    state = state.copyWith(name: trimmed);
    unawaited(
      AccountPersistenceService.save(ref.read(sharedPrefsProvider), state),
    );
  }
}

final accountProvider =
    NotifierProvider<AccountNotifier, AccountProfile>(AccountNotifier.new);

/// The active account id — what scopes the team. Stable (`local`) until
/// multi-account lands. Kept as its own provider so consumers that only need
/// the scope key don't rebuild when the cosmetic name changes.
final accountIdProvider =
    Provider<String>((ref) => ref.watch(accountProvider).id);
