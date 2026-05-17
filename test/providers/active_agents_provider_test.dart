/// Tests for activeAgentsProvider — server snapshot ingestion + cancel
/// intents for the Settings → "Активні агенти" tab.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/active_agents_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class _FakeWs extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final List<Map<String, Object?>> sent = [];

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => const Stream.empty();

  @override
  void listActiveAgents() => sent.add({'op': 'listActiveAgents'});

  @override
  void cancelDispatchAgent(String dispatchId) =>
      sent.add({'op': 'cancelDispatchAgent', 'id': dispatchId});

  @override
  void cancelChatQuery(String queryId) =>
      sent.add({'op': 'cancelChatQuery', 'id': queryId});

  @override
  void cancelAllActive() => sent.add({'op': 'cancelAllActive'});

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    return super.dispose();
  }
}

ProviderContainer _makeContainer(_FakeWs ws) {
  final c = ProviderContainer(overrides: [
    wsServiceProvider.overrideWithValue(ws),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('activeAgentsProvider', () {
    test('initial state is empty and provider requests a snapshot on build',
        () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);

      expect(c.read(activeAgentsProvider), isEmpty);
      // build() side-effect — provider asks server for initial state so the UI
      // is correct even if no broadcast has happened since reconnect.
      expect(ws.sent.where((m) => m['op'] == 'listActiveAgents'), hasLength(1));
    });

    test('ActiveAgentsMessage from server replaces the list', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(activeAgentsProvider); // subscribe

      ws.inject(const ActiveAgentsMessage(entries: [
        ActiveAgentEntry(
          kind: ActiveAgentKind.dispatch,
          id: 'disp-1',
          agentId: 'coder#1',
          task: 'add login button',
          elapsedMs: 12_000,
        ),
        ActiveAgentEntry(
          kind: ActiveAgentKind.chat,
          id: 'q-1',
          agentId: 'manager#1',
          task: 'plan the sprint',
          elapsedMs: 5_000,
        ),
      ]));
      await Future<void>.delayed(Duration.zero);

      final st = c.read(activeAgentsProvider);
      expect(st, hasLength(2));
      expect(st[0].kind, ActiveAgentKind.dispatch);
      expect(st[1].kind, ActiveAgentKind.chat);
      expect(st[1].task, 'plan the sprint');
    });

    test('subsequent message fully replaces (not merges) the list', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      c.read(activeAgentsProvider);

      ws.inject(const ActiveAgentsMessage(entries: [
        ActiveAgentEntry(
          kind: ActiveAgentKind.dispatch,
          id: 'disp-1',
          agentId: 'coder#1',
          task: 't1',
          elapsedMs: 1000,
        ),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(activeAgentsProvider), hasLength(1));

      // Empty message — agent finished, list should clear.
      ws.inject(const ActiveAgentsMessage(entries: []));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(activeAgentsProvider), isEmpty);
    });

    test('cancelDispatch sends cancel_dispatch_agent with id', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final n = c.read(activeAgentsProvider.notifier);

      n.cancelDispatch('disp-42');

      expect(
        ws.sent.firstWhere((m) => m['op'] == 'cancelDispatchAgent'),
        {'op': 'cancelDispatchAgent', 'id': 'disp-42'},
      );
    });

    test('cancelChat sends cancel_chat_query with id', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final n = c.read(activeAgentsProvider.notifier);

      n.cancelChat('q-7');

      expect(
        ws.sent.firstWhere((m) => m['op'] == 'cancelChatQuery'),
        {'op': 'cancelChatQuery', 'id': 'q-7'},
      );
    });

    test('cancelAll sends cancel_all_active', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final n = c.read(activeAgentsProvider.notifier);

      n.cancelAll();

      expect(ws.sent.where((m) => m['op'] == 'cancelAllActive'), hasLength(1));
    });

    test('refresh re-requests the snapshot', () async {
      final ws = _FakeWs();
      final c = _makeContainer(ws);
      final n = c.read(activeAgentsProvider.notifier);
      // build() already sent one — clear so we can isolate refresh's call.
      ws.sent.clear();

      n.refresh();

      expect(ws.sent, hasLength(1));
      expect(ws.sent.single['op'], 'listActiveAgents');
    });
  });

  group('ServerMessage.fromJson — active_agents', () {
    test('parses entries with both kinds', () {
      final raw =
          '{"type":"active_agents","entries":[{"kind":"dispatch","id":"d1","agentId":"coder#1","task":"x","elapsedMs":1000},{"kind":"chat","id":"q1","agentId":"manager#1","task":"y","elapsedMs":2500}]}';
      final msg = ServerMessage.fromJson(raw);
      expect(msg, isA<ActiveAgentsMessage>());
      final m = msg as ActiveAgentsMessage;
      expect(m.entries[0].kind, ActiveAgentKind.dispatch);
      expect(m.entries[1].kind, ActiveAgentKind.chat);
      expect(m.entries[1].elapsedMs, 2500);
    });

    test('tolerates missing task/elapsedMs with sensible defaults', () {
      final raw =
          '{"type":"active_agents","entries":[{"kind":"chat","id":"q1","agentId":"manager#1"}]}';
      final msg = ServerMessage.fromJson(raw) as ActiveAgentsMessage;
      expect(msg.entries.single.task, '');
      expect(msg.entries.single.elapsedMs, 0);
    });
  });
}
