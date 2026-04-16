import 'dart:async';

import '../models/agent_message.dart';
import 'agent_ws_service.dart';

/// Сервіс для побудови та OTA-встановлення iOS додатку.
///
/// Завжди відправляє команди на сервер через WebSocket.
/// Сервер будує IPA, генерує OTA manifest, та повертає install URL.
class IOSDeployService {
  final AgentWsService? _wsService;
  StreamSubscription<ServerMessage>? _wsSub;

  IOSDeployService({AgentWsService? wsService}) : _wsService = wsService;

  void dispose() {
    _wsSub?.cancel();
  }

  // ─── Dependency check ───────────────────────────────────────────────────

  /// Перевіряє, чи встановлено flutter на сервері.
  Future<bool> checkDependencies() async {
    final ws = _wsService;
    if (ws == null || !ws.isConnected) return false;

    final completer = Completer<bool>();
    late StreamSubscription<ServerMessage> sub;

    sub = ws.messages.listen((msg) {
      if (msg is IOSDeployStatusMessage && msg.subtype == 'deps_result') {
        sub.cancel();
        completer.complete(msg.hasFlutter ?? false);
      }
    });

    ws.iosDeployCheck();

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        return false;
      },
    );
  }

  // ─── Build & OTA Deploy ─────────────────────────────────────────────────

  /// Будує IPA та повертає OTA install URL.
  ///
  /// [onProgress] — лог повідомлення.
  /// [onError] — помилки.
  /// [onInstallReady] — викликається коли IPA готовий з itms-services:// URL.
  Future<bool> buildAndDeploy({
    required void Function(String) onProgress,
    required void Function(String) onError,
    required void Function(String installUrl) onInstallReady,
  }) async {
    final ws = _wsService;
    if (ws == null || !ws.isConnected) {
      onError('Немає з\'єднання з сервером');
      return false;
    }

    final completer = Completer<bool>();

    _wsSub?.cancel();
    _wsSub = ws.messages.listen((msg) {
      if (msg is IOSDeployStatusMessage) {
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

    ws.iosDeployStart();

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
    _wsService?.iosDeployCancel();
  }
}
