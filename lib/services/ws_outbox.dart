/// Bounded FIFO queue of outgoing WebSocket messages held while the
/// socket is down. Drained after the next successful (re)connect so that
/// user actions (chat, board edits) survive a 3-second reconnect gap.
///
/// Policies:
///  * Ephemeral message types (status pings, position sync) are dropped
///    silently — replaying them after a delay misleads the UI.
///  * Cap is enforced by evicting the OLDEST entry first. The user
///    typically cares more about the latest action than ancient ones
///    stuck behind it; dropping the newest would defeat the purpose of
///    queueing in the first place.
///  * Server-side `ChatHistory.add` is idempotent on caller-supplied id,
///    so a double-send across the flush/onDone race is safe — no
///    client-side ack tracking required.
///
/// Lifted out of `AgentWsService` so the policy is exercised by pure
/// unit tests without a real WebSocket. The service holds an instance
/// and forwards `enqueue` / `drainAll` calls.
library;

class WsOutbox {
  WsOutbox({this.cap = 100, Set<String>? ephemeralTypes})
    : _ephemeralTypes = ephemeralTypes ?? const {
        'sync_positions',
        'get_status',
        'interrupt',
      };

  final int cap;
  final Set<String> _ephemeralTypes;
  final List<Map<String, dynamic>> _items = [];

  /// Number of messages currently queued. Useful for telemetry.
  int get length => _items.length;

  /// Snapshot of currently queued types (for tests / debug output).
  List<String> get queuedTypes =>
      _items.map((m) => m['type'] as String? ?? '?').toList(growable: false);

  /// Returns the result of the enqueue attempt so callers can log
  /// without re-implementing the policy:
  ///  * `enqueued` — message accepted into the queue.
  ///  * `droppedEphemeral` — type is in the ephemeral allow-drop list.
  ///  * `evictedOldest` — cap reached; one prior message was dropped to
  ///    make room and the new one was enqueued.
  EnqueueResult enqueue(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type != null && _ephemeralTypes.contains(type)) {
      return EnqueueResult.droppedEphemeral;
    }
    if (_items.length >= cap) {
      _items.removeAt(0);
      _items.add(msg);
      return EnqueueResult.evictedOldest;
    }
    _items.add(msg);
    return EnqueueResult.enqueued;
  }

  /// Returns and clears the queued messages in FIFO order. Caller is
  /// responsible for actually transmitting them; the outbox doesn't know
  /// about the WebSocket.
  List<Map<String, dynamic>> drainAll() {
    if (_items.isEmpty) return const [];
    final pending = List<Map<String, dynamic>>.from(_items);
    _items.clear();
    return pending;
  }
}

enum EnqueueResult { enqueued, droppedEphemeral, evictedOldest }
