import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/account_profile.dart';

void main() {
  group('AccountProfile', () {
    test('local() uses the shared default id and name', () {
      final a = AccountProfile.local();
      expect(a.id, kDefaultAccountId);
      expect(a.id, 'local');
      expect(a.name, kDefaultAccountName);
    });

    test('toJson / fromJson round-trip', () {
      const a = AccountProfile(id: 'local', name: 'Моя команда');
      final back = AccountProfile.fromJson(a.toJson());
      expect(back, a);
    });

    test('encode / decode round-trip', () {
      const a = AccountProfile(id: 'team-42', name: 'Найкраща команда');
      expect(AccountProfile.decode(a.encode()), a);
    });

    test('fromJson defaults a missing/empty id to the default account', () {
      expect(AccountProfile.fromJson({'name': 'x'}).id, kDefaultAccountId);
      expect(AccountProfile.fromJson({'id': '', 'name': 'x'}).id, kDefaultAccountId);
      expect(AccountProfile.fromJson({'id': '  ', 'name': 'x'}).id, kDefaultAccountId);
    });

    test('fromJson defaults a missing name', () {
      expect(AccountProfile.fromJson({'id': 'local'}).name, kDefaultAccountName);
    });

    test('copyWith changes the name but never the id', () {
      const a = AccountProfile(id: 'local', name: 'Old');
      final b = a.copyWith(name: 'New');
      expect(b.id, 'local');
      expect(b.name, 'New');
    });

    test('equality is by id + name', () {
      expect(
        const AccountProfile(id: 'local', name: 'A'),
        const AccountProfile(id: 'local', name: 'A'),
      );
      expect(
        const AccountProfile(id: 'local', name: 'A'),
        isNot(const AccountProfile(id: 'local', name: 'B')),
      );
    });
  });
}
