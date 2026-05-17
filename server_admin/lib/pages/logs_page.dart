import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../admin_client.dart';
import '../theme.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({
    super.key,
    required this.serverLogs,
    required this.bootLogs,
    required this.showingBoot,
  });

  final List<LogEntry> serverLogs;
  final List<BootLogEntry> bootLogs;
  final bool showingBoot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _LogsCard(
              serverLogs: serverLogs,
              bootLogs: bootLogs,
              showingBoot: showingBoot,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsCard extends StatelessWidget {
  const _LogsCard({
    required this.serverLogs,
    required this.bootLogs,
    required this.showingBoot,
  });

  final List<LogEntry> serverLogs;
  final List<BootLogEntry> bootLogs;
  final bool showingBoot;

  Color _levelColor(String level) => switch (level) {
        'warn'  => PixelPalette.warn,
        'error' => PixelPalette.error,
        _       => PixelPalette.textHigh,
      };

  @override
  Widget build(BuildContext context) {
    final title = showingBoot ? 'Boot logs' : 'Server logs';
    final subtitle = showingBoot
        ? '(stdout/stderr from launcher)'
        : '(structured log ring)';
    final isEmpty =
        showingBoot ? bootLogs.isEmpty : serverLogs.isEmpty;

    return PixelCard(
      title: title,
      titleColor: showingBoot ? PixelPalette.gold : PixelPalette.accent,
      expand: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              subtitle,
              style: const TextStyle(
                  color: PixelPalette.textLow,
                  fontSize: 11,
                  fontFamily: 'Menlo'),
            ),
          ),
          Expanded(
            child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF08080B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: PixelPalette.border),
            ),
            child: isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      showingBoot
                          ? '(no boot logs yet — try Start)'
                          : '(no log entries yet)',
                      style:
                          const TextStyle(color: PixelPalette.textLow),
                    ),
                  )
                : showingBoot
                    ? _AutoScrollList(
                        key: const ValueKey('boot-logs'),
                        itemCount: bootLogs.length,
                        itemBuilder: _buildBootLine,
                      )
                    : _AutoScrollList(
                        key: const ValueKey('server-logs'),
                        itemCount: serverLogs.length,
                        itemBuilder: _buildServerLine,
                      ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerLine(BuildContext context, int i) {
    final e = serverLogs[i];
    final ts = e.timestamp.toIso8601String().substring(11, 23);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(children: [
          TextSpan(
              text: '$ts ',
              style: const TextStyle(color: PixelPalette.textLow)),
          TextSpan(
              text: '[${e.category}] ',
              style: const TextStyle(color: PixelPalette.accent)),
          TextSpan(
              text: e.message,
              style: TextStyle(color: _levelColor(e.level))),
        ]),
        style: const TextStyle(
            fontFamily: 'Menlo', fontSize: 12, height: 1.45),
      ),
    );
  }

  Widget _buildBootLine(BuildContext context, int i) {
    final e = bootLogs[i];
    final ts = e.timestamp.toIso8601String().substring(11, 23);
    final color = e.stream == 'stderr'
        ? PixelPalette.warn
        : PixelPalette.textHigh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(children: [
          TextSpan(
              text: '$ts ',
              style: const TextStyle(color: PixelPalette.textLow)),
          TextSpan(
            text: '${e.stream.padRight(6)} ',
            style: TextStyle(color: color.withValues(alpha: 0.55)),
          ),
          TextSpan(text: e.line, style: TextStyle(color: color)),
        ]),
        style: const TextStyle(
            fontFamily: 'Menlo', fontSize: 12, height: 1.45),
      ),
    );
  }
}

class _AutoScrollList extends StatefulWidget {
  const _AutoScrollList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_AutoScrollList> createState() => _AutoScrollListState();
}

class _AutoScrollListState extends State<_AutoScrollList> {
  final ScrollController _controller = ScrollController();
  bool _stickToBottom = true;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.itemCount;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(_AutoScrollList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != _lastCount) {
      _lastCount = widget.itemCount;
      if (_stickToBottom) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  void _animateToBottom() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _enableStick() {
    setState(() => _stickToBottom = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction == ScrollDirection.forward ||
                n.direction == ScrollDirection.reverse) {
              if (_stickToBottom) {
                setState(() => _stickToBottom = false);
              }
            }
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.all(10),
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: _StickButton(
            active: _stickToBottom,
            onTap: _enableStick,
          ),
        ),
      ],
    );
  }
}

class _StickButton extends StatelessWidget {
  const _StickButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? PixelPalette.accent : PixelPalette.textMed;
    final bg = active
        ? PixelPalette.accent.withValues(alpha: 0.12)
        : PixelPalette.surfaceDim;
    final border = active ? PixelPalette.accent : PixelPalette.border;

    return Tooltip(
      message: active
          ? 'Auto-scroll: ON (tail follows newest)'
          : 'Auto-scroll: OFF — tap to follow newest',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active
                      ? Icons.vertical_align_bottom
                      : Icons.arrow_downward,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  active ? 'STICK TO BOTTOM' : 'JUMP TO BOTTOM',
                  style: TextStyle(
                    color: fg,
                    fontFamily: 'Menlo',
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
