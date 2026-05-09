/// Pin the offline-message queue policy in `WsOutbox`. The queue exists
/// so user actions (chat, board edits) submitted during the 3-second
/// reconnect window survive instead of being silently dropped — without
/// the corresponding server-side dedup (`ChatHistory.add` is idempotent
/// on caller id), a replay would risk producing chat duplicates.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/ws_outbox.dart';

void main() {
  Map<String, dynamic> chat(String id) => {
    'type': 'send_message',
    'content': 'hi',
    'id': id,
  };

  group('WsOutbox.enqueue', () {
    test('queues non-ephemeral messages in FIFO order', () {
      final outbox = WsOutbox();
      expect(outbox.enqueue(chat('a')), EnqueueResult.enqueued);
      expect(outbox.enqueue(chat('b')), EnqueueResult.enqueued);
      expect(outbox.enqueue(chat('c')), EnqueueResult.enqueued);
      expect(outbox.length, 3);
      expect(outbox.queuedTypes, ['send_message', 'send_message', 'send_message']);
    });

    test('drops sync_positions / get_status / interrupt as ephemeral', () {
      final outbox = WsOutbox();
      expect(outbox.enqueue({'type': 'sync_positions'}), EnqueueResult.droppedEphemeral);
      expect(outbox.enqueue({'type': 'get_status'}), EnqueueResult.droppedEphemeral);
      expect(outbox.enqueue({'type': 'interrupt'}), EnqueueResult.droppedEphemeral);
      expect(outbox.length, 0);
    });

    test('cap evicts the OLDEST queued message, not the newest', () {
      // The whole point of queueing is preserving the most recent intent;
      // dropping the latest message would defeat that.
      final outbox = WsOutbox(cap: 3);
      outbox.enqueue(chat('a'));
      outbox.enqueue(chat('b'));
      outbox.enqueue(chat('c'));
      // Cap reached; the next enqueue evicts 'a'.
      expect(outbox.enqueue(chat('d')), EnqueueResult.evictedOldest);
      expect(outbox.length, 3);
      final drained = outbox.drainAll();
      expect(drained.map((m) => m['id']).toList(), ['b', 'c', 'd']);
    });

    test('messages without a type field are still queued (no policy applies)', () {
      final outbox = WsOutbox();
      expect(outbox.enqueue({'foo': 'bar'}), EnqueueResult.enqueued);
      expect(outbox.length, 1);
    });

    test('custom ephemeral set replaces the defaults entirely', () {
      final outbox = WsOutbox(ephemeralTypes: const {'foo'});
      expect(outbox.enqueue({'type': 'foo'}), EnqueueResult.droppedEphemeral);
      // 'sync_positions' is no longer treated as ephemeral with a custom set.
      expect(outbox.enqueue({'type': 'sync_positions'}), EnqueueResult.enqueued);
    });
  });

  group('WsOutbox.drainAll', () {
    test('returns FIFO snapshot and clears the queue', () {
      final outbox = WsOutbox();
      outbox.enqueue(chat('a'));
      outbox.enqueue(chat('b'));
      final drained = outbox.drainAll();
      expect(drained.map((m) => m['id']).toList(), ['a', 'b']);
      expect(outbox.length, 0);
    });

    test('on empty queue returns an empty list and stays empty', () {
      final outbox = WsOutbox();
      expect(outbox.drainAll(), isEmpty);
      expect(outbox.length, 0);
    });

    test('queue is reusable after drain — new enqueues land cleanly', () {
      final outbox = WsOutbox();
      outbox.enqueue(chat('a'));
      outbox.drainAll();
      outbox.enqueue(chat('b'));
      expect(outbox.length, 1);
      expect(outbox.drainAll().single['id'], 'b');
    });
  });
}
