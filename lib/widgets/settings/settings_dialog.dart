/// Modular settings dialog — adaptive for mobile (iPhone 16 Pro) and desktop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/agent_provider.dart';
import '../../providers/settings_provider.dart';

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

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  late final TextEditingController _urlController;
  bool _dirty = false;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final current = ref.read(settingsProvider).serverUrl;
    _urlController = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _confirmClearSessions(BuildContext context) {
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

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(settingsProvider.notifier).setServerUrl(
          _urlController.text.trim(),
        );
    if (mounted) {
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('URL сервера збережено. Перепідключіться для застосування.'),
          backgroundColor: const Color(0xFF2A2A30),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _reset() {
    _urlController.text = defaultServerUrl;
    setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section: Connection ──────────────────────────────────────────
        _SectionHeader(title: "З'єднання"),
        const SizedBox(height: 12),
        Text(
          'URL сервера',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'WebSocket-адреса сервера PixelCode. '
          'Використовуйте Tailscale IP для віддалених пристроїв.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _urlController,
          onChanged: (v) {
            if (!_dirty) setState(() => _dirty = true);
          },
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: defaultServerUrl,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontFamily: 'monospace',
            ),
            filled: true,
            fillColor: const Color(0xFF0E0E11),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF00C0D1),
              ),
            ),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _reset,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.6),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('За замовчуванням'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _dirty && !_saving ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00C0D1),
                    disabledBackgroundColor:
                        const Color(0xFF00C0D1).withValues(alpha: 0.3),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('Зберегти'),
                ),
              ),
            ),
          ],
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

        // ── Danger zone (hidden by default) ─────────────────────────────
        ...[
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
              onPressed: () => _confirmClearSessions(context),
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
      ],
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
