/// Modular settings dialog — adaptive for mobile (iPhone 16 Pro) and desktop.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/claude_auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../painters/pixel_glitch_painter.dart';
import '../session/session_form_dialog.dart';
import 'claude_avatar.dart';

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
        // ── Section: Account ──────────────────────────────────────────
        const _AccountSection(),

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

        // ── Section: Glitch effect ─────────────────────────────────
        const SizedBox(height: 32),
        _SectionHeader(title: 'Глітч-ефект'),
        const SizedBox(height: 12),
        Text(
          'Налаштування візуального глітч-ефекту на логотипі.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        _GlitchControls(
          enabled: ref.watch(settingsProvider).glitchEnabled,
          intensity: ref.watch(settingsProvider).glitchIntensity,
          speed: ref.watch(settingsProvider).glitchSpeed,
          bandHeight: ref.watch(settingsProvider).glitchBandHeight,
          shift: ref.watch(settingsProvider).glitchShift,
          chroma: ref.watch(settingsProvider).glitchChroma,
          onEnabledChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchEnabled(v),
          onIntensityChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchIntensity(v),
          onSpeedChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchSpeed(v),
          onBandHeightChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchBandHeight(v),
          onShiftChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchShift(v),
          onChromaChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchChroma(v),
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

// ─── Account section ───────────────────────────────────────────────────────

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _editingNickname = false;
  late TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: ref.read(settingsProvider).nickname,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(claudeAuthProvider);
    final nickname = ref.watch(settingsProvider).nickname;
    final isLoggedIn = authAsync.valueOrNull?.loggedIn ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Обліковий запис'),
        const SizedBox(height: 16),

        // Avatar + info row
        Row(
          children: [
            ClaudeAvatar(isActive: isLoggedIn, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nickname row
                  if (_editingNickname)
                    SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _nicknameController,
                        autofocus: true,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: const Color(0xFF00C0D1)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: Color(0xFF00C0D1)),
                          ),
                        ),
                        onSubmitted: (value) {
                          ref
                              .read(settingsProvider.notifier)
                              .setNickname(value.trim());
                          setState(() => _editingNickname = false);
                        },
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        _nicknameController.text = nickname;
                        setState(() => _editingNickname = true);
                      },
                      child: Row(
                        children: [
                          Text(
                            nickname.isEmpty ? 'Без імені' : nickname,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: nickname.isEmpty ? 0.35 : 0.9,
                              ),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontStyle: nickname.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Auth status line
                  _buildAuthStatus(authAsync),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Login / Logout button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: _buildAuthButton(authAsync),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildAuthStatus(AsyncValue<ClaudeAuthStatus> authAsync) {
    return authAsync.when(
      loading: () => Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Перевірка...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
      error: (_, _) => Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Помилка перевірки',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
      data: (status) {
        if (!status.loggedIn) {
          return Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Не авторизовано',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
            ],
          );
        }
        final plan =
            status.subscriptionType ?? status.authMethod ?? 'Claude';
        final org = status.orgName;
        final label = org != null ? '$plan · $org' : plan;
        return Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuthButton(AsyncValue<ClaudeAuthStatus> authAsync) {
    return authAsync.when(
      loading: () => FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
      error: (_, _) => OutlinedButton.icon(
        onPressed: () => ref.read(claudeAuthProvider.notifier).refresh(),
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Спробувати знову'),
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
      data: (status) {
        if (status.loggedIn) {
          return OutlinedButton(
            onPressed: () =>
                ref.read(claudeAuthProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.5),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Вийти'),
          );
        }
        return FilledButton.icon(
          onPressed: () =>
              ref.read(claudeAuthProvider.notifier).login(),
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text('Увійти через Claude'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00C0D1),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
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

// ─── Glitch effect controls ────────────────────────────────────────────────

class _GlitchControls extends StatefulWidget {
  final bool enabled;
  final double intensity;
  final double speed;
  final int bandHeight;
  final double shift;
  final double chroma;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onBandHeightChanged;
  final ValueChanged<double> onShiftChanged;
  final ValueChanged<double> onChromaChanged;

  const _GlitchControls({
    required this.enabled,
    required this.intensity,
    required this.speed,
    required this.bandHeight,
    required this.shift,
    required this.chroma,
    required this.onEnabledChanged,
    required this.onIntensityChanged,
    required this.onSpeedChanged,
    required this.onBandHeightChanged,
    required this.onShiftChanged,
    required this.onChromaChanged,
  });

  @override
  State<_GlitchControls> createState() => _GlitchControlsState();
}

class _GlitchControlsState extends State<_GlitchControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  final _rng = Random();
  int _seed = 0;
  ui.Image? _logoImage;
  ByteData? _logoImagePixels;

  @override
  void initState() {
    super.initState();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    final data = await rootBundle.load('assets/logo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final pixels = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (mounted) {
      setState(() {
        _logoImage = frame.image;
        _logoImagePixels = pixels;
      });
      _startLoop();
    }
  }

  void _startLoop() {
    if (!mounted || !widget.enabled || _logoImage == null) return;
    _seed = _rng.nextInt(10000);
    final baseDur = 400 + _rng.nextInt(801);
    final dur = (baseDur / widget.speed).round();
    _ctrl
      ..duration = Duration(milliseconds: dur)
      ..forward(from: 0.0).then((_) => _startLoop());
  }

  @override
  void didUpdateWidget(covariant _GlitchControls old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) {
      _startLoop();
    } else if (!widget.enabled && old.enabled) {
      _ctrl
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildPreview() {
    const previewSize = 64.0;
    return Center(
      child: Container(
        width: previewSize + 16,
        height: previewSize + 16,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.enabled
                ? const Color(0xFF00C0D1).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Center(
          child: _logoImage == null
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                )
              : AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final t = _ctrl.value;
                    final glitching =
                        widget.enabled && _ctrl.isAnimating && t > 0;

                    if (!glitching) {
                      return Image.asset(
                        'assets/logo.png',
                        width: previewSize,
                        height: previewSize,
                        filterQuality: FilterQuality.medium,
                      );
                    }

                    final frame = (t * 8).floor();
                    return SizedBox(
                      width: previewSize,
                      height: previewSize,
                      child: CustomPaint(
                        size: const Size(previewSize, previewSize),
                        painter: PixelGlitchPainter(
                          image: _logoImage!,
                          seed: _seed + frame,
                          pixelPercent: widget.intensity,
                          displaySize: previewSize,
                          imagePixels: _logoImagePixels,
                          bandHeightMax: widget.bandHeight,
                          shiftStrength: widget.shift,
                          chromaStrength: widget.chroma,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  SliderThemeData _sliderTheme(bool enabled) => SliderThemeData(
        activeTrackColor: enabled
            ? const Color(0xFF00C0D1)
            : Colors.white.withValues(alpha: 0.12),
        inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
        thumbColor: enabled
            ? const Color(0xFF00C0D1)
            : Colors.white.withValues(alpha: 0.2),
        overlayColor: const Color(0xFF00C0D1).withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      );

  Widget _vSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required bool enabled,
    required ValueChanged<double>? onChanged,
  }) {
    final iconColor = Colors.white.withValues(alpha: enabled ? 0.5 : 0.15);
    final labelColor = Colors.white.withValues(alpha: enabled ? 0.8 : 0.25);

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: _sliderTheme(enabled),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live preview + enable toggle
        Row(
          children: [
            Expanded(child: _buildPreview()),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Switch.adaptive(
                    value: enabled,
                    onChanged: widget.onEnabledChanged,
                    activeTrackColor: const Color(0xFF00C0D1),
                    activeThumbColor: const Color(0xFF00C0D1),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: enabled ? 0.6 : 0.2),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Vertical sliders row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intensity
            _vSlider(
              icon: Icons.grain,
              label: '${(widget.intensity * 100).round()}%',
              value: widget.intensity,
              min: 0.01,
              max: 0.30,
              divisions: 29,
              enabled: enabled,
              onChanged: enabled ? widget.onIntensityChanged : null,
            ),
            // Speed
            _vSlider(
              icon: Icons.speed,
              label: '${widget.speed.toStringAsFixed(1)}x',
              value: widget.speed,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              enabled: enabled,
              onChanged: enabled ? widget.onSpeedChanged : null,
            ),
            // Band height
            _vSlider(
              icon: Icons.line_weight,
              label: '${widget.bandHeight}px',
              value: widget.bandHeight.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              enabled: enabled,
              onChanged: enabled
                  ? (v) => widget.onBandHeightChanged(v.round())
                  : null,
            ),
            // Shift
            _vSlider(
              icon: Icons.swap_horiz,
              label: '${(widget.shift * 100).round()}%',
              value: widget.shift,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              enabled: enabled,
              onChanged: enabled ? widget.onShiftChanged : null,
            ),
            // Chroma
            _vSlider(
              icon: Icons.lens_blur,
              label: widget.chroma == 0
                  ? 'off'
                  : '${(widget.chroma * 100).round()}%',
              value: widget.chroma,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              enabled: enabled,
              onChanged: enabled ? widget.onChromaChanged : null,
            ),
          ],
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
