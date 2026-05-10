import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/setup_service.dart';
import '../theme.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SetupService>(
      builder: (context, setup, _) {
        final statusColor = _statusColor(setup);
        final statusLabel = setup.currentError != null && !setup.isStreaming
            ? 'Помилка налаштування'
            : setup.isDone
                ? 'Готово до запуску'
                : setup.isProbing
                    ? 'Перевірка середовища...'
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
            // Progress bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: setup.isBusy ? 3 : 0,
              child: setup.isBusy
                  ? LinearProgressIndicator(color: PixelPalette.accent)
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
                      _AnimatedDot(color: statusColor, isRunning: setup.isBusy),
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

            // Setup steps
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: setup.steps.length,
                itemBuilder: (context, index) =>
                    SetupStepTile(step: setup.steps[index]),
              ),
            ),

            // Claude log panel
            if (setup.isLogVisible) _ClaudeLogPanel(setup: setup),

            // Bottom actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity:
                        setup.canRollback || setup.isRollingBack ? 1.0 : 0.25,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: setup.canRollback
                              ? () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: PixelPalette.surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: const BorderSide(
                                            color: PixelPalette.border),
                                      ),
                                      title: Text('Видалити з системи?',
                                          style: pixelFont(
                                              size: 11,
                                              color: PixelPalette.error)),
                                      content: Text(
                                        'Буде видалено: ${setup.rollbackDescription}.\n\n'
                                        'Системні пакети (node, homebrew, claude) не чіпаємо.',
                                        style: const TextStyle(
                                            color: PixelPalette.textHigh),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text('Скасувати',
                                              style: pixelFont(
                                                  size: 9,
                                                  color: PixelPalette.textMed)),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: TextButton.styleFrom(
                                              foregroundColor:
                                                  PixelPalette.error),
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
                                    color: PixelPalette.error,
                                  ),
                                )
                              : const Icon(Icons.delete_sweep_outlined,
                                  size: 16),
                          label: Text(setup.isRollingBack
                              ? 'Видаляємо...'
                              : 'Видалити з системи'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                            foregroundColor: PixelPalette.error,
                            side: BorderSide(
                                color: PixelPalette.error.withValues(alpha: 0.6)),
                          ),
                        ),
                        if (setup.rollbackError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              setup.rollbackError!,
                              style: const TextStyle(
                                  fontSize: 11, color: PixelPalette.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: setup.canReset &&
                            (setup.isDone || setup.currentError != null)
                        ? 1.0
                        : 0.25,
                    child: OutlinedButton(
                      onPressed: setup.canReset &&
                              (setup.isDone || setup.currentError != null)
                          ? () => setup.reset()
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                        foregroundColor: PixelPalette.textMed,
                        side: const BorderSide(color: PixelPalette.border),
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
    );
  }

  Color _statusColor(SetupService setup) {
    if (setup.isStreaming) return PixelPalette.accent;
    if (setup.currentError != null) return PixelPalette.error;
    if (setup.isDone) return PixelPalette.success;
    if (setup.isRunning || setup.isProbing) return PixelPalette.warn;
    return PixelPalette.textMed;
  }
}

// ─── Step tile ────────────────────────────────────────────────────────────────

class SetupStepTile extends StatelessWidget {
  const SetupStepTile({super.key, required this.step});

  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final statusIcon = switch (step.status) {
      StepStatus.pending => Icon(Icons.radio_button_unchecked,
          size: 18, color: PixelPalette.textLow),
      StepStatus.running => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(PixelPalette.accent),
          ),
        ),
      StepStatus.done =>
        const Icon(Icons.check_circle, color: PixelPalette.success, size: 18),
      StepStatus.failed =>
        const Icon(Icons.cancel, color: PixelPalette.error, size: 18),
    };

    final labelColor = switch (step.status) {
      StepStatus.pending => PixelPalette.textLow,
      StepStatus.running => PixelPalette.textHigh,
      StepStatus.done    => PixelPalette.textHigh,
      StepStatus.failed  => PixelPalette.error,
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
                  _fmt(step.timestamp!),
                  style: const TextStyle(
                      fontSize: 11, color: PixelPalette.textLow),
                ),
            ],
          ),
          if (step.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Text(
                step.error!,
                style: const TextStyle(
                    fontSize: 11, color: PixelPalette.error, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

// ─── Claude log panel ─────────────────────────────────────────────────────────

class _ClaudeLogPanel extends StatefulWidget {
  const _ClaudeLogPanel({required this.setup});

  final SetupService setup;

  @override
  State<_ClaudeLogPanel> createState() => _ClaudeLogPanelState();
}

class _ClaudeLogPanelState extends State<_ClaudeLogPanel> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_ClaudeLogPanel old) {
    super.didUpdateWidget(old);
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
        ? PixelPalette.warn
        : isStreaming
            ? PixelPalette.accent
            : PixelPalette.success;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerColor.withValues(alpha: 0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
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
                    isFailed
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
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
                        color: headerColor.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: setup.setupLog.length,
              itemBuilder: (context, i) {
                final line = setup.setupLog[i];
                final isError =
                    line.startsWith('[stderr]') || line.startsWith('✗');
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
                          ? PixelPalette.error
                          : isSuccess
                              ? PixelPalette.success
                              : PixelPalette.textMed,
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

// ─── Animated dot ─────────────────────────────────────────────────────────────

class _AnimatedDot extends StatefulWidget {
  const _AnimatedDot({required this.color, required this.isRunning});

  final Color color;
  final bool isRunning;

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    if (widget.isRunning) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedDot old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !old.isRunning) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isRunning && old.isRunning) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context2, child2) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.6),
              blurRadius: 6 + (_ctrl.value * 8),
            ),
          ],
        ),
      ),
    );
  }
}
