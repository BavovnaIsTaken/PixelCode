/// Global iOS deploy state — one-click build+install from the toolbar.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ios_deploy_service.dart';
import 'agent_provider.dart';

// ─── State ─────────────────────────────────────────────────────────────────

enum DeployPhase { idle, checking, building, ready, error }

class DeployState {
  final DeployPhase phase;
  final String? installUrl;
  final String? lastError;
  final List<String> logs;

  const DeployState({
    this.phase = DeployPhase.idle,
    this.installUrl,
    this.lastError,
    this.logs = const [],
  });

  DeployState copyWith({
    DeployPhase? phase,
    String? installUrl,
    String? lastError,
    List<String>? logs,
  }) =>
      DeployState(
        phase: phase ?? this.phase,
        installUrl: installUrl ?? this.installUrl,
        lastError: lastError ?? this.lastError,
        logs: logs ?? this.logs,
      );

  bool get isBusy =>
      phase == DeployPhase.checking || phase == DeployPhase.building;
}

// ─── Notifier ──────────────────────────────────────────────────────────────

class DeployNotifier extends Notifier<DeployState> {
  IOSDeployService? _service;

  @override
  DeployState build() => const DeployState();

  /// One-click: check deps → build → auto-open install URL.
  Future<void> deploy() async {
    if (state.isBusy) return;

    final ws = ref.read(wsServiceProvider);
    _service?.dispose();
    _service = IOSDeployService(wsService: ws);

    // Reset
    state = const DeployState(phase: DeployPhase.checking);

    // 1. Check dependencies
    _addLog('Перевірка залежностей...');
    final hasFlutter = await _service!.checkDependencies();
    if (!hasFlutter) {
      _addLog('[ПОМИЛКА] Flutter не знайдено на сервері');
      state = state.copyWith(
        phase: DeployPhase.error,
        lastError: 'Flutter не знайдено на сервері',
      );
      return;
    }
    _addLog('Flutter: OK');

    // 2. Build + deploy
    state = state.copyWith(phase: DeployPhase.building);
    _addLog('Запуск побудови IPA...');

    final result = await _service!.buildAndDeploy(
      onProgress: _addLog,
      onError: (msg) => _addLog('[ПОМИЛКА] $msg'),
      onInstallReady: (url) {
        state = state.copyWith(
          phase: DeployPhase.ready,
          installUrl: url,
        );
        _addLog('OTA: IPA готовий! Відкриваю встановлення...');
        _openUrl(url);
      },
    );

    if (result && state.phase == DeployPhase.building) {
      // Silent install via devicectl succeeded — no OTA needed
      _addLog('Додаток встановлено на пристрій!');
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

final iosDeployProvider =
    NotifierProvider<DeployNotifier, DeployState>(DeployNotifier.new);
