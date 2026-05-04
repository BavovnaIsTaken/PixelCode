import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C0D1),
          brightness: Brightness.dark,
        ),
      ),
      home: ChangeNotifierProvider(
        create: (_) => SetupService(),
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
          final statusColor = setup.currentError != null
              ? Colors.red
              : setup.isDone
                  ? Colors.green
                  : Colors.orange;

          return Column(
            children: [
              // Status Hero Block
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
                          isRunning: setup.isRunning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            setup.currentError != null
                                ? 'Помилка налаштування'
                                : setup.isDone
                                    ? 'Налаштування завершено'
                                    : setup.isRunning
                                        ? 'Налаштування...'
                                        : 'Готово до запуску',
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
                        onPressed: setup.isRunning
                            ? null
                            : () => setup.runSetup(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusColor,
                          disabledBackgroundColor:
                              statusColor.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          setup.isRunning
                              ? 'Налаштування...'
                              : setup.isDone
                                  ? 'Запустити знову'
                                  : 'Розпочати',
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
              // Steps List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: setup.steps.length,
                  itemBuilder: (context, index) {
                    final step = setup.steps[index];
                    return SetupStepTile(
                      step: step,
                      index: index,
                    );
                  },
                ),
              ),
              // Reset Button
              if (setup.canReset)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: OutlinedButton(
                    onPressed: () => setup.reset(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                    ),
                    child: const Text('Скинути'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

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
    if (widget.isRunning) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _controller.stop();
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
        final blurRadius = 6 + (_controller.value * 8);
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.6),
                blurRadius: blurRadius,
                spreadRadius: 0,
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
    final statusIcon = switch (step.status) {
      StepStatus.pending => const Icon(Icons.radio_button_unchecked, size: 18),
      StepStatus.running => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      StepStatus.done =>
        const Icon(Icons.check_circle, color: Colors.green, size: 18),
      StepStatus.failed => const Icon(Icons.cancel, color: Colors.red, size: 18),
    };

    return AnimatedOpacity(
      opacity: 1,
      duration: Duration(milliseconds: 200 + (index * 50)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                statusIcon,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: step.status == StepStatus.failed
                          ? Colors.red
                          : Colors.grey[100],
                      fontWeight: step.status == StepStatus.done
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (step.timestamp != null)
                  Text(
                    _formatTime(step.timestamp!),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
            if (step.error != null)
              AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 300),
                child: Padding(
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
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}
