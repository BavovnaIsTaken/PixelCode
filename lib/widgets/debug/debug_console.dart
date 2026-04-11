/// Debug console panel — shows server logs, session lifecycle, WS events.
/// Temporary debugging tool.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';

class DebugConsole extends ConsumerStatefulWidget {
  const DebugConsole({super.key});

  @override
  ConsumerState<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends ConsumerState<DebugConsole> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  String _filter = 'all'; // all, session, sdk, ws, error

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    Future.delayed(const Duration(milliseconds: 30), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  List<DebugLogMessage> _filtered(List<DebugLogMessage> logs) {
    if (_filter == 'all') return logs;
    if (_filter == 'error') return logs.where((l) => l.level == 'error' || l.level == 'warn').toList();
    return logs.where((l) => l.category == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(debugLogProvider);
    final filtered = _filtered(logs);

    ref.listen(debugLogProvider, (_, _) => _scrollToBottom());

    return Container(
      color: const Color(0xFF0A0A0D),
      child: Column(
        children: [
          // Toolbar
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1F),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 13, color: Color(0xFF00C0D1)),
                const SizedBox(width: 6),
                Text(
                  'Консоль',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                // Filter chips
                ..._buildFilters(),
                const SizedBox(width: 6),
                Text(
                  _filter == 'all'
                      ? '${logs.length}'
                      : '${filtered.length} / ${logs.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                // Auto-scroll toggle
                _ToolbarButton(
                  icon: Icons.vertical_align_bottom_rounded,
                  active: _autoScroll,
                  tooltip: 'Автопрокрутка',
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                ),
                const SizedBox(width: 4),
                // Copy all
                _ToolbarButton(
                  icon: Icons.copy_rounded,
                  tooltip: 'Копіювати все',
                  onTap: () {
                    final text = filtered.map((l) {
                      final ts = _formatTime(l.timestamp);
                      return '$ts [${l.level}] [${l.category}] ${l.message}';
                    }).join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                  },
                ),
                const SizedBox(width: 4),
                // Clear log
                _ToolbarButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Очистити',
                  onTap: () => ref.read(debugLogProvider.notifier).clear(),
                ),
              ],
            ),
          ),
          // Log entries
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Очікування логів сервера...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.12),
                        fontSize: 11,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _LogEntry(log: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilters() {
    const filters = ['all', 'session', 'sdk', 'ws', 'error'];
    return filters.map((f) {
      final isActive = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF00C0D1).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              f.toUpperCase(),
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF00C0D1)
                    : Colors.white.withValues(alpha: 0.3),
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}.'
      '${dt.millisecond.toString().padLeft(3, '0')}';
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            icon,
            size: 14,
            color: active
                ? const Color(0xFF00C0D1)
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final DebugLogMessage log;

  const _LogEntry({required this.log});

  @override
  Widget build(BuildContext context) {
    final time =
        '${log.timestamp.hour.toString().padLeft(2, '0')}:'
        '${log.timestamp.minute.toString().padLeft(2, '0')}:'
        '${log.timestamp.second.toString().padLeft(2, '0')}.'
        '${log.timestamp.millisecond.toString().padLeft(3, '0')}';

    final (Color levelColor, String levelIcon) = switch (log.level) {
      'error' => (const Color(0xFFEF4444), 'ERR'),
      'warn' => (const Color(0xFFF59E0B), 'WRN'),
      'info' => (const Color(0xFF00C0D1), 'INF'),
      _ => (Colors.white.withValues(alpha: 0.3), 'DBG'),
    };

    final catColor = switch (log.category) {
      'session' => const Color(0xFF10B981),
      'sdk' => const Color(0xFF8B5CF6),
      'ws' => const Color(0xFF3B82F6),
      _ => Colors.white.withValues(alpha: 0.3),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 78,
            child: Text(
              time,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.18),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Level
          SizedBox(
            width: 26,
            child: Text(
              levelIcon,
              style: TextStyle(
                color: levelColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Category
          SizedBox(
            width: 52,
            child: Text(
              log.category,
              style: TextStyle(
                color: catColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Message
          Expanded(
            child: SelectableText(
              log.message,
              style: TextStyle(
                color: log.level == 'error'
                    ? const Color(0xFFEF4444)
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
