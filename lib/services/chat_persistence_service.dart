/// Persists chat messages and session ID to SharedPreferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_message.dart';

class ChatPersistenceService {
  static const _allMessagesKey = 'chat_messages_all';
  static const _sessionIdKey = 'chat_session_id';

  /// Legacy single-list key for migration.
  static const _legacyMessagesKey = 'chat_messages';

  /// Load all per-agent messages, migrating from legacy format if needed.
  static Map<String, List<ChatMessage>> loadAllMessages(
    SharedPreferences prefs,
  ) {
    // Try new per-agent format first
    final raw = prefs.getString(_allMessagesKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map.map((agentId, msgs) => MapEntry(
              agentId,
              (msgs as List)
                  .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
                  .toList(),
            ));
      } catch (_) {
        return {};
      }
    }

    // Migrate from legacy single-list format
    final legacy = prefs.getString(_legacyMessagesKey);
    if (legacy != null) {
      try {
        final list = jsonDecode(legacy) as List;
        final messages = list
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (messages.isNotEmpty) {
          // Group by agentId (legacy messages default to 'manager')
          final grouped = <String, List<ChatMessage>>{};
          for (final msg in messages) {
            (grouped[msg.agentId] ??= []).add(msg);
          }
          // Save in new format and remove legacy key
          saveAllMessages(prefs, grouped);
          prefs.remove(_legacyMessagesKey);
          return grouped;
        }
      } catch (_) {
        // ignore
      }
    }

    return {};
  }

  static Future<void> saveAllMessages(
    SharedPreferences prefs,
    Map<String, List<ChatMessage>> allMessages,
  ) {
    final map = allMessages.map(
      (agentId, msgs) =>
          MapEntry(agentId, msgs.map((m) => m.toJson()).toList()),
    );
    return prefs.setString(_allMessagesKey, jsonEncode(map));
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
    await prefs.remove(_allMessagesKey);
    await prefs.remove(_legacyMessagesKey);
    await prefs.remove(_sessionIdKey);
  }
}
