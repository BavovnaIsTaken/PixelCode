/// Network diagnostics widget — shown inside Settings → Мережа.
///
/// Renders 5 core health rows always, plus a collapsible "Додаткові перевірки"
/// group with 4 more. Each row shows a status indicator, a name, and a
/// contextual action (auto-fix or copyable instruction).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/health_provider.dart';

const _kCoreIds = <HealthItemId>[
  HealthItemId.tailscaleInstalled,
  HealthItemId.tailscaleRunning,
  HealthItemId.funnelActive,
  HealthItemId.serverListening,
  HealthItemId.clientConnected,
];

const _kExtraIds = <HealthItemId>[
  HealthItemId.iosSigning,
  HealthItemId.xcodeTools,
  HealthItemId.androidSdk,
  HealthItemId.androidSigning,
  HealthItemId.mdnsActive,
];

String _label(HealthItemId id) => switch (id) {
      HealthItemId.tailscaleInstalled => 'Tailscale CLI встановлений',
      HealthItemId.tailscaleRunning => 'Tailscale демон запущений',
      HealthItemId.funnelActive => 'Funnel активний',
      HealthItemId.serverListening => 'Сервер слухає порт',
      HealthItemId.clientConnected => 'Клієнт підключений до сервера',
      HealthItemId.iosSigning => 'iOS signing identity',
      HealthItemId.xcodeTools => 'Xcode Command Line Tools',
      HealthItemId.androidSdk => 'Android SDK / adb',
      HealthItemId.androidSigning => 'Android signing keystore',
      HealthItemId.mdnsActive => 'Bonjour / mDNS',
    };

class DiagnosticsSection extends ConsumerStatefulWidget {
  const DiagnosticsSection({super.key});

  @override
  ConsumerState<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<DiagnosticsSection> {
  bool _extrasExpanded = false;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    // Kick off first check after the frame so we don't touch providers in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _kicked) return;
      _kicked = true;
      ref.read(healthProvider.notifier).refreshAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(healthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Діагностика',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: state.refreshing
                  ? null
                  : () => ref.read(healthProvider.notifier).refreshAll(),
              icon: Icon(
                Icons.refresh,
                size: 15,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              label: Text(
                state.refreshing ? 'Перевірка…' : 'Оновити',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Перевірка компонентів, що потрібні для стабільної роботи серверу, '
          'віддаленого підключення та OTA-деплою.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        ..._kCoreIds.map((id) => _HealthRow(id: id, view: state.items[id])),
        const SizedBox(height: 10),
        _ExtrasToggle(
          expanded: _extrasExpanded,
          onTap: () => setState(() => _extrasExpanded = !_extrasExpanded),
        ),
        if (_extrasExpanded) ...[
          const SizedBox(height: 6),
          ..._kExtraIds.map((id) => _HealthRow(id: id, view: state.items[id])),
        ],
      ],
    );
  }
}

class _HealthRow extends ConsumerStatefulWidget {
  final HealthItemId id;
  final HealthItemView? view;

  const _HealthRow({required this.id, required this.view});

  @override
  ConsumerState<_HealthRow> createState() => _HealthRowState();
}

class _HealthRowState extends ConsumerState<_HealthRow> {
  bool _showInstruction = false;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final item = view?.item;
    final status = item?.status ?? HealthStatus.checking;
    final detail = item?.detail;
    final fixable = item?.fixable ?? false;
    final instruction = item?.instruction;
    final isFixing = view?.fixing ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(status: status, fixing: isFixing),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(widget.id),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildAction(status, fixable, instruction, isFixing),
            ],
          ),
          if (_showInstruction && instruction != null) ...[
            const SizedBox(height: 10),
            _InstructionPanel(text: instruction),
          ],
        ],
      ),
    );
  }

  Widget _buildAction(
    HealthStatus status,
    bool fixable,
    String? instruction,
    bool isFixing,
  ) {
    if (status != HealthStatus.fail) return const SizedBox.shrink();

    if (fixable) {
      return FilledButton(
        onPressed: isFixing
            ? null
            : () => ref.read(healthProvider.notifier).fix(widget.id),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00C0D1).withValues(alpha: 0.18),
          foregroundColor: const Color(0xFF00C0D1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: const Color(0xFF00C0D1).withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Text(isFixing ? 'Виправляю…' : 'Виправити'),
      );
    }

    if (instruction != null) {
      return TextButton(
        onPressed: () => setState(() => _showInstruction = !_showInstruction),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          _showInstruction ? 'Сховати' : 'Інструкція',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _StatusDot extends StatelessWidget {
  final HealthStatus status;
  final bool fixing;

  const _StatusDot({required this.status, required this.fixing});

  @override
  Widget build(BuildContext context) {
    if (status == HealthStatus.checking || fixing) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Color(0xFF00C0D1),
        ),
      );
    }
    final color = status == HealthStatus.ok
        ? const Color(0xFF4ADE80)
        : const Color(0xFFFF6B6B);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InstructionPanel extends StatelessWidget {
  final String text;

  const _InstructionPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Копіювати',
            icon: Icon(
              Icons.copy,
              size: 15,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
            },
          ),
        ],
      ),
    );
  }
}

class _ExtrasToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ExtrasToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              'Додаткові перевірки',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
