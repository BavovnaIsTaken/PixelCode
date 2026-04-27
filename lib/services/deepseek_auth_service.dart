/// Manages DeepSeek API key storage via SharedPreferences.
library;

import 'package:shared_preferences/shared_preferences.dart';

const _kDeepSeekApiKey = 'deepseek_api_key';

class DeepSeekAuthStatus {
  final bool linked;
  final String? apiKey;
  final String? maskedKey;

  const DeepSeekAuthStatus({required this.linked, this.apiKey, this.maskedKey});

  static const notLinked = DeepSeekAuthStatus(linked: false);
}

class DeepSeekAuthService {
  static Future<DeepSeekAuthStatus> checkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kDeepSeekApiKey);
    if (key == null || key.isEmpty) return DeepSeekAuthStatus.notLinked;
    return DeepSeekAuthStatus(linked: true, apiKey: key, maskedKey: _maskKey(key));
  }

  static Future<void> saveKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeepSeekApiKey, key.trim());
  }

  static Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeepSeekApiKey);
  }

  static String _maskKey(String key) {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }
}
