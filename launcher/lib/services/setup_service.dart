import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum StepStatus { pending, running, done, failed }

class SetupStep {
  final String id;
  final String label;
  StepStatus status;
  String? error;
  DateTime? timestamp;

  SetupStep({
    required this.id,
    required this.label,
    this.status = StepStatus.pending,
  });

  SetupStep copyWith({
    StepStatus? status,
    String? error,
    DateTime? timestamp,
  }) =>
      SetupStep(
        id: id,
        label: label,
      )
        ..status = status ?? this.status
        ..error = error ?? this.error
        ..timestamp = timestamp ?? this.timestamp;
}

class SetupService extends ChangeNotifier {
  final List<SetupStep> _steps = [
    SetupStep(id: 'check_node', label: 'Перевірка Node.js'),
    SetupStep(id: 'check_npm', label: 'Перевірка npm'),
    SetupStep(id: 'npm_install', label: 'npm install в server/'),
    SetupStep(id: 'check_env', label: 'Перевірка .env'),
  ];

  bool _isRunning = false;
  bool _isDone = false;
  String? _currentError;

  List<SetupStep> get steps => _steps;
  bool get isRunning => _isRunning;
  bool get isDone => _isDone;
  bool get canReset => !_isRunning;
  String? get currentError => _currentError;

  Future<void> runSetup() async {
    if (_isRunning) return;

    _isRunning = true;
    _isDone = false;
    _currentError = null;
    _resetSteps();
    notifyListeners();

    try {
      for (final step in _steps) {
        await _executeStep(step);
        if (step.status == StepStatus.failed) {
          _isRunning = false;
          notifyListeners();
          return;
        }
      }

      _isDone = true;
      _currentError = null;
    } catch (e) {
      _currentError = e.toString();
      _isDone = false;
    }

    _isRunning = false;
    notifyListeners();
  }

  Future<void> _executeStep(SetupStep step) async {
    step.status = StepStatus.running;
    step.timestamp = DateTime.now();
    notifyListeners();

    try {
      switch (step.id) {
        case 'check_node':
          await _checkNode();
          break;
        case 'check_npm':
          await _checkNpm();
          break;
        case 'npm_install':
          await _npmInstall();
          break;
        case 'check_env':
          await _checkEnv();
          break;
      }

      step.status = StepStatus.done;
      step.error = null;
    } catch (e) {
      step.status = StepStatus.failed;
      step.error = e.toString();
      rethrow;
    }

    notifyListeners();
  }

  Future<void> _checkNode() async {
    try {
      final result = await Process.run('node', ['--version']);
      if (result.exitCode != 0) {
        throw 'Node.js не встановлено. Встановіть з https://nodejs.org/';
      }
    } catch (e) {
      throw 'Node.js не знайдено в PATH. Встановіть з https://nodejs.org/';
    }
  }

  Future<void> _checkNpm() async {
    try {
      final result = await Process.run('npm', ['--version']);
      if (result.exitCode != 0) {
        throw 'npm не встановлено';
      }
    } catch (e) {
      throw 'npm не знайдено в PATH';
    }
  }

  Future<void> _npmInstall() async {
    final projectRoot = _getProjectRoot();
    final serverDir = Directory('${projectRoot.path}/server');

    final result = await Process.run(
      'npm',
      ['install'],
      workingDirectory: serverDir.path,
    );

    if (result.exitCode != 0) {
      throw 'npm install помилка: ${result.stderr}';
    }
  }

  Future<void> _checkEnv() async {
    final projectRoot = _getProjectRoot();
    final serverDir = Directory('${projectRoot.path}/server');
    final envFile = File('${serverDir.path}/.env');

    if (!envFile.existsSync()) {
      final exampleFile = File('${serverDir.path}/.env.example');
      if (exampleFile.existsSync()) {
        await exampleFile.copy(envFile.path);
      } else {
        throw '.env файл не знайдено. Створіть його вручну.';
      }
    }
  }

  void reset() {
    if (!canReset) return;
    _resetSteps();
    _isDone = false;
    _currentError = null;
    notifyListeners();
  }

  void _resetSteps() {
    for (final step in _steps) {
      step.status = StepStatus.pending;
      step.error = null;
      step.timestamp = null;
    }
  }

  Directory _getProjectRoot() {
    var current = Directory.current;
    while (current.path != current.parent.path) {
      if (File('${current.path}/pubspec.yaml').existsSync() &&
          Directory('${current.path}/server').existsSync()) {
        return current;
      }
      current = current.parent;
    }
    return Directory.current;
  }
}
