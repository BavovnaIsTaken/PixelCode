import 'package:flutter/material.dart';
import '../admin_client.dart';
import '../theme.dart';

class ConfigPage extends StatelessWidget {
  const ConfigPage({
    super.key,
    required this.snapshot,
    required this.serverRunning,
    required this.onSave,
    required this.onSaveAndRestart,
    required this.onReload,
  });

  final ConfigSnapshot? snapshot;
  final bool serverRunning;
  final Future<void> Function(Map<String, dynamic> patch) onSave;
  final Future<void> Function(Map<String, dynamic> patch) onSaveAndRestart;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConfigCard(
          snapshot: snapshot,
          serverRunning: serverRunning,
          onSave: onSave,
          onSaveAndRestart: onSaveAndRestart,
          onReload: onReload,
        ),
      ],
    );
  }
}

class _ConfigCard extends StatefulWidget {
  const _ConfigCard({
    required this.snapshot,
    required this.serverRunning,
    required this.onSave,
    required this.onSaveAndRestart,
    required this.onReload,
  });

  final ConfigSnapshot? snapshot;
  final bool serverRunning;
  final Future<void> Function(Map<String, dynamic> patch) onSave;
  final Future<void> Function(Map<String, dynamic> patch) onSaveAndRestart;
  final VoidCallback onReload;

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  final _portCtrl = TextEditingController();
  final _cwdCtrl = TextEditingController();
  final _otaCtrl = TextEditingController();
  ConfigSnapshot? _shown;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _ConfigCard old) {
    super.didUpdateWidget(old);
    final snap = widget.snapshot;
    if (snap != null && snap != _shown) {
      _shown = snap;
      _portCtrl.text = '${snap.file.port}';
      _cwdCtrl.text = snap.file.projectCwd;
      _otaCtrl.text = snap.file.otaHostname ?? '';
    }
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _cwdCtrl.dispose();
    _otaCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _collectPatch() {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be a number in 1..65535')),
      );
      return null;
    }
    final cwd = _cwdCtrl.text.trim();
    if (cwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project cwd cannot be empty')),
      );
      return null;
    }
    final ota = _otaCtrl.text.trim();
    return {
      'port': port,
      'projectCwd': cwd,
      'otaHostname': ota.isEmpty ? null : ota
    };
  }

  Future<void> _run(Future<void> Function(Map<String, dynamic>) action) async {
    final patch = _collectPatch();
    if (patch == null) return;
    setState(() => _saving = true);
    try {
      await action(patch);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final disabled = _saving || snap == null || !widget.serverRunning;
    return PixelCard(
      title: 'Configuration',
      titleColor: PixelPalette.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.serverRunning)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PixelPalette.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: PixelPalette.gold.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Server is offline — config edits go through /admin/api/config '
                'which needs the server running. Start it first.',
                style: TextStyle(
                    color: PixelPalette.gold.withValues(alpha: 0.9),
                    fontSize: 12),
              ),
            ),
          _field(
              label: 'PORT',
              controller: _portCtrl,
              hint: '9720',
              disabled: disabled),
          _field(
              label: 'PROJECT CWD',
              controller: _cwdCtrl,
              hint: '/path/to/project',
              disabled: disabled),
          _field(
              label: 'OTA HOSTNAME',
              controller: _otaCtrl,
              hint: '(optional, e.g. mac.local)',
              disabled: disabled),
          const SizedBox(height: 6),
          if (snap != null) ...[
            Text(
              'Config file: ${snap.configPath}',
              style: const TextStyle(
                  color: PixelPalette.textLow,
                  fontSize: 11,
                  fontFamily: 'Menlo'),
            ),
            if (snap.envOverrides.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'env overrides: ${snap.envOverrides.join(", ")}',
                  style: const TextStyle(
                      color: PixelPalette.warn, fontSize: 11),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed:
                    disabled ? null : () => _run(widget.onSave),
                style: pixelFilledStyle(color: PixelPalette.accent),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('SAVE'),
              ),
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => _run(widget.onSaveAndRestart),
                style: pixelOutlinedStyle(foreground: PixelPalette.accent),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('SAVE & RESTART'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : widget.onReload,
                style:
                    pixelOutlinedStyle(foreground: PixelPalette.textMed),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('RELOAD'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool disabled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: pixelFont(
                    size: 8,
                    color: PixelPalette.textMed,
                    letterSpacing: 1.4)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !disabled,
              style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 13,
                  color: PixelPalette.textHigh),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PixelPalette.surfaceDim,
                hintText: hint,
                hintStyle: const TextStyle(
                    color: PixelPalette.textLow, fontFamily: 'Menlo'),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: PixelPalette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: PixelPalette.accent),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                      color: PixelPalette.border.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
