/// Network-diagnostics state — tracks per-item health, fix progress, and fresh-check polling.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'agent_provider.dart';

/// Per-item view state the UI cares about beyond the raw check result.
class HealthItemView {
  final HealthItem item;
  final bool fixing;

  const HealthItemView({required this.item, this.fixing = false});

  HealthItemView copyWith({HealthItem? item, bool? fixing}) =>
      HealthItemView(item: item ?? this.item, fixing: fixing ?? this.fixing);
}

class HealthState {
  /// Map item id → view. Missing ids mean "never seen yet".
  final Map<HealthItemId, HealthItemView> items;

  /// True from the moment a refresh is sent until the first result comes back.
  final bool refreshing;

  /// True when server is unreachable — UI renders remote items as greyed out.
  final bool serverUnreachable;

  const HealthState({
    this.items = const {},
    this.refreshing = false,
    this.serverUnreachable = false,
  });

  HealthState copyWith({
    Map<HealthItemId, HealthItemView>? items,
    bool? refreshing,
    bool? serverUnreachable,
  }) =>
      HealthState(
        items: items ?? this.items,
        refreshing: refreshing ?? this.refreshing,
        serverUnreachable: serverUnreachable ?? this.serverUnreachable,
      );
}

class HealthNotifier extends Notifier<HealthState> {
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  final Map<HealthItemId, Timer> _fixTimers = {};

  @override
  HealthState build() {
    _msgSub?.cancel();
    _msgSub = ref.read(wsServiceProvider).messages.listen(_onMessage);

    _connSub?.cancel();
    _connSub = ref.read(wsServiceProvider).connectionStatus.listen(_onConnection);

    ref.onDispose(() {
      _msgSub?.cancel();
      _connSub?.cancel();
      for (final t in _fixTimers.values) {
        t.cancel();
      }
    });

    // Seed clientConnected from the current connection state.
    final connected = ref
            .read(connectionStatusProvider)
            .valueOrNull ??
        false;
    return HealthState(
      items: {
        HealthItemId.clientConnected: HealthItemView(
          item: HealthItem(
            id: HealthItemId.clientConnected,
            status: connected ? HealthStatus.ok : HealthStatus.fail,
            detail: connected ? null : 'Немає з\'єднання з сервером',
            fixable: false,
          ),
        ),
      },
    );
  }

  void _onMessage(ServerMessage msg) {
    if (msg is HealthCheckResultMessage) {
      final next = Map<HealthItemId, HealthItemView>.from(state.items);
      for (final item in msg.items) {
        final prev = next[item.id];
        next[item.id] = HealthItemView(item: item, fixing: prev?.fixing ?? false);
      }
      state = state.copyWith(items: next, refreshing: false, serverUnreachable: false);
    } else if (msg is HealthItemUpdateMessage) {
      final item = msg.item;
      if (item == null) return;
      final next = Map<HealthItemId, HealthItemView>.from(state.items);
      final prev = next[item.id];
      next[item.id] = HealthItemView(item: item, fixing: prev?.fixing ?? false);
      state = state.copyWith(items: next);
    }
  }

  void _onConnection(bool connected) {
    final next = Map<HealthItemId, HealthItemView>.from(state.items);
    next[HealthItemId.clientConnected] = HealthItemView(
      item: HealthItem(
        id: HealthItemId.clientConnected,
        status: connected ? HealthStatus.ok : HealthStatus.fail,
        detail: connected ? null : 'Немає з\'єднання з сервером',
        fixable: false,
      ),
    );
    state = state.copyWith(
      items: next,
      serverUnreachable: !connected,
      refreshing: connected ? state.refreshing : false,
    );
  }

  /// Kick off a full refresh — sends the WS request, waits for results.
  void refreshAll() {
    final connected = ref.read(connectionStatusProvider).valueOrNull ?? false;
    if (!connected) {
      state = state.copyWith(refreshing: false, serverUnreachable: true);
      return;
    }

    final next = Map<HealthItemId, HealthItemView>.from(state.items);
    // Mark all remote items as "checking".
    for (final id in HealthItemId.values) {
      if (id == HealthItemId.clientConnected) continue;
      final prev = next[id];
      next[id] = HealthItemView(
        item: HealthItem(
          id: id,
          status: HealthStatus.checking,
          detail: prev?.item.detail,
          fixable: prev?.item.fixable ?? false,
        ),
        fixing: prev?.fixing ?? false,
      );
    }
    state = state.copyWith(items: next, refreshing: true);
    ref.read(wsServiceProvider).healthCheckRequest();
  }

  /// Request an auto-fix; re-poll the item every 3s for up to ~15s.
  void fix(HealthItemId id) {
    final connected = ref.read(connectionStatusProvider).valueOrNull ?? false;
    if (!connected) return;

    final next = Map<HealthItemId, HealthItemView>.from(state.items);
    final prev = next[id];
    if (prev != null) {
      next[id] = prev.copyWith(
        fixing: true,
        item: prev.item.copyWith(status: HealthStatus.checking),
      );
      state = state.copyWith(items: next);
    }

    ref.read(wsServiceProvider).healthFixRequest(id.wire);

    _fixTimers[id]?.cancel();
    var elapsed = 0;
    _fixTimers[id] = Timer.periodic(const Duration(seconds: 3), (timer) {
      elapsed += 3;
      final current = state.items[id]?.item;
      if (current?.status == HealthStatus.ok || elapsed >= 15) {
        timer.cancel();
        _fixTimers.remove(id);
        final after = Map<HealthItemId, HealthItemView>.from(state.items);
        final entry = after[id];
        if (entry != null) after[id] = entry.copyWith(fixing: false);
        state = state.copyWith(items: after);
        return;
      }
      ref.read(wsServiceProvider).healthCheckRequest();
    });
  }
}

final healthProvider = NotifierProvider<HealthNotifier, HealthState>(HealthNotifier.new);
