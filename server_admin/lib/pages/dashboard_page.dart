import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../admin_client.dart';
import '../theme.dart';
import '../services/server_control_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.launcher,
    required this.launcherError,
    required this.server,
    required this.inFlightAction,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onRefresh,
  });

  final LauncherStatus? launcher;
  final String? launcherError;
  final ServerStatus? server;
  final String? inFlightAction;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerControlService>(
      builder: (context, ctrl, _) {
        return RefreshIndicator(
          color: PixelPalette.accent,
          backgroundColor: PixelPalette.surface,
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(
                launcher: launcher,
                launcherError: launcherError,
                server: server,
                inFlightAction: inFlightAction,
                daemonBusy: ctrl.actionBusy,
                daemonError: ctrl.actionError,
                onStart: onStart,
                onStop: onStop,
                onRestart: onRestart,
                onStartDaemon: ctrl.startDaemon,
              ),
              if (server?.metrics != null) ...[
                const SizedBox(height: 16),
                _MetricsCard(metrics: server!.metrics!),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Status card ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.launcher,
    required this.launcherError,
    required this.server,
    required this.inFlightAction,
    required this.daemonBusy,
    required this.daemonError,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onStartDaemon,
  });

  final LauncherStatus? launcher;
  final String? launcherError;
  final ServerStatus? server;
  final String? inFlightAction;
  final bool daemonBusy;
  final String? daemonError;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final Future<void> Function() onStartDaemon;

  @override
  Widget build(BuildContext context) {
    return PixelCard(
      title: 'Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (launcher == null && launcherError != null) ...[
            _ErrorBlock(error: launcherError!),
            const SizedBox(height: 14),
            _SpawnDaemonRow(
              busy: daemonBusy,
              error: daemonError,
              onSpawn: onStartDaemon,
            ),
          ] else if (launcher == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Connecting to launcher…', style: TextStyle(color: PixelPalette.textMed)),
            )
          else ...[
            _ProcRow(
              label: 'LAUNCHER',
              up: true,
              detail: ':${launcher!.launcherPort}  PID ${launcher!.launcherPid}  (${launcher!.phase.name})',
            ),
            const SizedBox(height: 8),
            _ProcRow(
              label: 'SERVER',
              up: launcher!.serverRunning,
              detail: launcher!.serverRunning
                  ? ':${launcher!.serverPort}  PID ${launcher!.serverPid ?? "?"}'
                  : _offlineDetail(launcher!),
            ),
            if (server != null) ...[
              const SizedBox(height: 16),
              const Divider(color: PixelPalette.divider, height: 1),
              const SizedBox(height: 12),
              _kv('Working dir', server!.config.projectCwd,
                  source: server!.sourceOf('projectCwd'), mono: true),
              _kv('OTA hostname', server!.config.otaHostname ?? '(auto)',
                  source: server!.sourceOf('otaHostname')),
              _kv('Connected clients', '${server!.clients}'),
              _kv('mDNS', server!.mdnsActive ? 'active' : 'inactive'),
              _kv('Tailscale', server!.tailscaleUrl ?? '—', mono: true),
              _kv('Uptime', _fmtUptime(server!.uptimeMs)),
              _kv('Booted', server!.bootedAt.toLocal().toString()),
              _kv('Config file', server!.configPath, mono: true),
            ],
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (launcher != null && !launcher!.serverRunning)
                _ActionButton(
                  filled: true,
                  color: PixelPalette.success,
                  icon: Icons.play_arrow,
                  idleLabel: 'START',
                  busyLabel: 'STARTING…',
                  inFlight: inFlightAction == 'start',
                  disabled: inFlightAction != null,
                  onPressed: onStart,
                ),
              if (launcher != null && launcher!.serverRunning) ...[
                _ActionButton(
                  filled: false,
                  color: PixelPalette.accent,
                  icon: Icons.refresh,
                  idleLabel: 'RESTART',
                  busyLabel: 'RESTARTING…',
                  inFlight: inFlightAction == 'restart',
                  disabled: inFlightAction != null,
                  onPressed: onRestart,
                ),
                _ActionButton(
                  filled: false,
                  color: PixelPalette.error,
                  icon: Icons.power_settings_new,
                  idleLabel: 'STOP',
                  busyLabel: 'STOPPING…',
                  inFlight: inFlightAction == 'stop',
                  disabled: inFlightAction != null,
                  onPressed: onStop,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _offlineDetail(LauncherStatus l) {
    if (l.lastExitCode != null) {
      final sig = l.lastSignal != null ? ' signal=${l.lastSignal}' : '';
      return 'offline — last exit ${l.lastExitCode}$sig';
    }
    return 'offline — never started this session';
  }

  static Widget _kv(String label, String value,
      {String? source, bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: pixelFont(
                    size: 8, color: PixelPalette.textMed, letterSpacing: 1.2)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: PixelPalette.textHigh,
                    fontFamily: mono ? 'Menlo' : null,
                  ),
                ),
                if (source != null && source != 'file')
                  _SourceBadge(source: source),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtUptime(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ${s % 60}s';
    final h = m ~/ 60;
    if (h < 24) return '${h}h ${m % 60}m';
    return '${h ~/ 24}d ${h % 24}h';
  }
}

// ─── Action button with in-button progress ───────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.filled,
    required this.color,
    required this.icon,
    required this.idleLabel,
    required this.busyLabel,
    required this.inFlight,
    required this.disabled,
    required this.onPressed,
  });

  final bool filled;
  final Color color;
  final IconData icon;
  final String idleLabel;
  final String busyLabel;
  final bool inFlight;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spinnerColor = filled ? const Color(0xFF0A0A0F) : color;
    final iconWidget = inFlight
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: spinnerColor),
          )
        : Icon(icon, size: 16);
    final label = Text(inFlight ? busyLabel : idleLabel);
    final onTap = (disabled || inFlight) ? null : onPressed;

    return filled
        ? FilledButton.icon(
            onPressed: onTap,
            style: pixelFilledStyle(color: color),
            icon: iconWidget,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            style: pixelOutlinedStyle(foreground: color),
            icon: iconWidget,
            label: label,
          );
  }
}

// ─── Spawn daemon row (shown when launcher is offline) ───────────────────────

class _SpawnDaemonRow extends StatelessWidget {
  const _SpawnDaemonRow({
    required this.busy,
    required this.error,
    required this.onSpawn,
  });

  final bool busy;
  final String? error;
  final Future<void> Function() onSpawn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : () => onSpawn(),
          style: pixelFilledStyle(color: PixelPalette.accent),
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF0A0A0F)),
                )
              : const Icon(Icons.rocket_launch_outlined, size: 16),
          label: Text(busy ? 'SPAWNING…' : 'SPAWN DAEMON'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: const TextStyle(fontSize: 11, color: PixelPalette.error),
            ),
          ),
      ],
    );
  }
}

// ─── Proc row ─────────────────────────────────────────────────────────────────

class _ProcRow extends StatelessWidget {
  const _ProcRow(
      {required this.label, required this.up, required this.detail});

  final String label;
  final bool up;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = up ? PixelPalette.success : PixelPalette.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PixelPalette.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PixelPalette.border),
      ),
      child: Row(
        children: [
          GlowDot(color: color, size: 9),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child:
                Text(label, style: pixelFont(size: 9, color: color, letterSpacing: 1.4)),
          ),
          Expanded(
            child: SelectableText(
              detail,
              style: const TextStyle(
                  fontFamily: 'Menlo', fontSize: 12, color: PixelPalette.textMed),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error block (launcher offline) ──────────────────────────────────────────

class _ErrorBlock extends StatefulWidget {
  const _ErrorBlock({required this.error});

  final String error;

  @override
  State<_ErrorBlock> createState() => _ErrorBlockState();
}

class _ErrorBlockState extends State<_ErrorBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: 'pixelcode-server start'));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelPalette.error.withValues(alpha: 0.1),
        border: Border.all(color: PixelPalette.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAUNCHER UNAVAILABLE',
              style: pixelFont(size: 10, color: PixelPalette.error, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: PixelPalette.textMed, fontSize: 12),
              children: [
                const TextSpan(text: 'Or run manually: '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _copy,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _copied
                              ? PixelPalette.success.withValues(alpha: 0.2)
                              : PixelPalette.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'pixelcode-server start',
                              style: TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 12,
                                color: PixelPalette.textHigh,
                              ),
                            ),
                            if (_copied) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check,
                                  size: 12, color: PixelPalette.success),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Metrics card ─────────────────────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.metrics});

  final ServerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cpu = metrics.cpuPercent;
    final cpuLabel = cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%';
    final heapPct = metrics.heapTotal > 0
        ? (metrics.heapUsed / metrics.heapTotal * 100).toStringAsFixed(0)
        : '—';
    return PixelCard(
      title: 'Metrics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: 'CPU', value: cpuLabel),
              _MetricTile(label: 'RSS', value: _fmtBytes(metrics.rss)),
              _MetricTile(
                label: 'HEAP',
                value:
                    '${_fmtBytes(metrics.heapUsed)} / ${_fmtBytes(metrics.heapTotal)}  ($heapPct%)',
              ),
              _MetricTile(label: 'QUEUED', value: '${metrics.queuedTasks}'),
              _MetricTile(label: 'ACTIVE AGENTS', value: '${metrics.activeAgents}'),
              _MetricTile(
                label: 'RUNTIME',
                value: '${metrics.nodeVersion} · ${metrics.platform}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024.0;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PixelPalette.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PixelPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: pixelFont(
                size: 8, color: PixelPalette.textMed, letterSpacing: 1.4),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 13,
              color: PixelPalette.textHigh,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Source badge ─────────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final color = source == 'env' ? PixelPalette.warn : PixelPalette.accent;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(source.toUpperCase(),
          style: pixelFont(size: 7, color: color, letterSpacing: 1.2)),
    );
  }
}
