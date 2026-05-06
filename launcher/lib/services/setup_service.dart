import 'dart:async';
import 'dart:convert';
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
}

class SetupService extends ChangeNotifier {
  final List<SetupStep> _steps = [
    SetupStep(id: 'find_claude', label: 'Знаходимо Claude Code'),
    SetupStep(id: 'scan',        label: 'Аналіз середовища'),
    SetupStep(id: 'setup',       label: 'Налаштування'),
    SetupStep(id: 'verify',      label: 'Перевірка'),
  ];

  bool _isRunning = false;
  bool _isDone = false;
  String? _currentError;
  String? _claudePath;
  Map<String, String> _sysInfo = {};
  final List<String> _log = [];
  bool _isStreaming = false;

  // Rollback tracking — only undo what we created.
  bool _npmInstallRan = false;
  bool _envCreatedBySetup = false;
  bool _envExistedBefore = false;
  bool _isRollingBack = false;
  String? _rollbackError;

  List<SetupStep> get steps => _steps;
  bool get isRunning => _isRunning;
  bool get isDone => _isDone;
  String? get currentError => _currentError;
  List<String> get setupLog => List.unmodifiable(_log);
  bool get isStreaming => _isStreaming;
  bool get isLogVisible => _log.isNotEmpty;
  bool get isBusy => _isRunning || _isRollingBack;
  bool get canReset => !isBusy;
  bool get isRollingBack => _isRollingBack;
  String? get rollbackError => _rollbackError;

  // True when there's something we created that can be cleaned up.
  bool get canRollback =>
      !isBusy && (_npmInstallRan || _envCreatedBySetup);

  // Human-readable summary of what rollback will remove.
  String get rollbackDescription {
    final parts = <String>[];
    if (_npmInstallRan) parts.add('node_modules');
    if (_envCreatedBySetup) parts.add('.env');
    return parts.join(' та ');
  }

  Future<void> runSetup() async {
    if (isBusy) return;

    _isRunning = true;
    _isDone = false;
    _currentError = null;
    _claudePath = null;
    _sysInfo = {};
    _log.clear();
    _isStreaming = false;
    _npmInstallRan = false;
    _envCreatedBySetup = false;
    _envExistedBefore = false;
    _rollbackError = null;
    _resetSteps();
    notifyListeners();

    SetupStep? failedStep;
    for (final step in _steps) {
      await _executeStep(step);
      if (step.status == StepStatus.failed) {
        failedStep = step;
        break;
      }
    }

    _isRunning = false;
    _isDone = failedStep == null;
    notifyListeners();
  }

  Future<void> _executeStep(SetupStep step) async {
    step.status = StepStatus.running;
    step.timestamp = DateTime.now();
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 200));

    try {
      switch (step.id) {
        case 'find_claude': await _findClaude();
        case 'scan':        await _scan();
        case 'setup':       await _setup();
        case 'verify':      await _verify();
      }
      step.status = StepStatus.done;
      step.error = null;
    } catch (e) {
      step.status = StepStatus.failed;
      step.error = e.toString();
      _currentError = e.toString();
    }

    _isStreaming = false;
    notifyListeners();
  }

  // ─── Steps ────────────────────────────────────────────────────────────────

  Future<void> _findClaude() async {
    final r = await _shell('which claude');
    if (r.exitCode != 0) {
      throw 'Claude Code CLI не знайдено.\n'
            'Встановіть з https://claude.ai/code і перезапустіть лаунчер.';
    }
    _claudePath = r.stdout.toString().trim();
  }

  Future<void> _scan() async {
    final serverDir = _serverDir();
    _envExistedBefore = File('$serverDir/.env').existsSync();

    final results = await Future.wait([
      _shell('uname -m'),
      _shell('sw_vers -productVersion'),
      _shell('which brew'),
      _shell('node --version'),
      _shell('npm --version'),
    ]);
    _sysInfo = {
      'arch':  results[0].stdout.toString().trim(),
      'macos': results[1].stdout.toString().trim(),
      'brew':  results[2].exitCode == 0 ? results[2].stdout.toString().trim() : 'not installed',
      'node':  results[3].exitCode == 0 ? results[3].stdout.toString().trim() : 'not installed',
      'npm':   results[4].exitCode == 0 ? results[4].stdout.toString().trim() : 'not installed',
    };
  }

  Future<void> _setup() async {
    final nodeOk = _sysInfo['node'] != 'not installed';
    final npmOk  = _sysInfo['npm']  != 'not installed';
    final serverDir = _serverDir();

    if (nodeOk && npmOk) {
      final installResult = await _shell('npm install', workingDirectory: serverDir);
      if (installResult.exitCode != 0) {
        throw 'npm install помилка:\n${installResult.stderr}';
      }
      _npmInstallRan = true;

      if (!_envExistedBefore) {
        await _createEnv(serverDir);
      }
      return;
    }

    // Something is missing — delegate to Claude.
    _isStreaming = true;
    notifyListeners();

    final projectRoot = _projectRoot();
    final branch = (await _shell('git branch --show-current', workingDirectory: projectRoot))
        .stdout.toString().trim();

    _addLog('Передаємо управління Claude Code...');
    _addLog('');

    final home = Platform.environment['HOME'] ?? '';
    // Prompt passed via env var — avoids shell quoting issues with multiline text.
    final script = '''
export HOME="$home"
[ -f /etc/zprofile ]      && . /etc/zprofile
[ -f ~/.zprofile ]        && . ~/.zprofile
[ -f ~/.zshrc ]           && . ~/.zshrc
[ -s ~/.nvm/nvm.sh ]      && . ~/.nvm/nvm.sh
[ -d ~/.volta/bin ]       && export VOLTA_HOME=~/.volta && export PATH="\$VOLTA_HOME/bin:\$PATH"
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH"
"$_claudePath" --dangerously-skip-permissions -p "\$_PIXELCODE_PROMPT"
''';

    final env = Map<String, String>.from(Platform.environment)
      ..['_PIXELCODE_PROMPT'] = _buildSetupPrompt(projectRoot, branch);

    final process = await Process.start(
      '/bin/zsh', ['-c', script],
      workingDirectory: projectRoot,
      environment: env,
    );

    final sub1 = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) { if (line.trim().isNotEmpty) _addLog(line); });

    final sub2 = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) { if (line.trim().isNotEmpty) _addLog('[stderr] $line'); });

    final exitCode = await process.exitCode;
    await Future.wait([sub1.cancel(), sub2.cancel()]);

    if (exitCode != 0) {
      throw 'Claude завершився з кодом $exitCode. Перевірте лог вище.';
    }

    _npmInstallRan = true;
    // Mark .env as ours only if it wasn't there before.
    if (!_envExistedBefore && File('$serverDir/.env').existsSync()) {
      _envCreatedBySetup = true;
    }

    _addLog('');
    _addLog('✓ Claude завершив роботу');
  }

  Future<void> _verify() async {
    final nodeResult = await _shell('node --version');
    if (nodeResult.exitCode != 0) {
      throw 'Node.js не знайдено після налаштування.\nПеревірте лог і спробуйте ще раз.';
    }
    if (!File('${_serverDir()}/.env').existsSync()) {
      throw 'server/.env не знайдено.\nДодайте ANTHROPIC_API_KEY до server/.env';
    }
  }

  // ─── Rollback ─────────────────────────────────────────────────────────────

  Future<void> rollback() async {
    if (!canRollback) return;

    _isRollingBack = true;
    _rollbackError = null;
    notifyListeners();

    try {
      final serverDir = _serverDir();

      if (_npmInstallRan) {
        final nodeModules = Directory('$serverDir/node_modules');
        if (nodeModules.existsSync()) {
          await nodeModules.delete(recursive: true);
        }
      }

      // Only remove .env if we created it — never touch a pre-existing file.
      if (_envCreatedBySetup) {
        final envFile = File('$serverDir/.env');
        if (envFile.existsSync()) await envFile.delete();
      }

      _npmInstallRan = false;
      _envCreatedBySetup = false;
      _isDone = false;
      _currentError = null;
      _log.clear();
      _sysInfo = {};
      _claudePath = null;
      _isStreaming = false;
      _resetSteps();
    } catch (e) {
      _rollbackError = e.toString();
    }

    _isRollingBack = false;
    notifyListeners();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _createEnv(String serverDir) async {
    final example = File('$serverDir/.env.example');
    if (example.existsSync()) {
      await example.copy('$serverDir/.env');
    } else {
      await File('$serverDir/.env').writeAsString('ANTHROPIC_API_KEY=sk-ant-REPLACE_ME\n');
    }
    _envCreatedBySetup = true;
  }

  void _addLog(String line) {
    _log.add(line);
    notifyListeners();
  }

  String _buildSetupPrompt(String projectRoot, String branch) => '''
Set up the PixelCode developer environment. Run everything non-interactively without asking for confirmation.

System state:
- macOS ${_sysInfo['macos']} (${_sysInfo['arch']})
- Homebrew: ${_sysInfo['brew']}
- Node.js:  ${_sysInfo['node']}
- npm:      ${_sysInfo['npm']}
- server/.env: ${File('$projectRoot/server/.env').existsSync() ? 'exists' : 'missing'}
- Project root: $projectRoot
- Git branch: $branch

Playbook — skip steps that are already satisfied, execute the rest:
1. Node.js missing → install via Homebrew: brew install node
   Homebrew itself missing → install it non-interactively first, then retry node
2. npm missing → ships with Node.js; if still absent → brew install npm
3. Run: cd "$projectRoot/server" && npm install
4. server/.env missing → copy "$projectRoot/server/.env.example" if it exists,
   otherwise create "$projectRoot/server/.env" with: ANTHROPIC_API_KEY=sk-ant-REPLACE_ME
5. Verify: node --version && npm --version && ls "$projectRoot/server/.env"

End with one paragraph summarising what was installed or configured.
Do NOT commit or push — this is environment setup only.
''';

  // macOS sandbox (app-sandbox=false in entitlements) allows spawning subprocesses,
  // but we still route through /bin/zsh and source profile files to get a full PATH
  // (homebrew, nvm, volta) that GUI apps don't inherit by default.
  Future<ProcessResult> _shell(String command, {String? workingDirectory}) {
    final home = Platform.environment['HOME'] ?? '';
    final wrapped = '''
export HOME="$home"
[ -f /etc/zprofile ]      && . /etc/zprofile
[ -f ~/.zprofile ]        && . ~/.zprofile
[ -f ~/.zshrc ]           && . ~/.zshrc
[ -s ~/.nvm/nvm.sh ]      && . ~/.nvm/nvm.sh
[ -d ~/.volta/bin ]       && export VOLTA_HOME=~/.volta && export PATH="\$VOLTA_HOME/bin:\$PATH"
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH"
$command
''';
    return Process.run(
      '/bin/zsh', ['-c', wrapped],
      environment: Platform.environment,
      workingDirectory: workingDirectory,
    );
  }

  void reset() {
    if (!canReset) return;
    _resetSteps();
    _isDone = false;
    _currentError = null;
    _claudePath = null;
    _sysInfo = {};
    _log.clear();
    _isStreaming = false;
    _npmInstallRan = false;
    _envCreatedBySetup = false;
    _envExistedBefore = false;
    _rollbackError = null;
    notifyListeners();
  }

  void _resetSteps() {
    for (final step in _steps) {
      step.status = StepStatus.pending;
      step.error = null;
      step.timestamp = null;
    }
  }

  // ─── Path resolution ───────────────────────────────────────────────────────

  String _projectRoot() {
    var current = Directory.current;
    while (current.path != current.parent.path) {
      if (File('${current.path}/server/package.json').existsSync()) return current.path;
      current = current.parent;
    }
    var dir = File(Platform.resolvedExecutable).parent;
    while (dir.path != dir.parent.path) {
      if (File('${dir.path}/server/package.json').existsSync()) return dir.path;
      dir = dir.parent;
    }
    return Directory.current.path;
  }

  String _serverDir() => '${_projectRoot()}/server';
}
