/// Modular settings dialog — adaptive for mobile (iPhone 16 Pro) and desktop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../session/session_form_dialog.dart';

/// Opens the settings dialog as a full-screen modal on mobile,
/// or a centered dialog on desktop.
Future<void> showSettingsDialog(BuildContext context) {
  final isNarrow = MediaQuery.sizeOf(context).width < 600;

  if (isNarrow) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _SettingsPage(),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (_) => const Center(child: _SettingsDialog()),
  );
}

// ─── Full-screen page for mobile ────────────────────────────────────────────

class _SettingsPage extends ConsumerWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text(
          'Налаштування',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: _SettingsContent(),
        ),
      ),
    );
  }
}

// ─── Desktop dialog ─────────────────────────────────────────────────────────

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Налаштування',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(
              color: Color(0xFF2A2A30),
              height: 1,
            ),
            // Content
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: _SettingsContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared settings content ────────────────────────────────────────────────

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section: Sessions ──────────────────────────────────────────
        _SectionHeader(title: 'Сесії'),
        const SizedBox(height: 12),
        Text(
          'Серверні профілі для підключення. '
          'Оберіть активну сесію в заголовку вікна.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Profile list
        for (final profile in session.profiles) ...[
          _SessionProfileTile(
            profile: profile,
            isActive: profile.id == session.activeProfileId,
            isConnected: profile.id == session.activeProfileId && isConnected,
            onEdit: () => _editProfile(context, ref, profile),
            onDelete: session.profiles.length > 1
                ? () => _deleteProfile(context, ref, profile)
                : null,
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => _addProfile(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Додати сесію'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00C0D1),
              side: BorderSide(
                color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        // ── Section: Ergonomics ────────────────────────────────────────
        const SizedBox(height: 32),
        _SectionHeader(title: 'Ергономіка робочого місця'),
        const SizedBox(height: 12),
        Text(
          'Висота робочого столу',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Мікрорегулювання висоти для оптимальної ергономічної '
          'позиції під час кодування.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        _DeskHeightControl(
          value: ref.watch(settingsProvider).deskHeight,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setDeskHeight(v),
        ),

        // ── Danger zone ─────────────────────────────────────────────
        const SizedBox(height: 32),
        _SectionHeader(title: 'Небезпечна зона'),
        const SizedBox(height: 12),
        Text(
          'Видаляє всі кешовані SDK-сесії з диска. '
          'Поточний контекст розмови буде втрачено.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: () => _confirmClearSessions(context, ref),
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: const Text('Очистити всі SDK-сесії'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00C0D1),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addProfile(BuildContext context, WidgetRef ref) async {
    final profile = await showSessionFormDialog(context);
    if (profile == null) return;
    await ref.read(sessionProvider.notifier).addProfile(profile);
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    SessionProfile profile,
  ) async {
    final updated = await showSessionFormDialog(context, existing: profile);
    if (updated == null) return;
    await ref.read(sessionProvider.notifier).updateProfile(updated);
  }

  void _deleteProfile(
    BuildContext context,
    WidgetRef ref,
    SessionProfile profile,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F27),
        title: Text(
          'Видалити "${profile.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Скасувати',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sessionProvider.notifier).deleteProfile(profile.id);
            },
            child: const Text(
              'Видалити',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearSessions(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F27),
        title: const Text(
          'Очистити всі SDK-сесії?',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          'Усі кешовані сесії буде видалено з диска. '
          'Поточний контекст розмови буде втрачено.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Скасувати',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(wsServiceProvider).clearSessions();
              ref.read(chatProvider.notifier).newChat();
            },
            child: const Text(
              'Очистити',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Session profile tile ──────────────────────────────────────────────────

class _SessionProfileTile extends StatelessWidget {
  final SessionProfile profile;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _SessionProfileTile({
    required this.profile,
    required this.isActive,
    required this.isConnected,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isActive
        ? (isConnected ? const Color(0xFF00C0D1) : Colors.red)
        : Colors.white.withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00C0D1).withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00C0D1).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: isActive ? 0.9 : 0.6),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.host}:${profile.port}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

// ─── Desk height ergonomics control ────────────────────────────────────────

class _DeskHeightControl extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _DeskHeightControl({required this.value, required this.onChanged});

  static String _statusText(double h) {
    if (h < 65) {
      return 'Компактна конфігурація · Зосереджений режим роботи';
    }
    if (h < 72) {
      return 'Знижена позиція · Оптимально для тривалих сесій';
    }
    if (h < 78) return 'Стандартна позиція · Рекомендовано ISO 11064-4';
    if (h < 90) {
      return 'Підвищена позиція · Покращена вентиляція робочої зони';
    }
    if (h < 110) return 'Високий стіл · Стимулює творче мислення';
    return 'Максимальна висота · Панорамний огляд коду';
  }

  /// Deterministic "ergonomic score" — always lands between 92 and 98.
  static int _ergoScore(double h) => 92 + ((h * 7.3) % 7).round();

  @override
  Widget build(BuildContext context) {
    final score = _ergoScore(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slider row
        Row(
          children: [
            Text(
              '60',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 10,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF00C0D1),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  thumbColor: const Color(0xFF00C0D1),
                  overlayColor: const Color(0xFF00C0D1).withValues(alpha: 0.12),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: value,
                  min: 60,
                  max: 130,
                  divisions: 70,
                  onChanged: onChanged,
                ),
              ),
            ),
            Text(
              '130',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 10,
              ),
            ),
          ],
        ),
        // Current value
        Center(
          child: Text(
            '${value.round()} см',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Status indicator
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusText(value),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Ergonomic rating bar
        Row(
          children: [
            Text(
              'Ергономічний рейтинг',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Text(
              '$score%',
              style: TextStyle(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF4ADE80)),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 10),
        // Certification
        Text(
          'Сертифіковано Комітетом з Віртуальної Ергономіки PixelCode™',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.15),
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ─── Reusable section header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}
