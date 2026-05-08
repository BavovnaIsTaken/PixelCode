/// Failing characterisation tests for `mergeChatHistory`.
///
/// Each test encodes the invariant that **two clients (e.g. macOS + iOS)
/// reacting to the same server stream must converge to identical state**.
/// They are expected to fail against the current implementation — that's the
/// point: they pin the divergence sources so the upcoming id+server-timestamp
/// rework has a regression net.
///
/// Drift sources currently exercised:
///   1. clock skew on optimistic user-message write
///   2. clock skew on streamed assistant messages after `done`
///   3. snapshot idempotency (same snapshot delivered twice)
///   4. out-of-order snapshot delivery
///   5. cross-device convergence on the same wire-trace
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/services/chat_history_merge.dart';

ChatMessage _user(
  String agentId,
  String text,
  DateTime ts, {
  String? idOverride,
}) =>
    ChatMessage(
      role: ChatRole.user,
      text: text,
      agentId: agentId,
      timestamp: ts,
      id: idOverride,
    );

ChatMessage _assistant(
  String agentId,
  String text,
  DateTime ts, {
  bool isStreaming = false,
  String? threadId,
}) =>
    ChatMessage(
      role: ChatRole.assistant,
      text: text,
      agentId: agentId,
      timestamp: ts,
      isStreaming: isStreaming,
      threadId: threadId,
    );

/// Compact projection used to compare lists across "devices" — strips the
/// volatile `timestamp` field so we assert *logical* convergence, not exact
/// instants. Two clients with skewed clocks should still produce the same
/// (role, agentId, text, isStreaming) sequence.
List<List<Object?>> _logical(List<ChatMessage> msgs) => [
      for (final m in msgs)
        [m.role, m.agentId, m.text, m.isStreaming],
    ];

void main() {
  const agent = 'manager#1';

  group('mergeChatHistory — clock-skew on optimistic user write (#1)', () {
    test(
      'macOS local-T > server-T must NOT duplicate the same message',
      () {
      // macOS optimistically appended the user's "Hello" at its local clock,
      // which happens to be 500ms ahead of the server's wall clock.
      final localTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 500);
      final serverTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 0);

      final local = {
        agent: [_user(agent, 'Hello', localTs)],
      };
      // Server then broadcasts a snapshot that contains the same message
      // with its canonical (earlier) timestamp.
      final serverMessages = [_user(agent, 'Hello', serverTs)];

      final merged = mergeChatHistory(local, serverMessages);

      // Invariant: server is source-of-truth, message is the same one — the
      // result must contain "Hello" exactly once.
      expect(merged[agent]!.length, 1,
          reason: 'optimistic local message must collapse with the server '
              'echo of the same message, not duplicate it');
    });

    test('iOS local-T < server-T already drops the local copy (control)',
        () {
      // Sanity check that the divergence is asymmetric — when the local
      // clock is BEHIND server, the current logic happens to produce the
      // correct count.  This means the bug is platform-dependent on whose
      // clock runs faster, exactly matching the user-reported drift.
      final localTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 0);
      final serverTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 500);

      final local = {
        agent: [_user(agent, 'Hello', localTs)],
      };
      final serverMessages = [_user(agent, 'Hello', serverTs)];

      final merged = mergeChatHistory(local, serverMessages);

      expect(merged[agent]!.length, 1);
    });
  });

  group('mergeChatHistory — clock-skew on finalised assistant stream (#2)',
      () {
    test(
      'finalised local stream with T_local > T_server must NOT duplicate',
      () {
      // After AssistantDoneMessage the local message is `isStreaming=false`
      // and carries the local DateTime.now() it was first instantiated with.
      // Snapshot then arrives with the server's canonical timestamp.
      final localTs = DateTime.utc(2026, 5, 3, 12, 0, 1, 200);
      final serverTs = DateTime.utc(2026, 5, 3, 12, 0, 1, 0);

      final local = {
        agent: [_assistant(agent, 'Pong', localTs, threadId: 't1')],
      };
      final serverMessages = [_assistant(agent, 'Pong', serverTs)];

      final merged = mergeChatHistory(local, serverMessages);

      expect(merged[agent]!.length, 1,
          reason: 'finalised assistant message echoed by the server snapshot '
              'must not coexist with the locally-stamped copy');
    });
  });

  group('mergeChatHistory — snapshot idempotency (#3)', () {
    test('applying the same snapshot twice yields the same logical list', () {
      final tsA = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final tsB = DateTime.utc(2026, 5, 3, 12, 0, 1);
      final snapshot = [
        _user(agent, 'Hi', tsA),
        _assistant(agent, 'Hello!', tsB),
      ];

      final once = mergeChatHistory({}, snapshot);
      final twice = mergeChatHistory(once, snapshot);

      expect(_logical(twice[agent]!), _logical(once[agent]!),
          reason: 'merge must be idempotent — duplicate snapshot delivery '
              '(reconnect burst) cannot change the list');
      expect(twice[agent]!.length, snapshot.length);
    });

    test(
      'optimistic-then-snapshot stays stable on a redelivery of the same snapshot',
      () {
      // First the sender's local optimistic write, then server snapshot,
      // then the same snapshot again (network retransmit). End state must
      // equal the state right after the first snapshot.
      final localTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 500);
      final serverTs = DateTime.utc(2026, 5, 3, 12, 0, 0, 0);

      final localAfterOptimistic = {
        agent: [_user(agent, 'Hello', localTs)],
      };
      final snapshot = [_user(agent, 'Hello', serverTs)];

      final after1 = mergeChatHistory(localAfterOptimistic, snapshot);
      final after2 = mergeChatHistory(after1, snapshot);

      expect(_logical(after2[agent]!), _logical(after1[agent]!));
      expect(after2[agent]!.length, 1,
          reason: 'redelivery of an idempotent snapshot must not grow list');
    });
  });

  group('mergeChatHistory — out-of-order snapshot delivery (#4)', () {
    test(
      'older snapshot arriving after a newer one must not roll back',
      () {
      final ts1 = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final ts2 = DateTime.utc(2026, 5, 3, 12, 0, 1);
      final ts3 = DateTime.utc(2026, 5, 3, 12, 0, 2);

      final newerSnapshot = [
        _user(agent, 'A', ts1),
        _assistant(agent, 'B', ts2),
        _user(agent, 'C', ts3),
      ];
      final olderSnapshot = [
        _user(agent, 'A', ts1),
        _assistant(agent, 'B', ts2),
      ];

      final afterNewer = mergeChatHistory({}, newerSnapshot);
      final afterOlder = mergeChatHistory(afterNewer, olderSnapshot);

      // Server is source-of-truth; if the server has only A,B in the late
      // snapshot, then "C" was rolled back server-side and must vanish on
      // the client too. The ALTERNATE invariant — "snapshots only grow" —
      // would also be acceptable, but the current implementation does
      // neither: it produces [A,B,C] (kept C via tail) which contradicts
      // the new snapshot, and also keeps duplicates of A,B if their
      // timestamps drift.  Pin the source-of-truth interpretation here.
      expect(_logical(afterOlder[agent]!), _logical(olderSnapshot),
          reason: 'server snapshot must replace local list — it is the '
              'source of truth, not an additive feed');
    });
  });

  group('mergeChatHistory — cross-device convergence (#5)', () {
    test(
      'two devices receiving the same wire trace converge to equal state',
      () {
      // Simulate macOS and iOS both seeing: optimistic user msg (sender
      // side only — receiver gets it via snapshot), assistant streamed
      // message, then chat_history snapshot at the end.
      // We model the only difference between the devices as their local
      // DateTime.now() values (~600ms skew).
      final macSkew = const Duration(milliseconds: 0);
      final iosSkew = const Duration(milliseconds: 600);

      // Server-canonical timestamps.
      final serverUserTs = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final serverAsstTs = DateTime.utc(2026, 5, 3, 12, 0, 1);

      Map<String, List<ChatMessage>> simulateDevice(Duration skew) {
        // 1) Sender-side optimistic write of the user message (macOS only
        //    here; for the iOS branch we treat the user message as inbound
        //    via snapshot, because the user typed on macOS).  We model both
        //    devices going through the same "local streaming" state for the
        //    assistant reply since both receive the same delta stream.
        var state = <String, List<ChatMessage>>{};

        // Local streaming assistant message (both devices stamp local now).
        final localAsstTs = serverAsstTs.add(skew);
        state = {
          agent: [
            _assistant(agent, 'Pong', localAsstTs, threadId: 't1'),
          ],
        };

        // Final chat_history snapshot from server.
        final snapshot = [
          _user(agent, 'Ping', serverUserTs),
          _assistant(agent, 'Pong', serverAsstTs),
        ];
        return mergeChatHistory(state, snapshot);
      }

      final macState = simulateDevice(macSkew);
      final iosState = simulateDevice(iosSkew);

      expect(_logical(iosState[agent]!), _logical(macState[agent]!),
          reason: 'two devices receiving identical wire data must converge '
              'to the same logical message list — clock skew is the only '
              'difference and must not influence the merge result');
    });
  });

  group('mergeChatHistory — known-good invariants (regression net)', () {
    test('keeps still-streaming local messages even if they pre-date server',
        () {
      // This is the original reason for the tail: don't wipe a captain
      // response that's mid-flight when an unrelated snapshot lands.
      final serverTs = DateTime.utc(2026, 5, 3, 12, 0, 5);
      final streamingTs = DateTime.utc(2026, 5, 3, 12, 0, 4);

      final local = {
        agent: [
          _assistant(agent, 'partial...', streamingTs,
              isStreaming: true, threadId: 't9'),
        ],
      };
      final serverMessages = [_user(agent, 'earlier', serverTs)];

      final merged = mergeChatHistory(local, serverMessages);

      expect(merged[agent]!.length, 2);
      expect(merged[agent]!.last.isStreaming, isTrue);
    });

    test('streaming local message on an agent absent from snapshot survives',
        () {
      // Captain delegated to coder#1, the coder is mid-stream, and a
      // chat_history snapshot lands that only covers manager#1. The
      // streaming coder bubble must NOT be wiped just because the
      // snapshot didn't mention it — the contract preserves streaming.
      final ts = DateTime.utc(2026, 5, 3, 12, 0);
      final local = {
        'coder#1': [
          _assistant('coder#1', 'partial...', ts,
              isStreaming: true, threadId: 't1'),
        ],
      };
      final merged =
          mergeChatHistory(local, [_user('manager#1', 'hi', ts)]);
      expect(merged['coder#1']!.single.isStreaming, isTrue);
      expect(merged['manager#1']!.single.text, 'hi');
    });

    test(
      'non-streaming local-only ghost on an absent agent is DROPPED '
      '(server snapshot is authoritative — fixes iPhone↔Mac stale-message bug)',
      () {
      // Pre-fix bug pathway: Mac cleared chat, server broadcast empty
      // snapshot, iPhone kept local stale messages because the merge
      // had a "subset of agents" fast-path that bypassed the per-msg
      // rules. Now: a non-streaming, no-id local message on an agent
      // the snapshot doesn't cover must die — that's what "server is
      // authoritative" actually means.
      final ts = DateTime.utc(2026, 5, 3, 12, 0);
      final stale = {
        'coder#1': [_user('coder#1', 'stale ghost', ts)],
      };
      final merged = mergeChatHistory(stale, const []);
      expect(merged.containsKey('coder#1'), isFalse,
          reason: 'agents with only stale ghost messages must drop out '
              'when the server says "no messages for anyone"');
      expect(merged, isEmpty);
    });

    test('empty local + empty snapshot = empty result', () {
      expect(mergeChatHistory({}, const []), isEmpty);
    });
  });

  group('mergeChatHistory — cross-device sync (iPhone↔Mac scenarios)', () {
    test(
      'Mac clears chat → server broadcasts empty → iPhone clears too',
      () {
      // Setup: both devices in sync after a chat with two messages.
      final ts1 = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final ts2 = DateTime.utc(2026, 5, 3, 12, 0, 1);
      final priorState = mergeChatHistory({}, [
        _user(agent, 'Привіт', ts1),
        _assistant(agent, 'Привіт, як справи?', ts2),
      ]);
      expect(priorState[agent]!.length, 2);

      // Mac taps "clear chat" → server broadcasts empty snapshot.
      final afterClear = mergeChatHistory(priorState, const []);

      // iPhone (running this same merge) must reflect the clear.
      expect(afterClear, isEmpty,
          reason: 'cross-device clear must propagate — empty snapshot '
              'wins over stale local list');
    });

    test(
      'iPhone joins late: empty local + populated snapshot = full sync',
      () {
      // iPhone connects mid-session. It has no local messages. Server
      // sends the full chat_history. iPhone must end up with everything.
      final ts1 = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final ts2 = DateTime.utc(2026, 5, 3, 12, 0, 1);
      final ts3 = DateTime.utc(2026, 5, 3, 12, 0, 2);
      final snapshot = [
        _user(agent, 'A', ts1),
        _assistant(agent, 'B', ts2),
        _user(agent, 'C', ts3),
      ];
      final merged = mergeChatHistory({}, snapshot);
      expect(merged[agent]!.length, 3);
      expect(merged[agent]!.map((m) => m.text).toList(), ['A', 'B', 'C']);
    });

    test(
      'one device on agent A, other on agent B — full snapshot syncs both',
      () {
      // Mac was on manager#1 chat. iPhone was on coder#1 chat. Snapshot
      // covers both agents. Both devices must see both threads after merge.
      final ts = DateTime.utc(2026, 5, 3, 12, 0);
      final localOnMac = {
        'manager#1': [
          _user('manager#1', 'mac local', ts, idOverride: 'mac-id-1'),
        ],
      };
      final fullSnapshot = [
        _user('manager#1', 'mac local', ts, idOverride: 'mac-id-1'),
        _user('coder#1', 'from iPhone', ts, idOverride: 'ios-id-1'),
      ];
      final merged = mergeChatHistory(localOnMac, fullSnapshot);
      expect(merged['manager#1']!.single.text, 'mac local');
      expect(merged['coder#1']!.single.text, 'from iPhone');
      expect(merged['manager#1']!.length, 1,
          reason: 'matching id must NOT duplicate');
    });
  });
}
