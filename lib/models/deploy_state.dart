/// Shared deploy state model used by both iOS and Android deploy providers.
library;

import 'agent_message.dart' show AndroidDevice;

// ─── Phase ────────────────────────────────────────────────────────────────

enum DeployPhase { idle, checking, building, ready, error }

// ─── State ────────────────────────────────────────────────────────────────

class DeployState {
  final DeployPhase phase;
  final String? installUrl;
  final String? lastError;
  final List<String> logs;
  // Android-only: list of connected devices + selected serial.
  final List<AndroidDevice> devices;
  final String? selectedSerial;

  const DeployState({
    this.phase = DeployPhase.idle,
    this.installUrl,
    this.lastError,
    this.logs = const [],
    this.devices = const [],
    this.selectedSerial,
  });

  DeployState copyWith({
    DeployPhase? phase,
    String? installUrl,
    String? lastError,
    List<String>? logs,
    List<AndroidDevice>? devices,
    String? selectedSerial,
    bool clearSelectedSerial = false,
  }) =>
      DeployState(
        phase: phase ?? this.phase,
        installUrl: installUrl ?? this.installUrl,
        lastError: lastError ?? this.lastError,
        logs: logs ?? this.logs,
        devices: devices ?? this.devices,
        selectedSerial:
            clearSelectedSerial ? null : (selectedSerial ?? this.selectedSerial),
      );

  bool get isBusy =>
      phase == DeployPhase.checking || phase == DeployPhase.building;
}
