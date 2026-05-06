import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/server_control_service.dart';
import 'services/setup_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelCode Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C0D1),
          brightness: Brightness.dark,
        ),
      ),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SetupService()),
          ChangeNotifierProvider(create: (_) => ServerControlService()),
        ],
        child: const LauncherScreen(),
      ),
    );
  }
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SetupService>().runSetup();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PixelCode Launcher'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer<SetupService>(
        builder: (context, setup, _) {
          final statusColor = _statusColor(setup);

          final statusLabel = setup.currentError != null && !setup.isStreaming
              ? 'Помилка налаштування'
              : setup.isDone
                  ? 'Готово до запуску'
                  : setup.isStreaming
                      ? 'Claude налаштовує середовище...'
                      : setup.isRunning
                          ? 'Налаштування...'
                          : 'Готово до запуску';

          final buttonLabel = setup.isBusy
              ? 'Виконується...'
              : setup.isDone
                  ? 'Запустити знову'
                  : 'Розпочати';

          return Column(
            children: [
              // Progress bar while busy
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: setup.isBusy ? 3 : 0,
                child: setup.isBusy
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink(),
              ),

              // Status hero block
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  border: Border(
                    left: BorderSide(color: statusColor, width: 3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusDot(
                          color: statusColor,
                          isRunning: setup.isBusy,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: setup.isBusy ? null : () => setup.runSetup(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusColor,
                          disabledBackgroundColor:
                              statusColor.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          buttonLabel,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Setup steps list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: setup.steps.length,
                  itemBuilder: (context, index) {
                    return SetupStepTile(
                      step: setup.steps[index],
                      index: index,
                    );
                  },
                ),
              ),

              // Claude log panel — visible whenever there's log output
              if (setup.isLogVisible)
                ClaudeLogPanel(setup: setup),

              // Server control — start / stop / restart the daemon
              const _ServerControlCard(),

              // Bottom action buttons — always visible, faded when inactive.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Rollback
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: setup.canRollback || setup.isRollingBack ? 1.0 : 0.25,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: setup.canRollback
                                ? () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Видалити з системи?'),
                                        content: Text(
                                          'Буде видалено: ${setup.rollbackDescription}.\n\n'
                                          'Системні пакети (node, homebrew, claude) не чіпаємо.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Скасувати'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            child: const Text('Видалити'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) setup.rollback();
                                  }
                                : null,
                            icon: setup.isRollingBack
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  )
                                : const Icon(Icons.delete_sweep_outlined, size: 16),
                            label: Text(
                              setup.isRollingBack ? 'Видаляємо...' : 'Видалити з системи',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 40),
                              foregroundColor: Colors.red,
                              side: BorderSide(color: Colors.red.withValues(alpha: 0.6)),
                            ),
                          ),
                          if (setup.rollbackError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                setup.rollbackError!,
                                style: const TextStyle(fontSize: 11, color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Reset
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: setup.canReset && (setup.isDone || setup.currentError != null)
                          ? 1.0
                          : 0.25,
                      child: OutlinedButton(
                        onPressed: setup.canReset && (setup.isDone || setup.currentError != null)
                            ? () => setup.reset()
                            : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 40),
                        ),
                        child: const Text('Скинути'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _statusColor(SetupService setup) {
    if (setup.isStreaming) return const Color(0xFF00C0D1);
    if (setup.currentError != null) return Colors.red;
    if (setup.isDone) return Colors.green;
    if (setup.isRunning) return Colors.orange;
    return Colors.grey;
  }
}

// ─── Server control card ─────────────────────────────────────────────────────

class _ServerControlCard extends StatelessWidget {
  const _ServerControlCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerControlService>(
      builder: (context, ctrl, _) {
        final (dotColor, label) = _statusLabel(ctrl.phase);
        final buttons = _buildButtons(context, ctrl);

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: 0.06),
            border: Border(left: BorderSide(color: dotColor, width: 3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StatusDot(
                    color: dotColor,
                    isRunning: ctrl.isTransitioning || ctrl.actionBusy,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dotColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: buttons),
              ],
              if (ctrl.actionError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.actionError!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  (Color, String) _statusLabel(DaemonPhase phase) => switch (phase) {
        DaemonPhase.unknown  => (Colors.grey,                   'Перевірка стану серверу...'),
        DaemonPhase.offline  => (Colors.red,                    'Сервер вимкнено'),
        DaemonPhase.idle     => (Colors.orange,                 'Daemon активний · сервер зупинено'),
        DaemonPhase.starting => (const Color(0xFF00C0D1),       'Сервер запускається...'),
        DaemonPhase.running  => (Colors.green,                  'Сервер працює'),
        DaemonPhase.stopping => (Colors.orange,                 'Сервер зупиняється...'),
        DaemonPhase.crashed  => (Colors.red,                    'Сервер аварійно завершився'),
      };

  List<Widget> _buildButtons(BuildContext context, ServerControlService ctrl) {
    final busy = ctrl.actionBusy || ctrl.isTransitioning;

    Widget btn(String label, VoidCallback? onPressed, {Color? color}) {
      final c = color ?? Theme.of(context).colorScheme.primary;
      return Expanded(
        child: OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: c,
            side: BorderSide(color: c.withValues(alpha: busy ? 0.3 : 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c),
                )
              : Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
    }

    return switch (ctrl.phase) {
      DaemonPhase.unknown  => [],
      DaemonPhase.offline  => [btn('Запустити', ctrl.startDaemon)],
      DaemonPhase.idle     => [btn('Запустити сервер', ctrl.startServer)],
      DaemonPhase.starting => [btn('Запускається...', null)],
      DaemonPhase.running  => [
          btn('Перезапустити', ctrl.restartServer),
          const SizedBox(width: 8),
          btn('Зупинити', ctrl.stopServer, color: Colors.red),
        ],
      DaemonPhase.stopping => [btn('Зупиняється...', null)],
      DaemonPhase.crashed  => [btn('Запустити знову', ctrl.startServer)],
    };
  }
}

// ─── Claude log panel ────────────────────────────────────────────────────────

class ClaudeLogPanel extends StatefulWidget {
  final SetupService setup;
  const ClaudeLogPanel({super.key, required this.setup});

  @override
  State<ClaudeLogPanel> createState() => _ClaudeLogPanelState();
}

class _ClaudeLogPanelState extends State<ClaudeLogPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(ClaudeLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    final isStreaming = setup.isStreaming;

    final setupStep = setup.steps.firstWhere(
      (s) => s.id == 'setup',
      orElse: () => SetupStep(id: 'setup', label: ''),
    );
    final isFailed = setupStep.status == StepStatus.failed;

    final headerColor = isFailed
        ? Colors.orange
        : isStreaming
            ? const Color(0xFF00C0D1)
            : Colors.green;

    final headerText = isStreaming
        ? 'Claude налаштовує середовище...'
        : isFailed
            ? 'Налаштування не вдалося'
            : 'Claude завершив роботу';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border.all(color: headerColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                if (isStreaming)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(headerColor),
                    ),
                  )
                else
                  Icon(
                    isFailed ? Icons.warning_amber_rounded : Icons.check_circle,
                    size: 14,
                    color: headerColor,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headerText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: headerColor,
                    ),
                  ),
                ),
                if (isStreaming)
                  Text(
                    'Не закривайте вікно',
                    style: TextStyle(
                      fontSize: 10,
                      color: headerColor.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),

          // Log output
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: setup.setupLog.length,
              itemBuilder: (context, i) {
                final line = setup.setupLog[i];
                final isError = line.startsWith('[stderr]') || line.startsWith('✗');
                final isSuccess = line.startsWith('✓');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line.isEmpty ? ' ' : line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.5,
                      color: isError
                          ? Colors.red[300]
                          : isSuccess
                              ? Colors.green[300]
                              : Colors.grey[400],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step tile ───────────────────────────────────────────────────────────────

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool isRunning;

  const _StatusDot({required this.color, required this.isRunning});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    if (widget.isRunning) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.6),
                blurRadius: 6 + (_controller.value * 8),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SetupStepTile extends StatelessWidget {
  final SetupStep step;
  final int index;

  const SetupStepTile({super.key, required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusIcon = switch (step.status) {
      StepStatus.pending => Icon(
          Icons.radio_button_unchecked,
          size: 18,
          color: Colors.grey[600],
        ),
      StepStatus.running => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
      StepStatus.done => const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 18,
        ),
      StepStatus.failed => const Icon(
          Icons.cancel,
          color: Colors.red,
          size: 18,
        ),
    };

    final labelColor = switch (step.status) {
      StepStatus.pending => Colors.grey[500]!,
      StepStatus.running => Colors.grey[100]!,
      StepStatus.done    => Colors.grey[100]!,
      StepStatus.failed  => Colors.red,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              statusIcon,
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 13,
                    color: labelColor,
                    fontWeight: step.status == StepStatus.done
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  child: Text(step.label),
                ),
              ),
              if (step.timestamp != null)
                Text(
                  _formatTime(step.timestamp!),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
            ],
          ),
          if (step.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Text(
                step.error!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) =>
      '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}
