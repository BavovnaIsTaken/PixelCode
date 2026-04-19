/// Riverpod provider for connected devices tracking.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'agent_provider.dart';

class ConnectedDevicesNotifier extends Notifier<List<ConnectedClient>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<ConnectedClient> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _onMessage(ServerMessage msg) {
    if (msg is ClientsUpdatedMessage) {
      state = msg.clients;
    }
  }

  /// The client ID of this device (for "this device" highlighting).
  String get ownClientId => ref.read(wsServiceProvider).clientId;

  /// Clients that share a machine with the server (loopback connections).
  List<ConnectedClient> get hostMachineDevices =>
      state.where((c) => c.isHostMachine).toList();

  /// Clients connecting from other machines.
  List<ConnectedClient> get remoteDevices =>
      state.where((c) => !c.isHostMachine).toList();
}

final connectedDevicesProvider =
    NotifierProvider<ConnectedDevicesNotifier, List<ConnectedClient>>(
  ConnectedDevicesNotifier.new,
);
