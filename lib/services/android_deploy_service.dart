import 'dart:async';

import '../models/agent_message.dart';
import 'agent_ws_service.dart';

export '../models/agent_message.dart' show AndroidDevice;

/// Сервіс для побудови та встановлення Android додатку (APK).
///
/// Відправляє команди на сервер через WebSocket.
/// Сервер будує APK та повертає URL для завантаження.
class AndroidDeployService {
  final AgentWsService? _wsService;
  StreamSubscription<ServerMessage>? _wsSub;

  AndroidDeployService({AgentWsService? wsService}) : _wsService = wsService;

  void dispose() {
    _wsSub?.cancel();
  }

  // ─── Dependency check ───────────────────────────────────────────────────

  /// Перевіряє, чи встановлено flutter + Android SDK на сервері.
  Future<bool> checkDependencies() async {
    final ws = _wsService;
    if (ws == null || !ws.isConnected) return false;

    final completer = Completer<bool>();
    late StreamSubscription<ServerMessage> sub;

    sub = ws.messages.listen((msg) {
      if (msg is AndroidDeployStatusMessage && msg.subtype == 'deps_result') {
        sub.cancel();
        completer.complete(msg.hasFlutter ?? false);
      }
    });

    ws.androidDeployCheck();

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        return false;
      },
    );
  }

  // ─── Device listing ─────────────────────────────────────────────────────

  /// Запитує список підключених пристроїв з сервера (через `adb devices -l`).
  Future<List<AndroidDevice>> listDevices() async {
    final ws = _wsService;
    if (ws == null || !ws.isConnected) return const [];

    final completer = Completer<List<AndroidDevice>>();
    late StreamSubscription<ServerMessage> sub;

    sub = ws.messages.listen((msg) {
      if (msg is AndroidDeployStatusMessage && msg.subtype == 'devices_list') {
        sub.cancel();
        completer.complete(msg.devices ?? const []);
      }
    });

    ws.androidDeployListDevices();

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        return const [];
      },
    );
  }

  // ─── Build & Deploy ─────────────────────────────────────────────────────

  /// Будує APK та повертає URL для завантаження.
  Future<bool> buildAndDeploy({
    required void Function(String) onProgress,
    required void Function(String) onError,
    required void Function(String installUrl) onInstallReady,
    String? deviceSerial,
  }) async {
    final ws = _wsService;
    if (ws == null || !ws.isConnected) {
      onError('Немає з\'єднання з сервером');
      return false;
    }

    final completer = Completer<bool>();

    _wsSub?.cancel();
    _wsSub = ws.messages.listen((msg) {
      if (msg is AndroidDeployStatusMessage) {
        switch (msg.subtype) {
          case 'log':
            if (msg.message != null) onProgress(msg.message!);
          case 'error':
            if (msg.message != null) onError(msg.message!);
          case 'install_ready':
            if (msg.installUrl != null) onInstallReady(msg.installUrl!);
          case 'complete':
            _wsSub?.cancel();
            _wsSub = null;
            if (!completer.isCompleted) {
              completer.complete(msg.success ?? false);
            }
        }
      }
    });

    ws.androidDeployStart(deviceSerial: deviceSerial);

    return completer.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        _wsSub?.cancel();
        _wsSub = null;
        onError('Таймаут операції (15 хвилин)');
        return false;
      },
    );
  }

  /// Скасувати поточний білд.
  void cancelDeploy() {
    _wsSub?.cancel();
    _wsSub = null;
    _wsService?.androidDeployCancel();
  }
}
