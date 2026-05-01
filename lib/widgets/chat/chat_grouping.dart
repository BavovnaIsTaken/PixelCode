import 'package:flutter/material.dart';

import '../../models/agent_message.dart';

// ─── Chat item types ──────────────────────────────────────────────────────────

sealed class ChatItem {}

class SingleMessage extends ChatItem {
  final ChatMessage message;
  SingleMessage(this.message);
}

class StatusGroup extends ChatItem {
  final List<ChatMessage> messages;
  StatusGroup(this.messages);
}

class ThreadGroup extends ChatItem {
  final String id;
  final List<ChatMessage> messages;
  ThreadGroup({required this.id, required this.messages});
}

/// A burst of 2+ consecutive messages from the same sender (role:agentId).
/// Rendered as a visual deck — newest message on top, older ones peeking behind.
class MessagePack extends ChatItem {
  /// Stable ID derived from first message timestamp.
  final String packId;

  /// Sender key: "${role.name}:${agentId}".
  final String senderId;
  final List<ChatMessage> messages;

  MessagePack({
    required this.packId,
    required this.senderId,
    required this.messages,
  });
}

// ─── Agent color / icon helpers ───────────────────────────────────────────────

String _roleTypeOfId(String id) {
  final hash = id.indexOf('#');
  return hash > 0 ? id.substring(0, hash) : id;
}

Color agentColorFor(String agentId) => switch (_roleTypeOfId(agentId)) {
      'manager' => const Color(0xFF00C0D1),
      'tech-lead' => const Color(0xFFFF6B6B),
      'coder' => const Color(0xFF4ECDC4),
      'reviewer' => const Color(0xFFFFA500),
      'tester' => const Color(0xFFFF6B9D),
      'security' => const Color(0xFF8E44AD),
      'ui-ux-designer' => const Color(0xFF3498DB),
      'llm-specialist' => const Color(0xFF9B59FF),
      _ => const Color(0xFF95A5A6),
    };

IconData agentIconFor(String agentId) => switch (_roleTypeOfId(agentId)) {
      'manager' => Icons.sentiment_very_satisfied,
      'tech-lead' => Icons.architecture,
      'coder' => Icons.code,
      'reviewer' => Icons.fact_check,
      'tester' => Icons.bug_report,
      'security' => Icons.security,
      'ui-ux-designer' => Icons.palette,
      'llm-specialist' => Icons.psychology,
      _ => Icons.smart_toy_outlined,
    };

// ─── Grouping helpers ─────────────────────────────────────────────────────────

/// Returns a stable sender key used to decide bubble stacking, or null for
/// items that never stack (thread groups, status groups, packs).
String? itemSender(ChatItem item) {
  if (item is SingleMessage) {
    return '${item.message.role.name}:${item.message.agentId}';
  }
  return null;
}

/// Groups a flat chronological [messages] list into render items.
///
/// - [MessageCategory.packBreak] sentinel → flushes burst, not rendered.
/// - Messages sharing a [ChatMessage.threadId] → [ThreadGroup].
/// - ≥2 consecutive [MessageCategory.status] messages without threadId → [StatusGroup].
/// - ≥2 consecutive regular messages from the same sender → [MessagePack].
/// - Everything else → [SingleMessage].
List<ChatItem> buildChatItems(List<ChatMessage> messages) {
  final items = <ChatItem>[];
  final burst = <ChatMessage>[];
  String? burstSender;

  void flushBurst() {
    if (burst.isEmpty) return;
    if (burst.length >= 2) {
      items.add(MessagePack(
        packId: burst.first.timestamp.millisecondsSinceEpoch.toString(),
        senderId: burstSender!,
        messages: List.unmodifiable(burst),
      ));
    } else {
      items.add(SingleMessage(burst.first));
    }
    burst.clear();
    burstSender = null;
  }

  int i = 0;
  while (i < messages.length) {
    final msg = messages[i];

    // packBreak sentinel — flush burst, not rendered itself
    if (msg.category == MessageCategory.packBreak) {
      flushBurst();
      i++;
      continue;
    }

    // Thread group: flush burst first, then collect thread
    if (msg.threadId != null) {
      flushBurst();
      final id = msg.threadId!;
      final group = <ChatMessage>[];
      while (i < messages.length && messages[i].threadId == id) {
        group.add(messages[i]);
        i++;
      }
      items.add(ThreadGroup(id: id, messages: group));
      continue;
    }

    // Status run: flush burst first, then collect run
    if (msg.category == MessageCategory.status) {
      flushBurst();
      final run = <ChatMessage>[];
      while (i < messages.length &&
          messages[i].category == MessageCategory.status &&
          messages[i].threadId == null) {
        run.add(messages[i]);
        i++;
      }
      if (run.length >= 2) {
        items.add(StatusGroup(run));
      } else {
        items.add(SingleMessage(run.first));
      }
      continue;
    }

    // taskLinked: flush burst, render as single
    if (msg.category == MessageCategory.taskLinked) {
      flushBurst();
      items.add(SingleMessage(msg));
      i++;
      continue;
    }

    // Regular message: accumulate burst, flush on sender change
    final sender = '${msg.role.name}:${msg.agentId}';
    if (burstSender != null && burstSender != sender) {
      flushBurst();
    }
    burstSender = sender;
    burst.add(msg);
    i++;
  }

  flushBurst();
  return items;
}
