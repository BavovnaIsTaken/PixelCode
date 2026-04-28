import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/services/chat_persistence_service.dart';

ChatMessage _msg(String agentId, String text) => ChatMessage(
      role: ChatRole.user,
      text: text,
      agentId: agentId,
      timestamp: DateTime(2026, 1, 1),
    );

Future<SharedPreferences> _prefs([Map<String, Object>? init]) async {
  SharedPreferences.setMockInitialValues(init ?? {});
  return SharedPreferences.getInstance();
}

void main() {
  group('ChatPersistenceService.loadAllMessages', () {
    test('returns empty map when prefs are empty', () async {
      final p = await _prefs();
      expect(ChatPersistenceService.loadAllMessages(p), isEmpty);
    });

    test('returns empty map on corrupted JSON', () async {
      final p = await _prefs({'chat_messages_all': 'not-json'});
      expect(ChatPersistenceService.loadAllMessages(p), isEmpty);
    });
  });

  group('ChatPersistenceService saveAllMessages + loadAllMessages', () {
    test('round-trips messages by agentId', () async {
      final p = await _prefs();
      final msgs = {
        'coder#1': [_msg('coder#1', 'Hello')],
        'manager#1': [_msg('manager#1', 'Good job')],
      };
      await ChatPersistenceService.saveAllMessages(p, msgs);
      final loaded = ChatPersistenceService.loadAllMessages(p);
      expect(loaded.keys, containsAll(['coder#1', 'manager#1']));
      expect(loaded['coder#1']!.first.text, 'Hello');
      expect(loaded['manager#1']!.first.text, 'Good job');
    });

    test('overwrites previous data', () async {
      final p = await _prefs();
      await ChatPersistenceService.saveAllMessages(p, {
        'coder#1': [_msg('coder#1', 'Old')],
      });
      await ChatPersistenceService.saveAllMessages(p, {
        'coder#1': [_msg('coder#1', 'New')],
      });
      final loaded = ChatPersistenceService.loadAllMessages(p);
      expect(loaded['coder#1']!.first.text, 'New');
    });
  });

  group('ChatPersistenceService legacy migration', () {
    test('migrates legacy chat_messages list to per-agent map', () async {
      final p = await _prefs({
        'chat_messages':
            '[{"role":"user","text":"Legacy","agentId":"manager#1","timestamp":"2026-01-01T00:00:00.000"}]',
      });
      final loaded = ChatPersistenceService.loadAllMessages(p);
      expect(loaded, contains('manager#1'));
      expect(loaded['manager#1']!.first.text, 'Legacy');
    });
  });

  group('ChatPersistenceService.sessionId', () {
    test('loadSessionId returns null when not set', () async {
      final p = await _prefs();
      expect(ChatPersistenceService.loadSessionId(p), isNull);
    });

    test('saveSessionId + loadSessionId round-trip', () async {
      final p = await _prefs();
      await ChatPersistenceService.saveSessionId(p, 'session-42');
      expect(ChatPersistenceService.loadSessionId(p), 'session-42');
    });
  });

  group('ChatPersistenceService.clear', () {
    test('removes all keys', () async {
      final p = await _prefs();
      await ChatPersistenceService.saveAllMessages(p, {
        'coder#1': [_msg('coder#1', 'Hi')],
      });
      await ChatPersistenceService.saveSessionId(p, 'sess-1');
      await ChatPersistenceService.clear(p);
      expect(ChatPersistenceService.loadAllMessages(p), isEmpty);
      expect(ChatPersistenceService.loadSessionId(p), isNull);
    });
  });
}
