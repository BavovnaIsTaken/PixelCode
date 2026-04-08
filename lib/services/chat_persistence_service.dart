/// Persists chat messages and session ID to SharedPreferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_message.dart';

class ChatPersistenceService {
  static const _messagesKey = 'chat_messages';
  static const _sessionIdKey = 'chat_session_id';

  static List<ChatMessage> loadMessages(SharedPreferences prefs) {
    final raw = prefs.getString(_messagesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMessages(
    SharedPreferences prefs,
    List<ChatMessage> messages,
  ) {
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    return prefs.setString(_messagesKey, json);
  }

  static String? loadSessionId(SharedPreferences prefs) {
    return prefs.getString(_sessionIdKey);
  }

  static Future<void> saveSessionId(
    SharedPreferences prefs,
    String sessionId,
  ) {
    return prefs.setString(_sessionIdKey, sessionId);
  }

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_messagesKey);
    await prefs.remove(_sessionIdKey);
  }
}
