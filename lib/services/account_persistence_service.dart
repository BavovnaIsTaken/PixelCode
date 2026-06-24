/// Persistence for the active [AccountProfile].
///
/// The profile is tiny and flat → SharedPreferences. The team's actual data
/// (roster/economy) is the GameState, already stored globally on the client and
/// account-scoped on the server; this only persists *which* account is active
/// and its display name.
///
/// Shaped as a list-ready single-active pair (mirroring SessionProfile) so
/// multi-account can grow into it without a storage migration.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_profile.dart';

class AccountPersistenceService {
  static const _kActiveAccount = 'active_account_profile';

  /// Load the persisted active account, or `null` if none has been saved yet.
  static AccountProfile? load(SharedPreferences prefs) {
    final raw = prefs.getString(_kActiveAccount);
    if (raw == null) return null;
    try {
      return AccountProfile.decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(SharedPreferences prefs, AccountProfile account) async {
    await prefs.setString(_kActiveAccount, account.encode());
  }

  /// Return the active account, creating and persisting the default local
  /// account on first run. The id is stable across launches (the default
  /// constant), so the team resolves consistently every time.
  static Future<AccountProfile> ensureLocalAccount(SharedPreferences prefs) async {
    final existing = load(prefs);
    if (existing != null) return existing;
    final account = AccountProfile.local();
    await save(prefs, account);
    return account;
  }
}
