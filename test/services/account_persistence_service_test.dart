import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/account_profile.dart';
import 'package:pixelcode/services/account_persistence_service.dart';

Future<SharedPreferences> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

void main() {
  group('AccountPersistenceService', () {
    test('load returns null when nothing is persisted', () async {
      final prefs = await _prefs();
      expect(AccountPersistenceService.load(prefs), isNull);
    });

    test('ensureLocalAccount creates + persists the default account on first run',
        () async {
      final prefs = await _prefs();
      final account = await AccountPersistenceService.ensureLocalAccount(prefs);
      expect(account.id, kDefaultAccountId);
      // Persisted, so a subsequent load returns it.
      expect(AccountPersistenceService.load(prefs), account);
    });

    test('ensureLocalAccount is idempotent and stable across calls', () async {
      final prefs = await _prefs();
      final first = await AccountPersistenceService.ensureLocalAccount(prefs);
      final second = await AccountPersistenceService.ensureLocalAccount(prefs);
      // Same stable id — the team resolves consistently every launch.
      expect(second.id, first.id);
      expect(second, first);
    });

    test('ensureLocalAccount does not clobber a renamed account', () async {
      final prefs = await _prefs();
      await AccountPersistenceService.save(
        prefs,
        const AccountProfile(id: 'local', name: 'Моя суперкоманда'),
      );
      final account = await AccountPersistenceService.ensureLocalAccount(prefs);
      expect(account.name, 'Моя суперкоманда');
      expect(account.id, 'local');
    });

    test('save / load round-trips a custom account', () async {
      final prefs = await _prefs();
      const a = AccountProfile(id: 'team-42', name: 'Альфа');
      await AccountPersistenceService.save(prefs, a);
      expect(AccountPersistenceService.load(prefs), a);
    });

    test('load returns null on corrupt stored value', () async {
      final prefs = await _prefs({'active_account_profile': 'not json'});
      expect(AccountPersistenceService.load(prefs), isNull);
    });
  });
}
