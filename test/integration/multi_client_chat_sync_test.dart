/// Integration: end-to-end multi-client chat convergence.
///
/// Pins the user-stated invariant (2026-05-16):
///   "Якщо ти надіслав повідомлення з маку і з айфону — це має бути те саме,
///   як якби ти надіслав два повідомлення з макбуку у PixelCode."
///
/// We model the wire with a tiny in-memory `_FakeServer` holding a
/// canonical `[ChatMessage]` log (the server-side `ChatHistory`). Each
/// "device" (`_FakeDevice`) wraps a `ProviderContainer` + `_FakeWs` that
/// forwards `sendMessage` to the server and receives `chat_history`
/// snapshot broadcasts. The server enforces idempotent-by-id append,
/// matching `server/src/chat_history.ts`.
///
/// Coverage:
///   • Two devices each send one message → both end states identical and
///     contain BOTH messages.
///   • Equivalent to one device sending two messages (same end state).
///   • Replaying the same snapshot twice does not duplicate (idempotency
///     end-to-end, not just inside mergeChatHistory).
///   • A duplicate localId from a second device is dropped server-side
///     (defends against retry-on-flaky-network).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake server holding a canonical ChatHistory ──────────────────────

class _FakeServer {
  /// Append-only log, dedup on id (mirrors server `ChatHistory.add`).
  final List<ChatMessage> _messages = [];
  final Set<String> _seenIds = {};
  final List<_FakeWs> _clients = [];

  void attach(_FakeWs ws) => _clients.add(ws);

  /// Server-side `send_message` intake. Server stamps a timestamp + id.
  void receiveUserMessage({
    required String text,
    required String agentId,
    String? localId,
  }) {
    final id = localId ?? 'srv_${_messages.length}';
    if (_seenIds.contains(id)) return; // idempotent on id — duplicate intake dropped
    _seenIds.add(id);
    _messages.add(ChatMessage(
      role: ChatRole.user,
      text: text,
      agentId: agentId,
      timestamp: DateTime.utc(2026, 5, 16, 12, 0, _messages.length),
      id: id,
    ));
    _broadcast();
  }

  void _broadcast() {
    final msg = ChatHistoryMessage(messages: List.unmodifiable(_messages));
    for (final c in _clients) {
      c.injectFromServer(msg);
    }
  }
}

// ─── Fake WS that routes through the shared server ────────────────────

class _FakeWs extends AgentWsService {
  final _FakeServer server;
  final _msgCtrl = StreamController<ServerMessage>.broadcast();

  _FakeWs(this.server) {
    server.attach(this);
  }

  void injectFromServer(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => const Stream.empty();

  @override
  void sendMessage(
    String content, {
    String agentId = 'manager',
    List<String>? images,
    String? localId,
  }) {
    server.receiveUserMessage(text: content, agentId: agentId, localId: localId);
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    return super.dispose();
  }
}

// ─── Device = container + ws ───────────────────────────────────────────

class _Device {
  final ProviderContainer container;
  final _FakeWs ws;
  _Device(this.container, this.ws);

  ChatNotifier get chat => container.read(chatProvider.notifier);
  List<ChatMessage> get state => container.read(chatProvider);
}

Future<_Device> _device(_FakeServer server) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final ws = _FakeWs(server);
  final c = ProviderContainer(overrides: [
    wsServiceProvider.overrideWithValue(ws),
    sharedPrefsProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  c.read(selectedAgentProvider.notifier).state = 'manager#1';
  c.read(chatProvider); // subscribe so the listener is live before sends
  await Future<void>.delayed(Duration.zero);
  return _Device(c, ws);
}

/// Logical projection — strips volatile fields so we compare what the
/// user actually sees (role + agent + text), not server-clock drift.
List<List<Object?>> _logical(List<ChatMessage> msgs) => [
      for (final m in msgs.where((m) => m.role == ChatRole.user))
        [m.role, m.agentId, m.text],
    ];

void main() {
  group('multi-client chat sync end-to-end', () {
    test(
      'Mac sends A, iPhone sends B → both devices converge to [A, B]',
      () async {
        final server = _FakeServer();
        final mac = await _device(server);
        final iphone = await _device(server);

        mac.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        iphone.chat.sendMessage('B');
        await Future<void>.delayed(Duration.zero);

        // Both devices see exactly the same logical sequence.
        expect(_logical(mac.state), _logical(iphone.state));
        // And the sequence is [A, B].
        expect(
          _logical(mac.state),
          equals([
            [ChatRole.user, 'manager#1', 'A'],
            [ChatRole.user, 'manager#1', 'B'],
          ]),
        );
      },
    );

    test(
      'multi-device ≡ single-device sending the same two messages',
      () async {
        // Two-device path.
        final server1 = _FakeServer();
        final mac = await _device(server1);
        final iphone = await _device(server1);
        mac.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        iphone.chat.sendMessage('B');
        await Future<void>.delayed(Duration.zero);

        // Single-device baseline.
        final server2 = _FakeServer();
        final solo = await _device(server2);
        solo.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        solo.chat.sendMessage('B');
        await Future<void>.delayed(Duration.zero);

        // User-visible state is identical between paths.
        expect(_logical(mac.state), _logical(solo.state));
        expect(_logical(iphone.state), _logical(solo.state));
      },
    );

    test(
      'duplicate localId from a flaky retry does NOT produce a duplicate row',
      () async {
        final server = _FakeServer();
        final mac = await _device(server);
        final iphone = await _device(server);

        // Mac sends with a known id, then "re-emits" the same wire send
        // (e.g. resume-from-outbox after reconnect) — server must dedupe.
        mac.ws.sendMessage('A', agentId: 'manager#1', localId: 'fixed-id');
        await Future<void>.delayed(Duration.zero);
        // iPhone, on flaky network, retries the same logical message and
        // happens to collide on id (or echoes mac's outbox).
        iphone.ws.sendMessage('A', agentId: 'manager#1', localId: 'fixed-id');
        await Future<void>.delayed(Duration.zero);

        // Both devices see exactly one A (server dropped the duplicate).
        expect(_logical(mac.state), equals([[ChatRole.user, 'manager#1', 'A']]));
        expect(_logical(iphone.state), _logical(mac.state));
      },
    );

    test(
      'replaying the same chat_history snapshot twice does not duplicate',
      () async {
        final server = _FakeServer();
        final mac = await _device(server);

        mac.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        final after1 = _logical(mac.state);

        // Server re-broadcasts the same snapshot (e.g. another device
        // joined and triggered a peer-sync rebroadcast).
        server._broadcast();
        await Future<void>.delayed(Duration.zero);

        expect(_logical(mac.state), equals(after1));
      },
    );

    test(
      'interleaved order A → B → A2 on Mac, mid-stream B from iPhone, '
      'logical sequence still matches single-device baseline',
      () async {
        final server = _FakeServer();
        final mac = await _device(server);
        final iphone = await _device(server);

        mac.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        iphone.chat.sendMessage('B');
        await Future<void>.delayed(Duration.zero);
        mac.chat.sendMessage('A2');
        await Future<void>.delayed(Duration.zero);

        // Single-device baseline with the same logical send order.
        final server2 = _FakeServer();
        final solo = await _device(server2);
        solo.chat.sendMessage('A');
        await Future<void>.delayed(Duration.zero);
        solo.chat.sendMessage('B');
        await Future<void>.delayed(Duration.zero);
        solo.chat.sendMessage('A2');
        await Future<void>.delayed(Duration.zero);

        expect(_logical(mac.state), _logical(solo.state));
        expect(_logical(iphone.state), _logical(solo.state));
        expect(_logical(mac.state), _logical(iphone.state));
      },
    );
  });
}
