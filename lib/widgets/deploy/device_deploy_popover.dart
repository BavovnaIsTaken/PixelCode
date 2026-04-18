/// Popover with Android / iOS tabs for one-click device deploy.
///
/// Opened from the phone icon in the title bar. Each tab owns a single
/// responsibility: showing deploy state + action button for its platform.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart' show AndroidDevice;
import '../../models/app_theme.dart';
import '../../providers/android_deploy_provider.dart';
import '../../providers/ios_deploy_provider.dart';

// ─── Public entry point ──────────────────────────────────────────────────

/// Shows the deploy popover anchored below [anchor].
OverlayEntry showDeviceDeployPopover({
  required BuildContext context,
  required Offset anchor,
  required VoidCallback onDismiss,
}) {
  final entry = OverlayEntry(
    builder: (_) => _DeployPopover(
      anchor: anchor,
      onDismiss: onDismiss,
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}

// ─── Popover shell ──────────────────────────────────────────────────────

class _DeployPopover extends ConsumerStatefulWidget {
  const _DeployPopover({required this.anchor, required this.onDismiss});

  final Offset anchor;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_DeployPopover> createState() => _DeployPopoverState();
}

class _DeployPopoverState extends ConsumerState<_DeployPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  )..forward();

  int _tabIndex = 0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  static const _popoverWidth = 280.0;
  static const _edgeMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final rawLeft = widget.anchor.dx - _popoverWidth / 2;
        final left = rawLeft.clamp(
          _edgeMargin,
          (maxWidth - _popoverWidth - _edgeMargin)
              .clamp(_edgeMargin, double.infinity),
        );
        final top = widget.anchor.dy
            .clamp(_edgeMargin, (maxHeight - _edgeMargin).clamp(_edgeMargin, double.infinity));

        return Stack(
          children: [
            // Dismiss layer
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
              ),
            ),
            // Popover
            Positioned(
              left: left,
              top: top,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  final t = Curves.easeOut.transform(_anim.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, -4 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: _popoverWidth,
                    decoration: BoxDecoration(
                      color: tc.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tc.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TabBar(
                          index: _tabIndex,
                          onChanged: (i) => setState(() => _tabIndex = i),
                        ),
                        Container(height: 1, color: tc.divider),
                        IndexedStack(
                          index: _tabIndex,
                          children: const [
                            _AndroidTab(),
                            _IOSTab(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Tab bar ────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _tabs = [
    (Icons.phone_android, 'Android'),
    (Icons.phone_iphone, 'iOS'),
  ];

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          for (int i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: i == index
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tabs[i].$1,
                        size: 14,
                        color: i == index ? tc.textHigh : tc.textLow,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _tabs[i].$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              i == index ? FontWeight.w600 : FontWeight.normal,
                          color: i == index ? tc.textHigh : tc.textLow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Android tab ────────────────────────────────────────────────────────

class _AndroidTab extends ConsumerStatefulWidget {
  const _AndroidTab();

  @override
  ConsumerState<_AndroidTab> createState() => _AndroidTabState();
}

class _AndroidTabState extends ConsumerState<_AndroidTab> {
  @override
  void initState() {
    super.initState();
    // Fetch connected devices as soon as the tab appears so the user can pick
    // a target before tapping "Install APK".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(androidDeployProvider.notifier).refreshDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deploy = ref.watch(androidDeployProvider);
    final notifier = ref.read(androidDeployProvider.notifier);

    return _PlatformDeployTab(
      state: deploy,
      platformLabel: 'Android',
      buildArtifact: 'APK',
      onDeploy: notifier.deploy,
      onCancel: notifier.cancel,
      onOpenUrl: notifier.openInstallUrl,
      extra: _AndroidDevicePicker(
        devices: deploy.devices,
        selectedSerial: deploy.selectedSerial,
        isBusy: deploy.isBusy,
        onSelect: notifier.selectDevice,
        onRefresh: notifier.refreshDevices,
      ),
    );
  }
}

// ─── iOS tab ────────────────────────────────────────────────────────────

class _IOSTab extends ConsumerWidget {
  const _IOSTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deploy = ref.watch(iosDeployProvider);
    final notifier = ref.read(iosDeployProvider.notifier);

    return _PlatformDeployTab(
      state: deploy,
      platformLabel: 'iOS',
      buildArtifact: 'IPA',
      onDeploy: notifier.deploy,
      onCancel: notifier.cancel,
      onOpenUrl: notifier.openInstallUrl,
    );
  }
}

// ─── Shared platform tab content ────────────────────────────────────────

class _PlatformDeployTab extends StatelessWidget {
  const _PlatformDeployTab({
    required this.state,
    required this.platformLabel,
    required this.buildArtifact,
    required this.onDeploy,
    required this.onCancel,
    required this.onOpenUrl,
    this.extra,
  });

  final DeployState state;
  final String platformLabel;
  final String buildArtifact;
  final VoidCallback onDeploy;
  final VoidCallback onCancel;
  final VoidCallback onOpenUrl;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status row
          _StatusRow(phase: state.phase, buildArtifact: buildArtifact),
          if (extra != null) ...[
            const SizedBox(height: 10),
            extra!,
          ],
          const SizedBox(height: 10),
          // Action button
          _ActionButton(
            phase: state.phase,
            platformLabel: platformLabel,
            buildArtifact: buildArtifact,
            onDeploy: onDeploy,
            onCancel: onCancel,
            onOpenUrl: onOpenUrl,
          ),
          // Error message
          if (state.phase == DeployPhase.error && state.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              state.lastError!,
              style: TextStyle(
                color: tc.error,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Android device picker ─────────────────────────────────────────────

class _AndroidDevicePicker extends StatelessWidget {
  const _AndroidDevicePicker({
    required this.devices,
    required this.selectedSerial,
    required this.isBusy,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<AndroidDevice> devices;
  final String? selectedSerial;
  final bool isBusy;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.devices_other, size: 12, color: tc.textLow),
            const SizedBox(width: 6),
            Text(
              'Пристрої',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tc.textLow,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: isBusy ? null : onRefresh,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.refresh,
                  size: 14,
                  color: isBusy ? tc.textLow : tc.textMedium,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (devices.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tc.border),
            ),
            child: Text(
              'Пристрої не знайдено — встанови через завантаження.',
              style: TextStyle(fontSize: 11, color: tc.textLow),
            ),
          )
        else
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in devices)
                _DeviceRow(
                  device: d,
                  selected: d.serial == selectedSerial,
                  onTap: d.isReady && !isBusy ? () => onSelect(d.serial) : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final AndroidDevice device;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;
    final enabled = onTap != null;
    final stateLabel = switch (device.state) {
      'device' => null,
      'unauthorized' => 'unauthorized',
      'offline' => 'offline',
      _ => device.state,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? tc.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? tc.accent : tc.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 12,
                color: selected
                    ? tc.accent
                    : (enabled ? tc.textMedium : tc.textLow),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.model.isEmpty ? device.serial : device.model,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: enabled ? tc.textHigh : tc.textLow,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      device.serial,
                      style: TextStyle(
                        fontSize: 10,
                        color: tc.textLow,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (stateLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tc.error.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: tc.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status row ─────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.phase, required this.buildArtifact});

  final DeployPhase phase;
  final String buildArtifact;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;

    final (String label, Color color, IconData icon) = switch (phase) {
      DeployPhase.idle => ('Не зібрано', tc.textLow, Icons.circle_outlined),
      DeployPhase.checking => ('Перевірка залежностей...', tc.accent, Icons.hourglass_top),
      DeployPhase.building => ('Збірка $buildArtifact...', tc.accent, Icons.build_outlined),
      DeployPhase.ready => ('$buildArtifact готовий', tc.success, Icons.check_circle_outline),
      DeployPhase.error => ('Помилка', tc.error, Icons.error_outline),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Action button ──────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.phase,
    required this.platformLabel,
    required this.buildArtifact,
    required this.onDeploy,
    required this.onCancel,
    required this.onOpenUrl,
  });

  final DeployPhase phase;
  final String platformLabel;
  final String buildArtifact;
  final VoidCallback onDeploy;
  final VoidCallback onCancel;
  final VoidCallback onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;

    final (String label, VoidCallback onTap, Color bg, Color fg) =
        switch (phase) {
      DeployPhase.idle => (
          'Встановити $buildArtifact',
          onDeploy,
          tc.accent,
          tc.background,
        ),
      DeployPhase.checking || DeployPhase.building => (
          'Скасувати',
          onCancel,
          Colors.white.withValues(alpha: 0.08),
          tc.textMedium,
        ),
      DeployPhase.ready => (
          'Відкрити посилання',
          onOpenUrl,
          tc.success,
          tc.background,
        ),
      DeployPhase.error => (
          'Спробувати знову',
          onDeploy,
          tc.error,
          Colors.white,
        ),
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
