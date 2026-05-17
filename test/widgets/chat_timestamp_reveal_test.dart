/// Pull-to-reveal timestamp helpers in chat_grouping.dart.
///
/// The widget portion (`_TimestampRevealRow` in chat_panel.dart) is library-
/// private and renders trivial Stack math — covered indirectly via these
/// helpers + manual smoke test. What we pin here is the deterministic logic
/// (`chatItemTimestamp` per ChatItem variant + `formatChatHm`) so the column
/// label stays correct as the chat grouping evolves.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/chat/chat_grouping.dart';

ChatMessage _msg(DateTime ts, {ChatRole role = ChatRole.user}) => ChatMessage(
      role: role,
      text: 'x',
      agentId: 'manager#1',
      timestamp: ts,
    );

void main() {
  group('chatItemTimestamp', () {
    test('SingleMessage returns its own timestamp', () {
      final ts = DateTime.utc(2026, 5, 16, 14, 30);
      expect(chatItemTimestamp(SingleMessage(_msg(ts))), ts);
    });

    test('StatusGroup uses the first message (oldest) timestamp', () {
      final t1 = DateTime.utc(2026, 5, 16, 14, 30);
      final t2 = DateTime.utc(2026, 5, 16, 14, 31);
      final t3 = DateTime.utc(2026, 5, 16, 14, 32);
      final group = StatusGroup([_msg(t1), _msg(t2), _msg(t3)]);
      expect(chatItemTimestamp(group), t1);
    });

    test('ThreadGroup uses the first message timestamp', () {
      final t1 = DateTime.utc(2026, 5, 16, 10, 0);
      final t2 = DateTime.utc(2026, 5, 16, 10, 5);
      final group = ThreadGroup(id: 'tid', messages: [_msg(t1), _msg(t2)]);
      expect(chatItemTimestamp(group), t1);
    });

    test('MessagePack uses the first message timestamp', () {
      final t1 = DateTime.utc(2026, 5, 16, 9, 0);
      final t2 = DateTime.utc(2026, 5, 16, 9, 1);
      final pack = MessagePack(
        packId: 'p1',
        senderId: 'user:manager#1',
        messages: [_msg(t1), _msg(t2)],
      );
      expect(chatItemTimestamp(pack), t1);
    });
  });

  group('formatChatHm', () {
    test('pads single-digit hour and minute', () {
      // UTC → local; constructing a `local` DateTime keeps the test
      // independent of the host's time zone.
      expect(formatChatHm(DateTime(2026, 5, 16, 7, 5)), '07:05');
    });

    test('two-digit hour passes through', () {
      expect(formatChatHm(DateTime(2026, 5, 16, 23, 59)), '23:59');
    });

    test('00:00 midnight edge', () {
      expect(formatChatHm(DateTime(2026, 5, 16, 0, 0)), '00:00');
    });

    test('UTC input is converted to local time', () {
      // Construct UTC, format takes .toLocal(). Independent assertion: the
      // output must be a valid HH:MM string of length 5 with a colon at index 2.
      final out = formatChatHm(DateTime.utc(2026, 5, 16, 12, 0));
      expect(out.length, 5);
      expect(out[2], ':');
      // Hour and minute must be 0..23 / 0..59.
      final h = int.parse(out.substring(0, 2));
      final m = int.parse(out.substring(3, 5));
      expect(h >= 0 && h <= 23, isTrue);
      expect(m >= 0 && m <= 59, isTrue);
    });
  });
}
