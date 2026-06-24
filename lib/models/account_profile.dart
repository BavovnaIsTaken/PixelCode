/// The user's portable team identity.
///
/// The team — roster, levels, skills, learned traits, currency, office — is
/// tied to the ACCOUNT, not to any project. Switching projects keeps the same
/// team; the account is the thing the user "takes with them".
///
/// Multi-account is not built yet. There is a single account with a well-known
/// constant id ([kDefaultAccountId]) so every device the user signs in on
/// resolves to the *same* team (the server is single-tenant; a constant id
/// keeps cross-device sync intact). A random per-device id would split the team
/// in two — so the default id is deliberately NOT generated. Real per-user ids
/// (and a server-authoritative reconciliation) arrive with multi-account; this
/// model already carries an explicit `id` so that lands as config, not a
/// rewrite.
library;

import 'dart:convert';

/// Well-known id of the single default account. A constant shared by every
/// device — see the class doc for why it must not be randomized.
const String kDefaultAccountId = 'local';

/// Default human label for the local account.
const String kDefaultAccountName = 'Моя команда';

class AccountProfile {
  /// Stable account identifier sent to the server to scope team storage.
  final String id;

  /// Human-facing label (editable). Cosmetic — never used for scoping.
  final String name;

  const AccountProfile({required this.id, required this.name});

  /// The single local account every device shares until multi-account lands.
  factory AccountProfile.local([String name = kDefaultAccountName]) =>
      AccountProfile(id: kDefaultAccountId, name: name);

  AccountProfile copyWith({String? name}) =>
      AccountProfile(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        id: (json['id'] as String?)?.trim().isNotEmpty == true
            ? json['id'] as String
            : kDefaultAccountId,
        name: json['name'] as String? ?? kDefaultAccountName,
      );

  String encode() => jsonEncode(toJson());

  factory AccountProfile.decode(String raw) =>
      AccountProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountProfile && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'AccountProfile(id: $id, name: $name)';
}
