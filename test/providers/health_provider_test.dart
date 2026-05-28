/// Tests for HealthProvider — state management and message handling.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/health_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

// ─── Fake WS service ─────────────────────────────────────────────────────────

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  bool _connected;

  _FakeWsService({bool connected = false}) : _connected = connected;

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  void setConnected(bool value) {
    _connected = value;
    _connCtrl.add(value);
  }

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus async* {
    yield _connected;
    yield* _connCtrl.stream;
  }

  @override
  Stream<String> get connectionLog => const Stream.empty();

  @override
  Stream<String?> get phaseStatus => const Stream.empty();

  @override
  bool get isConnected => _connected;

  @override
  void healthCheckRequest() {}

  @override
  void healthFixRequest(String id) {}

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
  }
}

ProviderContainer _makeContainer(_FakeWsService ws) {
  return ProviderContainer(
    overrides: [
      wsServiceProvider.overrideWithValue(ws),
      // Seed a synchronous stream so connectionStatusProvider.valueOrNull
      // resolves immediately instead of remaining AsyncLoading.
      connectionStatusProvider.overrideWith(
        (ref) => ref.watch(wsServiceProvider).connectionStatus,
      ),
    ],
  );
}

HealthItem _item(HealthItemId id, HealthStatus status, {bool fixable = false}) =>
    HealthItem(id: id, status: status, fixable: fixable);

void main() {
  group('HealthNotifier initial state', () {
    test('seeds clientConnected=fail when WS is not connected', () async {
      final ws = _FakeWsService(connected: false);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(healthProvider);
      expect(state.serverUnreachable, false);
      final clientItem = state.items[HealthItemId.clientConnected];
      expect(clientItem, isNotNull);
      expect(clientItem!.item.status, HealthStatus.fail);
    });

    test('seeds clientConnected=ok when WS is connected', () async {
      final ws = _FakeWsService(connected: true);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(healthProvider); // force build + _connSub
      await Future<void>.delayed(Duration.zero);

      final state = container.read(healthProvider);
      final clientItem = state.items[HealthItemId.clientConnected];
      expect(clientItem, isNotNull);
      expect(clientItem!.item.status, HealthStatus.ok);
    });
  });

  group('HealthNotifier._onMessage', () {
    test('processes HealthCheckResultMessage and clears refreshing flag', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(healthProvider); // force subscription

      ws.inject(HealthCheckResultMessage(items: [
        _item(HealthItemId.tailscaleInstalled, HealthStatus.ok),
        _item(HealthItemId.serverListening, HealthStatus.fail, fixable: true),
      ]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(healthProvider);
      expect(state.refreshing, false);
      expect(state.serverUnreachable, false);
      expect(state.items[HealthItemId.tailscaleInstalled]?.item.status,
          HealthStatus.ok);
      expect(state.items[HealthItemId.serverListening]?.item.status,
          HealthStatus.fail);
    });

    test('processes HealthItemUpdateMessage for a single item', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(healthProvider); // force subscription

      ws.inject(HealthCheckResultMessage(items: [
        _item(HealthItemId.tailscaleInstalled, HealthStatus.fail),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(healthProvider).items[HealthItemId.tailscaleInstalled]
          ?.item.status, HealthStatus.fail);

      ws.inject(HealthItemUpdateMessage(
        item: _item(HealthItemId.tailscaleInstalled, HealthStatus.ok),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(healthProvider).items[HealthItemId.tailscaleInstalled]
          ?.item.status, HealthStatus.ok);
    });

    test('ignores HealthItemUpdateMessage with null item', () async {
      final ws = _FakeWsService();
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(healthProvider); // force subscription

      ws.inject(HealthCheckResultMessage(items: [
        _item(HealthItemId.tailscaleInstalled, HealthStatus.ok),
      ]));
      await Future<void>.delayed(Duration.zero);

      // null-item update should not crash or change state
      ws.inject(const HealthItemUpdateMessage(item: null));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(healthProvider).items[HealthItemId.tailscaleInstalled]
          ?.item.status, HealthStatus.ok);
    });
  });

  group('HealthNotifier._onConnection', () {
    test('updates clientConnected on disconnect', () async {
      final ws = _FakeWsService(connected: true);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      container.read(healthProvider); // force subscription
      await Future<void>.delayed(Duration.zero);

      ws.setConnected(false);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(healthProvider);
      expect(state.items[HealthItemId.clientConnected]?.item.status,
          HealthStatus.fail);
      expect(state.serverUnreachable, true);
    });

    test('updates clientConnected on reconnect', () async {
      final ws = _FakeWsService(connected: false);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      // Force build so _connSub is active, then wait for async* initial yield.
      container.read(healthProvider);
      await Future<void>.delayed(Duration.zero);

      ws.setConnected(true);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(healthProvider).items[HealthItemId.clientConnected]
          ?.item.status, HealthStatus.ok);
      expect(container.read(healthProvider).serverUnreachable, false);
    });
  });

  group('HealthNotifier.refreshAll', () {
    test('sets serverUnreachable=true when not connected', () async {
      final ws = _FakeWsService(connected: false);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      container.read(healthProvider.notifier).refreshAll();

      expect(container.read(healthProvider).serverUnreachable, true);
      expect(container.read(healthProvider).refreshing, false);
    });

    test('sets refreshing=true when connected', () async {
      final ws = _FakeWsService(connected: true);
      final container = _makeContainer(ws);
      addTearDown(container.dispose);
      // Build the provider and let connectionStatusProvider emit its first value.
      container.read(healthProvider);
      await Future<void>.delayed(Duration.zero);

      container.read(healthProvider.notifier).refreshAll();

      expect(container.read(healthProvider).refreshing, true);
    });
  });
}
