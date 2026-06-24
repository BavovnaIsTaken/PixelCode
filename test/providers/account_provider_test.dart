import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/account_profile.dart';
import 'package:pixelcode/providers/account_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/services/account_persistence_service.dart';

Future<ProviderContainer> _container([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('accountProvider', () {
    test('defaults to the local account and persists it on first build',
        () async {
      final c = await _container();
      final account = c.read(accountProvider);
      expect(account.id, kDefaultAccountId);

      // Persisted as a side effect of the first build.
      final prefs = c.read(sharedPrefsProvider);
      expect(AccountPersistenceService.load(prefs)?.id, kDefaultAccountId);
    });

    test('accountIdProvider exposes the scope key', () async {
      final c = await _container();
      expect(c.read(accountIdProvider), 'local');
    });

    test('restores a previously persisted account', () async {
      final c = await _container({
        'active_account_profile':
            const AccountProfile(id: 'local', name: 'Команда мрії').encode(),
      });
      expect(c.read(accountProvider).name, 'Команда мрії');
    });

    test('rename updates state and persists, leaving the id (scope) intact',
        () async {
      final c = await _container();
      c.read(accountProvider.notifier).rename('Нова назва');

      expect(c.read(accountProvider).name, 'Нова назва');
      expect(c.read(accountIdProvider), 'local', reason: 'scope id must not change');

      final prefs = c.read(sharedPrefsProvider);
      expect(AccountPersistenceService.load(prefs)?.name, 'Нова назва');
    });

    test('rename ignores empty / unchanged names', () async {
      final c = await _container();
      final before = c.read(accountProvider);
      c.read(accountProvider.notifier).rename('   ');
      c.read(accountProvider.notifier).rename(before.name);
      expect(c.read(accountProvider), before);
    });
  });
}
