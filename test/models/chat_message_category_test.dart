import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';

void main() {
  group('MessageCategory serialization', () {
    test('roundtrips awaitingReply through toJson/fromJson', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Яку технологію обрати?',
        agentId: 'manager#1',
        category: MessageCategory.awaitingReply,
      );
      final json = msg.toJson();
      expect(json['category'], 'awaitingReply');
      final restored = ChatMessage.fromJson(json);
      expect(restored.category, MessageCategory.awaitingReply);
    });

    test('roundtrips status through toJson/fromJson', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'читаю lib/main.dart',
        agentId: 'coder#1',
        category: MessageCategory.status,
      );
      final json = msg.toJson();
      expect(json['category'], 'status');
      final restored = ChatMessage.fromJson(json);
      expect(restored.category, MessageCategory.status);
    });

    test('roundtrips taskLinked through toJson/fromJson', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Реалізувати auth flow',
        agentId: 'manager#1',
        category: MessageCategory.taskLinked,
      );
      final json = msg.toJson();
      expect(json['category'], 'taskLinked');
      final restored = ChatMessage.fromJson(json);
      expect(restored.category, MessageCategory.taskLinked);
    });

    test('null category is omitted from toJson and restores as null', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Привіт!',
        agentId: 'manager#1',
      );
      final json = msg.toJson();
      expect(json.containsKey('category'), isFalse);
      final restored = ChatMessage.fromJson(json);
      expect(restored.category, isNull);
    });

    test('unknown category string restores as null', () {
      final json = {
        'role': 'assistant',
        'text': 'test',
        'agentId': 'manager#1',
        'timestamp': DateTime.now().toIso8601String(),
        'category': 'someUnknownFutureCategory',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.category, isNull);
    });
  });

  group('threadId serialization', () {
    test('roundtrips threadId through toJson/fromJson', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Починаю задачу',
        agentId: 'coder#1',
        threadId: 'thread-abc-123',
      );
      final json = msg.toJson();
      expect(json['threadId'], 'thread-abc-123');
      final restored = ChatMessage.fromJson(json);
      expect(restored.threadId, 'thread-abc-123');
    });

    test('null threadId is omitted from toJson and restores as null', () {
      final msg = ChatMessage(
        role: ChatRole.user,
        text: 'Привіт',
        agentId: 'manager#1',
      );
      final json = msg.toJson();
      expect(json.containsKey('threadId'), isFalse);
      final restored = ChatMessage.fromJson(json);
      expect(restored.threadId, isNull);
    });
  });

  group('copyWith', () {
    test('copyWith preserves category when not overridden', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'original',
        agentId: 'manager#1',
        category: MessageCategory.awaitingReply,
      );
      final updated = msg.copyWith(text: 'updated');
      expect(updated.category, MessageCategory.awaitingReply);
      expect(updated.text, 'updated');
    });

    test('copyWith preserves threadId when not overridden', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'test',
        agentId: 'coder#1',
        threadId: 'thread-xyz',
      );
      final updated = msg.copyWith(isStreaming: true);
      expect(updated.threadId, 'thread-xyz');
    });
  });
}
