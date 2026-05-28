/// Tests for TechLeadPulseProvider and agentCompletionCountProvider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/tech_lead_pulse_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WS service ─────────────────────────────────────────────────────────

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  Stream<String> get connectionLog => const Stream.empty();

  @override
  Stream<String?> get phaseStatus => const Stream.empty();

  @override
  bool get isConnected => true;

  @override
  void getTechLeadPulse({int? limit}) {}

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
  }
}

ProviderContainer _makeContainer(_FakeWsService ws) {
  return ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(ws)],
  );
}

TechLeadPulseEntry _entry({
  required String agentId,
  String taskId = 'task-1',
  String title = 'Task',
  String role = 'coder',
}) =>
    TechLeadPulseEntry(
      taskId: taskId,
      title: title,
      agentId: agentId,
      role: role,
      ts: DateTime.now().toUtc(),
    );

void main() {
  group('TechLeadPulseNotifier', () {
    test('initial state is an empty list', () {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);

      expect(container.read(techLeadPulseProvider), isEmpty);
    });

    test('updates state when TechLeadPulseMessage arrives', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(techLeadPulseProvider); // force subscription

      final entries = [
        _entry(agentId: 'coder#1', taskId: 'task-1'),
        _entry(agentId: 'coder#2', taskId: 'task-2'),
      ];

      ws.inject(TechLeadPulseMessage(entries: entries));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(techLeadPulseProvider), hasLength(2));
      expect(container.read(techLeadPulseProvider).first.agentId, 'coder#1');
    });

    test('replaces state on each new pulse message', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(techLeadPulseProvider); // force subscription

      ws.inject(TechLeadPulseMessage(entries: [
        _entry(agentId: 'coder#1', taskId: 'task-1'),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(techLeadPulseProvider), hasLength(1));

      ws.inject(TechLeadPulseMessage(entries: [
        _entry(agentId: 'coder#1', taskId: 'task-2'),
        _entry(agentId: 'coder#2', taskId: 'task-3'),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(techLeadPulseProvider), hasLength(2));
    });

    test('ignores non-pulse server messages', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(techLeadPulseProvider); // force subscription

      ws.inject(ErrorMessage(message: 'oops'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(techLeadPulseProvider), isEmpty);
    });
  });

  group('agentCompletionCountProvider', () {
    test('returns 0 for an agent with no entries', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(techLeadPulseProvider); // force subscription

      ws.inject(TechLeadPulseMessage(entries: [
        _entry(agentId: 'coder#1'),
      ]));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(agentCompletionCountProvider('designer#1')), 0);
    });

    test('counts entries belonging to the given agentId', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(techLeadPulseProvider); // force subscription

      ws.inject(TechLeadPulseMessage(entries: [
        _entry(agentId: 'coder#1', taskId: 'task-1'),
        _entry(agentId: 'coder#1', taskId: 'task-2'),
        _entry(agentId: 'designer#1', taskId: 'task-3'),
      ]));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(agentCompletionCountProvider('coder#1')), 2);
      expect(container.read(agentCompletionCountProvider('designer#1')), 1);
    });

    test('returns 0 when pulse list is empty', () {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);

      expect(container.read(agentCompletionCountProvider('coder#1')), 0);
    });
  });
}
