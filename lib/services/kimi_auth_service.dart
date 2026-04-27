/// Manages Kimi K2.6 (Moonshot AI) API key storage via SharedPreferences.
library;

import 'package:shared_preferences/shared_preferences.dart';

const _kKimiApiKey = 'kimi_api_key';

class KimiAuthStatus {
  final bool linked;
  final String? apiKey;
  final String? maskedKey;

  const KimiAuthStatus({required this.linked, this.apiKey, this.maskedKey});

  static const notLinked = KimiAuthStatus(linked: false);
}

class KimiAuthService {
  static Future<KimiAuthStatus> checkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kKimiApiKey);
    if (key == null || key.isEmpty) return KimiAuthStatus.notLinked;
    return KimiAuthStatus(linked: true, apiKey: key, maskedKey: _maskKey(key));
  }

  static Future<void> saveKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKimiApiKey, key.trim());
  }

  static Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKimiApiKey);
  }

  static String _maskKey(String key) {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }
}
