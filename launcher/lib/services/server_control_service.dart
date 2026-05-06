import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum DaemonPhase { unknown, offline, idle, starting, running, stopping, crashed }

class ServerControlService extends ChangeNotifier {
  static const _host = '127.0.0.1';
  static const _port = 9719;
  static const _pollInterval = Duration(milliseconds: 2500);

  Timer? _pollTimer;
  DaemonPhase _phase = DaemonPhase.unknown;
  bool _actionBusy = false;
  String? _actionError;

  DaemonPhase get phase => _phase;
  bool get daemonOnline => _phase != DaemonPhase.unknown && _phase != DaemonPhase.offline;
  bool get serverRunning => _phase == DaemonPhase.running;
  bool get actionBusy => _actionBusy;
  String? get actionError => _actionError;
  bool get isTransitioning => _phase == DaemonPhase.starting || _phase == DaemonPhase.stopping;

  ServerControlService() {
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollOnce();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final phase = await _fetchPhase();
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  Future<DaemonPhase> _fetchPhase() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client
          .getUrl(Uri(scheme: 'http', host: _host, port: _port, path: '/launcher/status'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) return DaemonPhase.offline;
      final j = jsonDecode(body) as Map<String, dynamic>;
      final raw = (j['launcher'] as Map<String, dynamic>)['phase'] as String?;
      return _parsePhase(raw);
    } catch (_) {
      return DaemonPhase.offline;
    } finally {
      client?.close(force: true);
    }
  }

  static DaemonPhase _parsePhase(String? raw) => switch (raw) {
        'starting' => DaemonPhase.starting,
        'running'  => DaemonPhase.running,
        'stopping' => DaemonPhase.stopping,
        'crashed'  => DaemonPhase.crashed,
        _          => DaemonPhase.idle,
      };

  /// Spawns `pixelcode-server start` as a detached daemon (survives launcher close).
  Future<void> startDaemon() async {
    if (_actionBusy) return;
    _actionBusy = true;
    _actionError = null;
    notifyListeners();
    try {
      final home = Platform.environment['HOME'] ?? '';
      final script = '''
export HOME="$home"
[ -f /etc/zprofile ]      && . /etc/zprofile
[ -f ~/.zprofile ]        && . ~/.zprofile
[ -f ~/.zshrc ]           && . ~/.zshrc
[ -s ~/.nvm/nvm.sh ]      && . ~/.nvm/nvm.sh
[ -d ~/.volta/bin ]       && export VOLTA_HOME=~/.volta && export PATH="\$VOLTA_HOME/bin:\$PATH"
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH"
exec pixelcode-server start
''';
      await Process.start(
        '/bin/zsh',
        ['-c', script],
        mode: ProcessStartMode.detached,
        environment: Platform.environment,
      );
      // Poll until daemon binds its port (up to ~5 s).
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final phase = await _fetchPhase();
        if (phase != DaemonPhase.offline) {
          _phase = phase;
          break;
        }
      }
    } catch (e) {
      _actionError = e.toString();
    }
    _actionBusy = false;
    notifyListeners();
  }

  Future<void> startServer()   => _httpAction('start');
  Future<void> stopServer()    => _httpAction('stop');
  Future<void> restartServer() => _httpAction('restart');

  Future<void> _httpAction(String name) async {
    if (_actionBusy) return;
    _actionBusy = true;
    _actionError = null;
    notifyListeners();
    HttpClient? client;
    try {
      client = HttpClient();
      final req = await client.postUrl(
        Uri(scheme: 'http', host: _host, port: _port, path: '/launcher/$name'),
      );
      req.headers.contentLength = 0;
      final res = await req.close().timeout(const Duration(seconds: 30));
      await res.drain<void>();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _actionError = 'HTTP ${res.statusCode}';
      }
      await _pollOnce();
    } catch (e) {
      _actionError = e.toString();
    } finally {
      client?.close(force: true);
    }
    _actionBusy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
