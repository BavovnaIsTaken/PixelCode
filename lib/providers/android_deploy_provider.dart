/// Global Android deploy state — one-click build+install from the toolbar.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_message.dart' show AndroidDeployStatusMessage, AndroidDevice;
import '../models/deploy_state.dart';
import '../services/android_deploy_service.dart';
import 'agent_provider.dart';

// ─── Notifier ──────────────────────────────────────────────────────────────

class AndroidDeployNotifier extends Notifier<DeployState> {
  AndroidDeployService? _service;
  StreamSubscription? _deviceWatchSub;

  @override
  DeployState build() => const DeployState();

  // ─── Device watching ──────────────────────────────────────────────────────

  void startWatchingDevices() {
    final ws = ref.read(wsServiceProvider);
    _deviceWatchSub?.cancel();
    _deviceWatchSub = ws.messages.listen((msg) {
      if (msg is AndroidDeployStatusMessage && msg.subtype == 'devices_list') {
        _onDevicesList(msg.devices ?? const []);
      }
    });
    ws.androidDeployWatchDevices();
  }

  void stopWatchingDevices() {
    _deviceWatchSub?.cancel();
    _deviceWatchSub = null;
    ref.read(wsServiceProvider).androidDeployUnwatchDevices();
  }

  void _onDevicesList(List<AndroidDevice> devices) {
    final currentSerial = state.selectedSerial;
    final stillThere = devices.any(
      (d) => d.serial == currentSerial && d.isReady,
    );
    final autoPick = devices.firstWhere(
      (d) => d.isReady,
      orElse: () => const AndroidDevice(serial: '', model: '', state: ''),
    );
    final nextSerial = stillThere
        ? currentSerial
        : (autoPick.serial.isEmpty ? null : autoPick.serial);

    state = state.copyWith(
      devices: devices,
      selectedSerial: nextSerial,
      clearSelectedSerial: nextSerial == null,
    );
  }

  void selectDevice(String serial) {
    state = state.copyWith(selectedSerial: serial);
  }

  // ─── Deploy ───────────────────────────────────────────────────────────────

  /// One-click: check deps → build → serve APK download URL.
  Future<void> deploy() async {
    if (state.isBusy) return;

    final ws = ref.read(wsServiceProvider);
    _service?.dispose();
    _service = AndroidDeployService(wsService: ws);

    // Reset — keep devices list + current selection.
    state = DeployState(
      phase: DeployPhase.checking,
      devices: state.devices,
      selectedSerial: state.selectedSerial,
    );

    // 1. Check dependencies
    _addLog('Перевірка залежностей...');
    final hasFlutter = await _service!.checkDependencies();
    if (!hasFlutter) {
      _addLog('[ПОМИЛКА] Flutter / Android SDK не знайдено на сервері');
      state = state.copyWith(
        phase: DeployPhase.error,
        lastError: 'Flutter / Android SDK не знайдено на сервері',
      );
      return;
    }
    _addLog('Flutter + Android SDK: OK');

    // 2. Build + deploy
    state = state.copyWith(phase: DeployPhase.building);
    final target = state.selectedSerial;
    _addLog(target != null
        ? 'Запуск побудови APK для пристрою $target...'
        : 'Запуск побудови APK...');

    final result = await _service!.buildAndDeploy(
      deviceSerial: target,
      onProgress: _addLog,
      onError: (msg) => _addLog('[ПОМИЛКА] $msg'),
      onInstallReady: (url) {
        state = state.copyWith(
          phase: DeployPhase.ready,
          installUrl: url,
        );
        _addLog('APK готовий! Відкриваю завантаження...');
        _openUrl(url);
      },
    );

    if (result && state.phase == DeployPhase.building) {
      _addLog('APK встановлено на пристрій!');
      state = state.copyWith(phase: DeployPhase.idle);
    } else if (!result && state.phase != DeployPhase.ready) {
      state = state.copyWith(
        phase: DeployPhase.error,
        lastError: 'Помилка при побудові',
      );
    }
  }

  void cancel() {
    _service?.cancelDeploy();
    _addLog('Скасовано.');
    state = state.copyWith(phase: DeployPhase.idle);
  }

  void openInstallUrl() {
    if (state.installUrl != null) _openUrl(state.installUrl!);
  }

  void _addLog(String msg) {
    final logs = [...state.logs, msg];
    if (logs.length > 1000) logs.removeRange(0, logs.length - 1000);
    state = state.copyWith(logs: logs);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _addLog('[ПОМИЛКА] Не вдалося відкрити URL');
    }
  }
}

// ─── Provider ──────────────────────────────────────────────────────────────

final androidDeployProvider =
    NotifierProvider<AndroidDeployNotifier, DeployState>(
        AndroidDeployNotifier.new);
