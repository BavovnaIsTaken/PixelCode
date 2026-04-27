/// Modular settings dialog — adaptive for mobile (iPhone 16 Pro) and desktop.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/claude_auth_provider.dart';
import '../../providers/deepseek_auth_provider.dart';
import '../../providers/gemini_auth_provider.dart';
import '../../providers/energy_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/ios_deploy_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tailscale_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import '../../services/logo_path_program.dart' show kDefaultLogoPathScript;
import '../painters/pixel_glitch_painter.dart';
import '../session/session_form_dialog.dart';
import 'claude_avatar.dart';
import 'diagnostics_section.dart';
import 'logo_path_editor.dart';
import 'send_button_section.dart';
import 'theme_section.dart';

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
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: const Text(
          'Налаштування',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const SafeArea(child: _SettingsContent()),
    );
  }
}

// ─── Desktop dialog ─────────────────────────────────────────────────────────

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: c.surface,
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
            const Flexible(child: _SettingsContent()),
          ],
        ),
      ),
    );
  }
}

// ─── Category taxonomy ─────────────────────────────────────────────────────

enum _SettingsCategory {
  account(Icons.person_outline, 'Обліковий запис'),
  energy(Icons.bolt_outlined, 'Енергія'),
  themes(Icons.palette_outlined, 'Теми'),
  sendButton(Icons.send_outlined, 'Кнопка «Надіслати»'),
  network(Icons.hub_outlined, 'Мережа'),
  ergonomics(Icons.chair_outlined, 'Ергономіка'),
  logo(Icons.memory, 'Лого'),
  cheats(Icons.auto_awesome_outlined, 'Чіти'),
  danger(Icons.warning_amber_rounded, 'Небезпечна зона');

  const _SettingsCategory(this.icon, this.label);

  final IconData icon;
  final String label;
}

// ─── Shared settings content ────────────────────────────────────────────────

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  _SettingsCategory _cat = _SettingsCategory.account;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
            child: _buildSection(_cat),
          ),
        ),
        Container(width: 1, color: const Color(0xFF2A2A30)),
        _CategoryRail(
          selected: _cat,
          onSelect: (c) => setState(() => _cat = c),
        ),
      ],
    );
  }

  Widget _buildSection(_SettingsCategory cat) {
    switch (cat) {
      case _SettingsCategory.account:
        return const _AccountSection();
      case _SettingsCategory.energy:
        return _buildEnergy();
      case _SettingsCategory.themes:
        return _buildThemes();
      case _SettingsCategory.sendButton:
        return _buildSendButton();
      case _SettingsCategory.network:
        return _buildNetwork();
      case _SettingsCategory.ergonomics:
        return _buildErgonomics();
      case _SettingsCategory.logo:
        return _buildLogo();
      case _SettingsCategory.cheats:
        return _buildCheats();
      case _SettingsCategory.danger:
        return _buildDanger();
    }
  }

  Widget _buildEnergy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Енергія'),
        const SizedBox(height: 12),
        _desc('Денний ліміт токенів Claude API. '
            'При вичерпанні модель автоматично понижується до Haiku. '
            'Лічильники скидаються опівночі за локальним часом.'),
        const SizedBox(height: 18),
        const _EnergyDetails(),
      ],
    );
  }

  Widget _buildThemes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Теми'),
        const SizedBox(height: 12),
        _desc('Обери стиль свого робочого простору. '
            'Преміум теми можна кастомізувати.'),
        const SizedBox(height: 14),
        const ThemeSection(),
      ],
    );
  }

  Widget _buildSendButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Кнопка «Надіслати»'),
        const SizedBox(height: 12),
        _desc('Ексклюзивні ручні дизайни найчастіше натискуваної '
            'кнопки. Преміум-варіанти — найдорожча косметика в магазині.'),
        const SizedBox(height: 14),
        const SendButtonSection(),
      ],
    );
  }

  Widget _buildNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSessions(),
        const SizedBox(height: 24),
        _buildTailscale(),
        const SizedBox(height: 24),
        _buildIosDeploy(),
        const SizedBox(height: 24),
        const DiagnosticsSection(),
      ],
    );
  }

  Widget _buildSessions() {
    final session = ref.watch(sessionProvider);
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Сесії'),
        const SizedBox(height: 12),
        _desc('Серверні профілі для підключення. '
            'Оберіть активну сесію в заголовку вікна.'),
        const SizedBox(height: 12),
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
      ],
    );
  }

  Widget _buildErgonomics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _desc('Мікрорегулювання висоти для оптимальної ергономічної '
            'позиції під час кодування.'),
        const SizedBox(height: 14),
        _DeskHeightControl(
          value: ref.watch(settingsProvider).deskHeight,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setDeskHeight(v),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    final settings = ref.watch(settingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Лого'),
        const SizedBox(height: 16),

        // ── Subsection: Glitch effect ─────────────────────
        _SectionHeader(title: 'Глітч-ефект'),
        const SizedBox(height: 8),
        _desc('Налаштування візуального глітч-ефекту на логотипі.'),
        const SizedBox(height: 14),
        _GlitchControls(
          enabled: settings.glitchEnabled,
          intensity: settings.glitchIntensity,
          speed: settings.glitchSpeed,
          bandHeight: settings.glitchBandHeight,
          bandHeightMin: settings.glitchBandHeightMin,
          shift: settings.glitchShift,
          chroma: settings.glitchChroma,
          onEnabledChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchEnabled(v),
          onIntensityChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchIntensity(v),
          onSpeedChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchSpeed(v),
          onBandHeightChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchBandHeight(v),
          onBandHeightMinChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchBandHeightMin(v),
          onShiftChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchShift(v),
          onChromaChanged: (v) =>
              ref.read(settingsProvider.notifier).setGlitchChroma(v),
        ),

        const SizedBox(height: 28),

        // ── Subsection: Movement algorithm ────────────────
        _SectionHeader(title: 'Алгоритм руху'),
        const SizedBox(height: 8),
        _desc('Власна функція позиції логотипа під час анімації вимкнення. '
            'Inputs: start, end, screenWidth, screenHeight, t (0→1). '
            'Output: return Point(x, y).'),
        const SizedBox(height: 14),
        LogoPathEditor(
          script: settings.logoPathScript ?? kDefaultLogoPathScript,
          onSaved: (script) {
            final isDefault = script.trim() == kDefaultLogoPathScript.trim();
            ref
                .read(settingsProvider.notifier)
                .setLogoPathScript(isDefault ? null : script);
          },
        ),

        const SizedBox(height: 20),

        // ── Subsection: Animation duration ────────────────
        _SectionHeader(title: 'Час анімації'),
        const SizedBox(height: 8),
        _desc('Скільки триває політ іконки під час вимкнення. '
            'Native window collapse (400 мс) підлаштовується автоматично.'),
        const SizedBox(height: 12),
        _LogoAnimationDurationControl(
          value: settings.logoAnimationDurationMs,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .setLogoAnimationDurationMs(v),
        ),
      ],
    );
  }

  Widget _buildTailscale() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Tailscale Funnel'),
        const SizedBox(height: 12),
        _desc('Дозволяє підключатися до сервера та встановлювати '
            'білди з iPhone з будь-якої мережі.'),
        const SizedBox(height: 14),
        const _TailscaleSection(),
      ],
    );
  }

  Widget _buildIosDeploy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Конфігурація запуску iOS'),
        const SizedBox(height: 12),
        _desc('Побудова та OTA-встановлення iOS додатку через Wi-Fi. '
            'Натисніть іконку телефону у панелі інструментів для '
            'швидкого запуску.'),
        const SizedBox(height: 14),
        const _DeployStatusSection(),
      ],
    );
  }

  Widget _buildCheats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Чіти'),
        const SizedBox(height: 12),
        _desc('Швидкі дії для розробки та тестування.'),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildDanger() {
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Небезпечна зона',
          color: Colors.red.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 12),
        _desc('Операції, які можуть привести до втрати даних. '
            'Виконуйте з обережністю.'),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Очистити кеш SDK-сесій',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Видаляє всі кешовані сесії з диска. '
              'Поточний контекст розмови буде втрачено.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FilledButton.icon(
                    onPressed: () => _confirmClearSessions(context, ref),
                    icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                    label: const Text('Очистити'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00C0D1),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: const CustomPaint(
                          painter: _DirtOverlayPainter(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (isConnected)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Зупинити всіх агентів',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Екстрено зупиняє виконання всіх поточних агентів '
                'та їх підзадач.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: const _StopAllButton(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _desc(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 12,
        ),
      );

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

// ─── Category rail ─────────────────────────────────────────────────────────

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.selected, required this.onSelect});

  final _SettingsCategory selected;
  final ValueChanged<_SettingsCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final cat in _SettingsCategory.values) ...[
              _RailButton(
                icon: cat.icon,
                tooltip: cat.label,
                active: cat == selected,
                danger: cat == _SettingsCategory.danger,
                onTap: () => onSelect(cat),
                customIcon: cat == _SettingsCategory.logo
                    ? Image.asset(
                        'assets/logo_pixel.png',
                        width: 16,
                        height: 16,
                        filterQuality: FilterQuality.none,
                      )
                    : null,
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.danger = false,
    this.customIcon,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool danger;
  final VoidCallback onTap;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) {
    final accent = danger
        ? Colors.red.withValues(alpha: 0.85)
        : const Color(0xFF00C0D1);
    final iconColor = active
        ? accent
        : Colors.white.withValues(alpha: danger ? 0.55 : 0.45);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? accent : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: customIcon != null
              ? ColorFiltered(
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  child: customIcon!,
                )
              : Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

// ─── Framed avatar ─────────────────────────────────────────────────────────

class _FramedAvatar extends StatelessWidget {
  final String? frameId;
  final bool isLoggedIn;

  const _FramedAvatar({this.frameId, required this.isLoggedIn});

  static const _frameColors = <String, Color>{
    'frame_neon': Color(0xFF00C0D1),
    'frame_gold': Color(0xFFFFD700),
    'frame_fire': Color(0xFFFF6B35),
    'frame_glitch': Color(0xFF9B59B6),
    'frame_pixel': Color(0xFF22C55E),
    'frame_matrix': Color(0xFF00FF41),
  };

  @override
  Widget build(BuildContext context) {
    final frameColor = frameId != null
        ? (_frameColors[frameId!] ?? const Color(0xFF00C0D1))
        : null;

    if (frameColor == null) {
      return ClaudeAvatar(isActive: isLoggedIn, size: 48);
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: frameColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: frameColor.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClaudeAvatar(isActive: isLoggedIn, size: 48),
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
  bool _randomHovered = false;
  late TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    final game = ref.read(gameEconomyProvider);
    _nicknameController = TextEditingController(text: game.nickname);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _submitNickname() {
    final newNick = _nicknameController.text.trim();
    if (newNick.isEmpty) {
      setState(() => _editingNickname = false);
      return;
    }
    final success = ref.read(gameEconomyProvider.notifier).changeNickname(newNick);
    if (!success) {
      // Not enough grymni
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Недостатньо гримнів для зміни нікнейму!',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    setState(() => _editingNickname = false);
  }

  @override
  Widget build(BuildContext context) {
    final claudeAuthAsync = ref.watch(claudeAuthProvider);
    final geminiAuthAsync = ref.watch(geminiAuthProvider);
    final deepseekAuthAsync = ref.watch(deepseekAuthProvider);
    final game = ref.watch(gameEconomyProvider);
    final claudeLoggedIn = claudeAuthAsync.valueOrNull?.loggedIn ?? false;

    final frameId = game.equippedFor(CosmeticType.avatarFrame);
    final titleId = game.equippedFor(CosmeticType.titleBadge);
    final title = titleId != null ? cosmeticById(titleId)?.preview : null;

    final freeLeft = (freeNicknameChanges - game.nicknameChangesUsed)
        .clamp(0, freeNicknameChanges);
    final isFree = game.isNicknameChangeFree;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Обліковий запис'),
        const SizedBox(height: 16),

        // Avatar + info row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar with frame
            _FramedAvatar(frameId: frameId, isLoggedIn: claudeLoggedIn),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title badge
                  if (title != null) ...[
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  // Nickname row
                  if (_editingNickname)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 30,
                            child: TextField(
                              controller: _nicknameController,
                              autofocus: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                hintText: 'Latin nickname',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  fontSize: 12,
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
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00C0D1),
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _submitNickname(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _submitNickname,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C0D1).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF00C0D1).withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Color(0xFF00C0D1),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        _nicknameController.text = game.nickname;
                        setState(() => _editingNickname = true);
                      },
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              game.displayNickname.isEmpty
                                  ? 'Без нікнейму'
                                  : game.displayNickname,
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha: game.nickname.isEmpty ? 0.35 : 0.9,
                                ),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontStyle: game.nickname.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
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

                  const SizedBox(height: 5),

                  // Nickname change counter
                  Row(
                    children: [
                      Icon(
                        isFree ? Icons.lock_open_outlined : Icons.lock_outlined,
                        size: 10,
                        color: isFree
                            ? const Color(0xFF22C55E).withValues(alpha: 0.7)
                            : const Color(0xFFFFD700).withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isFree
                            ? 'Безкоштовно ($freeLeft/$freeNicknameChanges залишилось)'
                            : 'Далі',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                      ),
                      if (!isFree) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            ref.read(shopDeepLinkProvider.notifier).state =
                                shopTabDonation;
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$nicknameChangeCost',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Text(
                                  '₲',
                                  style: TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      // Randomize button
                      MouseRegion(
                        onEnter: (_) => setState(() => _randomHovered = true),
                        onExit: (_) => setState(() => _randomHovered = false),
                        child: GestureDetector(
                          onTap: () {
                            final success = ref
                                .read(gameEconomyProvider.notifier)
                                .randomizeNickname();
                            if (!success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Недостатньо гримнів!',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.red.shade800,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 75),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                  alpha: _randomHovered ? 0.1 : 0.04),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(
                                    alpha: _randomHovered ? 0.2 : 0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shuffle_rounded,
                                  size: 9,
                                  color: Colors.white.withValues(
                                      alpha: _randomHovered ? 0.7 : 0.35),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Random',
                                  style: TextStyle(
                                    color: Colors.white.withValues(
                                        alpha: _randomHovered ? 0.7 : 0.35),
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),
                  // Launch counter
                  Row(
                    children: [
                      Icon(
                        Icons.rocket_launch_outlined,
                        size: 10,
                        color: const Color(0xFF00C0D1).withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Запусків: ${ref.watch(settingsProvider).launchCount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Auth status line
                  _buildAuthStatus(claudeAuthAsync),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Login / Logout / API-key buttons
        SizedBox(
          width: double.infinity,
          child: _buildAuthSection(ref, claudeAuthAsync, geminiAuthAsync, deepseekAuthAsync),
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

  Widget _buildAuthSection(
    WidgetRef ref,
    AsyncValue<ClaudeAuthStatus> claudeAuthAsync,
    AsyncValue<GeminiAuthStatus> geminiAuthAsync,
    AsyncValue<DeepSeekAuthStatus> deepseekAuthAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProviderRow(
          button: _buildAuthProviderButton(
            ref,
            provider: 'Claude',
            icon: Icons.login_rounded,
            claudeAuth: claudeAuthAsync,
          ),
          connected: claudeAuthAsync.valueOrNull?.loggedIn ?? false,
          isLoading: claudeAuthAsync.isLoading,
        ),
        const SizedBox(height: 10),
        _buildProviderRow(
          button: _buildAuthProviderButton(
            ref,
            provider: 'Google (Gemini)',
            icon: Icons.login_rounded,
            geminiAuth: geminiAuthAsync,
          ),
          connected: geminiAuthAsync.valueOrNull?.loggedIn ?? false,
          isLoading: geminiAuthAsync.isLoading,
        ),
        const SizedBox(height: 10),
        _buildProviderRow(
          button: _buildAuthProviderButton(
            ref,
            provider: 'DeepSeek',
            icon: Icons.key_outlined,
            deepseekAuth: deepseekAuthAsync,
          ),
          connected: deepseekAuthAsync.valueOrNull?.linked ?? false,
          isLoading: deepseekAuthAsync.isLoading,
        ),
      ],
    );
  }

  Widget _buildProviderRow({
    required Widget button,
    required bool connected,
    bool isLoading = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        button,
        const Spacer(),
        _buildPixelStatusBadge(connected: connected, isLoading: isLoading),
      ],
    );
  }

  Widget _buildPixelStatusBadge({required bool connected, bool isLoading = false}) {
    final Color color;
    final String label;
    if (isLoading) {
      color = Colors.white.withValues(alpha: 0.2);
      label = '· · ·';
    } else if (connected) {
      color = const Color(0xFF22C55E);
      label = 'CONNECTED';
    } else {
      color = Colors.white.withValues(alpha: 0.18);
      label = 'OFFLINE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: connected ? 0.65 : 0.3)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontFamily: 'monospace',
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildAuthProviderButton(
    WidgetRef ref, {
    required String provider,
    required IconData icon,
    AsyncValue<ClaudeAuthStatus>? claudeAuth,
    AsyncValue<GeminiAuthStatus>? geminiAuth,
    AsyncValue<DeepSeekAuthStatus>? deepseekAuth,
  }) {
    if (claudeAuth != null) {
      return claudeAuth.when(
        loading: () => _buildLoadingButton(),
        error: (_, _) => _buildErrorButton(
          onPressed: () => ref.read(claudeAuthProvider.notifier).refresh(),
        ),
        data: (status) {
          if (status.loggedIn) {
            return _buildLoggedInButton(
              label: 'Вийти (Claude)',
              onPressed: () => ref.read(claudeAuthProvider.notifier).logout(),
            );
          }
          return _buildLoginButton(
            label: 'Увійти через claude.ai',
            icon: icon,
            onPressed: () => ref.read(claudeAuthProvider.notifier).login(),
          );
        },
      );
    } else if (geminiAuth != null) {
      return geminiAuth.when(
        loading: () => _buildLoadingButton(),
        error: (_, _) => _buildErrorButton(
          onPressed: () => ref.read(geminiAuthProvider.notifier).refresh(),
        ),
        data: (status) {
          if (status.loggedIn) {
            return _buildLoggedInButton(
              label: 'Вийти (Google)',
              onPressed: () => ref.read(geminiAuthProvider.notifier).logout(),
            );
          }
          return _buildLoginButton(
            label: 'Увійти через Google (gemini-cli)',
            icon: icon,
            onPressed: () => ref.read(geminiAuthProvider.notifier).login(),
          );
        },
      );
    } else if (deepseekAuth != null) {
      return deepseekAuth.when(
        loading: () => _buildLoadingButton(),
        error: (_, _) => _buildErrorButton(
          onPressed: () => ref.read(deepseekAuthProvider.notifier).refresh(),
        ),
        data: (status) {
          if (status.linked) {
            return _buildLoggedInButton(
              label: 'Очистити ключ DeepSeek (${status.maskedKey})',
              onPressed: () => ref.read(deepseekAuthProvider.notifier).clearKey(),
            );
          }
          return _buildLoginButton(
            label: 'Додати API ключ DeepSeek',
            icon: icon,
            onPressed: () => _showDeepSeekKeyDialog(ref),
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  void _showDeepSeekKeyDialog(WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'DeepSeek API ключ',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ключ зберігається локально і надсилається тільки на api.deepseek.com.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'sk-...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00C0D1)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Скасувати',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00C0D1),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                ref.read(deepseekAuthProvider.notifier).saveKey(key);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Зберегти'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _buildLoadingButton() => FilledButton(
    onPressed: null,
    style: FilledButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white.withValues(alpha: 0.3),
      ),
    ),
  );

  Widget _buildErrorButton({required VoidCallback onPressed}) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Спробувати знову'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00C0D1),
          side: BorderSide(
            color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  Widget _buildLoginButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) =>
      FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00C0D1),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  Widget _buildLoggedInButton({
    required String label,
    required VoidCallback onPressed,
  }) =>
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.5),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      );
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
                  profile.wsUrl,
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
          'Сертифіковано Комітетом з Віртуальної Ергономіки ПіксельКод™',
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
  final int bandHeightMin;
  final double shift;
  final double chroma;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onBandHeightChanged;
  final ValueChanged<int> onBandHeightMinChanged;
  final ValueChanged<double> onShiftChanged;
  final ValueChanged<double> onChromaChanged;

  const _GlitchControls({
    required this.enabled,
    required this.intensity,
    required this.speed,
    required this.bandHeight,
    required this.bandHeightMin,
    required this.shift,
    required this.chroma,
    required this.onEnabledChanged,
    required this.onIntensityChanged,
    required this.onSpeedChanged,
    required this.onBandHeightChanged,
    required this.onBandHeightMinChanged,
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
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedBuilder(
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
                            bandHeightMin: widget.bandHeightMin,
                            shiftStrength: widget.shift,
                            chromaStrength: widget.chroma,
                          ),
                        ),
                      );
                    },
                  ),
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
            // Band height — min
            _vSlider(
              icon: Icons.horizontal_rule,
              label: 'min ${widget.bandHeightMin}px',
              value: widget.bandHeightMin.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              enabled: enabled,
              onChanged: enabled
                  ? (v) => widget.onBandHeightMinChanged(v.round())
                  : null,
            ),
            // Band height — max
            _vSlider(
              icon: Icons.line_weight,
              label: 'max ${widget.bandHeight}px',
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

// ─── Logo animation duration slider ────────────────────────────────────────

class _LogoAnimationDurationControl extends StatelessWidget {
  /// null → use [kDefaultLogoAnimationDurationMs].
  final int? value;
  final ValueChanged<int?> onChanged;

  const _LogoAnimationDurationControl({
    required this.value,
    required this.onChanged,
  });

  static const _minMs = 400;
  static const _maxMs = 3000;
  static const _stepMs = 50;

  @override
  Widget build(BuildContext context) {
    final effective = value ?? kDefaultLogoAnimationDurationMs;
    final isCustom = value != null;
    const accent = Color(0xFF00C0D1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  thumbColor: accent,
                  overlayColor: accent.withValues(alpha: 0.12),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: effective.toDouble().clamp(
                        _minMs.toDouble(),
                        _maxMs.toDouble(),
                      ),
                  min: _minMs.toDouble(),
                  max: _maxMs.toDouble(),
                  divisions: (_maxMs - _minMs) ~/ _stepMs,
                  onChanged: (v) {
                    final rounded = (v / _stepMs).round() * _stepMs;
                    if (rounded == kDefaultLogoAnimationDurationMs) {
                      onChanged(null);
                    } else {
                      onChanged(rounded);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                '$effective мс',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Дефолт: $kDefaultLogoAnimationDurationMs мс',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
            const Spacer(),
            if (isCustom)
              TextButton(
                onPressed: () => onChanged(null),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Скинути',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Tailscale Funnel setup ────────────────────────────────────────────────

class _TailscaleSection extends ConsumerStatefulWidget {
  const _TailscaleSection();

  @override
  ConsumerState<_TailscaleSection> createState() => _TailscaleSectionState();
}

class _TailscaleSectionState extends ConsumerState<_TailscaleSection> {
  bool _logsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tunnelUrl = ref.watch(tunnelUrlProvider);
    final setup = ref.watch(tailscaleSetupProvider);
    final isActive = tunnelUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isActive
                    ? const Color(0xFF4ADE80)
                    : setup.isConnecting
                        ? const Color(0xFF00C0D1)
                        : Colors.white.withValues(alpha: 0.15))
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isActive
                      ? const Color(0xFF4ADE80)
                      : setup.isConnecting
                          ? const Color(0xFF00C0D1)
                          : Colors.white.withValues(alpha: 0.15))
                  .withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              if (setup.isConnecting)
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: const Color(0xFF00C0D1),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? const Color(0xFF4ADE80)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: isActive
                    ? Text(
                        tunnelUrl.replaceFirst('wss://', ''),
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        setup.isConnecting
                            ? 'Підключення…'
                            : 'Не активний',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
              ),
              if (isActive)
                Icon(
                  Icons.cloud_done_outlined,
                  size: 16,
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.7),
                ),
            ],
          ),
        ),

        // Connect button (when not active and not connecting)
        if (!isActive && !setup.isConnecting) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: () =>
                  ref.read(tailscaleSetupProvider.notifier).connect(),
              icon: const Icon(Icons.vpn_key_outlined, size: 15),
              label: const Text('Підключити Tailscale'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C0D1).withValues(alpha: 0.15),
                foregroundColor: const Color(0xFF00C0D1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],

        // Expandable logs
        if (setup.logs.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
            child: Row(
              children: [
                Icon(
                  _logsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 4),
                Text(
                  'Лог (${setup.logs.length})',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_logsExpanded) ...[
            const SizedBox(height: 6),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in setup.logs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            color: line.startsWith('❌')
                                ? const Color(0xFFFF6B6B)
                                : line.startsWith('✓') || line.startsWith('🚀')
                                    ? const Color(0xFF4ADE80)
                                    : Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ─── iOS deploy status & logs ──────────────────────────────────────────────

class _DeployStatusSection extends ConsumerStatefulWidget {
  const _DeployStatusSection();

  @override
  ConsumerState<_DeployStatusSection> createState() =>
      _DeployStatusSectionState();
}

class _DeployStatusSectionState extends ConsumerState<_DeployStatusSection> {
  bool _logsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final deploy = ref.watch(iosDeployProvider);

    // Status indicator
    final (Color statusColor, String statusText) = switch (deploy.phase) {
      DeployPhase.idle => (
          Colors.white.withValues(alpha: 0.2),
          'Очікує запуску'
        ),
      DeployPhase.checking => (
          const Color(0xFF00C0D1),
          'Перевірка залежностей...'
        ),
      DeployPhase.building => (const Color(0xFF00C0D1), 'Побудова IPA...'),
      DeployPhase.ready => (const Color(0xFF4ADE80), 'Готово до встановлення'),
      DeployPhase.error => (
          const Color(0xFFEF4444),
          deploy.lastError ?? 'Помилка'
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              if (deploy.isBusy)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: statusColor,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
              if (deploy.isBusy)
                InkWell(
                  onTap: () =>
                      ref.read(iosDeployProvider.notifier).cancel(),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'Скасувати',
                      style: TextStyle(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (deploy.phase == DeployPhase.ready)
                InkWell(
                  onTap: () =>
                      ref.read(iosDeployProvider.notifier).openInstallUrl(),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      'Відкрити',
                      style: TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Expandable logs
        if (deploy.logs.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
            child: Row(
              children: [
                Icon(
                  _logsExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 4),
                Text(
                  'Лог (${deploy.logs.length})',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_logsExpanded) ...[
            const SizedBox(height: 6),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final log in deploy.logs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            color: log.contains('[ПОМИЛКА]')
                                ? const Color(0xFFFF6B6B)
                                : Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ─── Reusable section header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: color ?? Colors.white.withValues(alpha: 0.35),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─── Stop all agents button ────────────────────────────────────────────────

class _StopAllButton extends ConsumerStatefulWidget {
  const _StopAllButton();

  @override
  ConsumerState<_StopAllButton> createState() => _StopAllButtonState();
}

class _StopAllButtonState extends ConsumerState<_StopAllButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);
    final hasActiveAgents = agents.values.any((a) => a.isActive);
    final enabled = hasActiveAgents;

    final Color baseColor;
    final Color borderColor;
    final Color fgColor;

    if (!enabled) {
      baseColor = Colors.white.withValues(alpha: 0.04);
      borderColor = Colors.white.withValues(alpha: 0.08);
      fgColor = Colors.white.withValues(alpha: 0.2);
    } else if (_pressed) {
      baseColor = const Color(0xFF5A1A1E);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.7);
      fgColor = const Color(0xFFFF5252);
    } else if (_hovered) {
      baseColor = const Color(0xFF4A1619);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.55);
      fgColor = const Color(0xFFFF4D4D);
    } else {
      baseColor = const Color(0xFF3D1518);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.4);
      fgColor = const Color(0xFFFF3B3B);
    }

    return Tooltip(
      message: enabled ? 'Зупинити всіх агентів' : 'Немає активних агентів',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  ref.read(wsServiceProvider).interrupt();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stop_circle_outlined, size: 16, color: fgColor),
                const SizedBox(width: 6),
                Text(
                  'Зупинити всіх агентів',
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

// ─── Dirt overlay painter (Terraria-style) ────────────────────────────────

/// Pixel-art dirt overlay drawn on top of the "Очистити" button.
///
/// Shape logic:
///  • Dirt is concentrated on the LEFT and RIGHT sides.
///  • An invisible oval around the button content repels dirt smoothly —
///    inside the oval the probability drops to zero, outside it ramps up.
///  • Even at the sides the coverage is soft (~55 % max) so the cyan
///    button colour still breathes through.
class _DirtOverlayPainter extends CustomPainter {
  const _DirtOverlayPainter();

  static const double _bs = 3.0; // block size in logical pixels

  static const List<Color> _palette = [
    Color(0xFF3A2010), // very dark dirt
    Color(0xFF5C3D1E), // dark dirt
    Color(0xFF7A5230), // mid-dark dirt
    Color(0xFF8B6340), // mid dirt
    Color(0xFFA07848), // light dirt
    Color(0xFFB09060), // sandy patch
    Color(0xFF6B6B6B), // stone grey
    Color(0xFF555555), // dark stone
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / _bs).ceil();
    final rows = (size.height / _bs).ceil();

    for (var row = 0; row < rows; row++) {
      final rowFrac = rows > 1 ? row / (rows - 1) : 0.5;

      for (var col = 0; col < cols; col++) {
        final xFrac = cols > 1 ? col / (cols - 1) : 0.5;

        // ── Horizontal side weight ──────────────────────────────────────
        // 1.0 at left/right edges, 0.0 at horizontal centre.
        // Power < 1 keeps the ramp gentle so the middle still gets some dirt.
        final hSide = pow((xFrac - 0.5).abs() * 2.0, 0.65).toDouble();

        // ── Oval clearing around the button content ─────────────────────
        // Semi-axes in normalised [0,1] space. rx covers ~70 % of half-width,
        // ry covers most of the height — creating a wide, squat clearing.
        const rx = 0.34;
        const ry = 0.46;
        final dx = xFrac - 0.5;
        final dy = rowFrac - 0.5;
        final ovalDist = sqrt((dx / rx) * (dx / rx) + (dy / ry) * (dy / ry));
        // Smooth ramp: 0.0 at ovalDist ≤ 0.85, 1.0 at ovalDist ≥ 1.2
        final ovalMask = ((ovalDist - 0.85) / 0.35).clamp(0.0, 1.0);

        // ── Mild vertical boost at top/bottom ───────────────────────────
        final vBoost = 0.75 + (rowFrac - 0.5).abs() * 2.0 * 0.25; // 0.75 → 1.0

        // ── Final probability (soft cap ~55 %) ──────────────────────────
        final prob = hSide * ovalMask * vBoost * 0.55;

        if (prob <= 0.0) continue;

        final seed = (row * 997 + col) ^ 0x1A3F7C2B;
        final rng = Random(seed);

        if (rng.nextDouble() < prob) {
          // Darker colours toward the outermost edges
          final maxIdx =
              (1.0 + hSide * (_palette.length - 1)).floor().clamp(1, _palette.length);
          final colorIdx = rng.nextInt(maxIdx);

          canvas.drawRect(
            Rect.fromLTWH(col * _bs, row * _bs, _bs, _bs),
            Paint()..color = _palette[colorIdx],
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DirtOverlayPainter old) => false;
}

class _EnergyDetails extends ConsumerWidget {
  const _EnergyDetails();

  static String _fmtK(int v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(energyProvider);
    final ratio = e.tokenUsageRatio;
    final tokenColor = ratio > 0.9
        ? Colors.redAccent
        : ratio > 0.7
            ? Colors.orangeAccent
            : Colors.greenAccent;
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🪫', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('Токени сьогодні', style: labelStyle),
            const Spacer(),
            Text(
              '${_fmtK(e.tokensUsedToday)} / ${_fmtK(e.dailyTokenCap)}',
              style: TextStyle(
                color: tokenColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(tokenColor),
          ),
        ),
        const SizedBox(height: 20),
        _ModelTierRow(
          label: 'Opus',
          used: e.opusTasksUsedToday,
          cap: e.opusCapPerDay,
          color: const Color(0xFFFFD54F),
        ),
        const SizedBox(height: 10),
        _ModelTierRow(
          label: 'Sonnet',
          used: e.sonnetTasksUsedToday,
          cap: e.sonnetCapPerDay,
          color: const Color(0xFF81D4FA),
        ),
      ],
    );
  }
}

class _ModelTierRow extends StatelessWidget {
  final String label;
  final int used;
  final int cap;
  final Color color;

  const _ModelTierRow({
    required this.label,
    required this.used,
    required this.cap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final exhausted = used >= cap;
    final ratio = cap == 0 ? 1.0 : (used / cap).clamp(0.0, 1.0);
    final effective =
        exhausted ? Colors.white.withValues(alpha: 0.35) : color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: effective,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$used / $cap',
              style: TextStyle(
                color: effective,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(
              exhausted ? color.withValues(alpha: 0.3) : color,
            ),
          ),
        ),
      ],
    );
  }
}
