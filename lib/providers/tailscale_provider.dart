/// Tailscale Funnel setup state — tracks `tailscale up` progress.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'agent_provider.dart';

class TailscaleSetupState {
  final bool isConnecting;
  final List<String> logs;

  const TailscaleSetupState({
    this.isConnecting = false,
    this.logs = const [],
  });

  TailscaleSetupState copyWith({bool? isConnecting, List<String>? logs}) =>
      TailscaleSetupState(
        isConnecting: isConnecting ?? this.isConnecting,
        logs: logs ?? this.logs,
      );
}

class TailscaleSetupNotifier extends Notifier<TailscaleSetupState> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  TailscaleSetupState build() {
    _sub?.cancel();
    _sub = ref.read(wsServiceProvider).messages.listen((msg) {
      if (msg is TailscaleLogMessage) {
        final logs = [...state.logs, msg.message];
        // Detect success via the tunnel URL becoming active
        final done = msg.message.startsWith('🚀');
        state = state.copyWith(
          logs: logs,
          isConnecting: done ? false : state.isConnecting,
        );
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return const TailscaleSetupState();
  }

  void connect() {
    state = const TailscaleSetupState(isConnecting: true);
    ref.read(wsServiceProvider).tailscaleConnect();
  }
}

final tailscaleSetupProvider =
    NotifierProvider<TailscaleSetupNotifier, TailscaleSetupState>(
  TailscaleSetupNotifier.new,
);
