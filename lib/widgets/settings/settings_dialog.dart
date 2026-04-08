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
          'Settings',
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
        constraints: const BoxConstraints(maxHeight: 520),
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
                    'Settings',
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
          'Clear all SDK sessions?',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          'This will delete all cached sessions from disk. '
          'The current conversation context will be lost.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
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
              'Clear',
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
          content: const Text('Server URL saved. Reconnect to apply.'),
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
        _SectionHeader(title: 'Connection'),
        const SizedBox(height: 12),
        Text(
          'Server URL',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'WebSocket address of the PixelCode server. '
          'Use your Tailscale IP for remote devices.',
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
                  child: const Text('Reset to default'),
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
                      : const Text('Save'),
                ),
              ),
            ),
          ],
        ),

        // ── Danger zone (hidden by default) ─────────────────────────────
        ...[
          const SizedBox(height: 32),
          _SectionHeader(title: 'Danger Zone'),
          const SizedBox(height: 12),
          Text(
            'Clears all cached SDK sessions from disk. '
            'The current conversation context will be lost.',
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
              label: const Text('Clear all SDK sessions'),
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
