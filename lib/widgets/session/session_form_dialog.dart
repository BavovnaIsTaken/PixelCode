/// Dialog for creating or editing a session profile.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../services/network_discovery_service.dart';

/// Opens a dialog to create (or edit) a [SessionProfile].
///
/// Pass [existing] to pre-populate fields for an edit. Returns the completed
/// [SessionProfile] on confirm, or `null` if cancelled.
Future<SessionProfile?> showSessionFormDialog(
  BuildContext context, {
  SessionProfile? existing,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < 600;

  if (isNarrow) {
    return Navigator.of(context).push<SessionProfile?>(
      MaterialPageRoute<SessionProfile?>(
        fullscreenDialog: true,
        builder: (_) => _SessionFormPage(existing: existing),
      ),
    );
  }

  return showDialog<SessionProfile?>(
    context: context,
    builder: (_) => Center(child: _SessionFormDialog(existing: existing)),
  );
}

// ─── Full-screen page for mobile ─────────────────────────────────────────────

class _SessionFormPage extends StatelessWidget {
  const _SessionFormPage({this.existing});
  final SessionProfile? existing;

  @override
  Widget build(BuildContext context) {
    final isEdit = existing != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1F),
        title: Text(
          isEdit ? 'Редагувати сесію' : 'Нова сесія',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: _SessionFormContent(
            existing: existing,
            onSubmit: (profile) => Navigator.of(context).pop(profile),
            onCancel: () => Navigator.of(context).pop(null),
          ),
        ),
      ),
    );
  }
}

// ─── Desktop dialog ──────────────────────────────────────────────────────────

class _SessionFormDialog extends StatelessWidget {
  const _SessionFormDialog({this.existing});
  final SessionProfile? existing;

  @override
  Widget build(BuildContext context) {
    final isEdit = existing != null;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 600),
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
                  Text(
                    isEdit ? 'Редагувати сесію' : 'Нова сесія',
                    style: const TextStyle(
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
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: _SessionFormContent(
                  existing: existing,
                  onSubmit: (profile) => Navigator.of(context).pop(profile),
                  onCancel: () => Navigator.of(context).pop(null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared form content ──────────────────────────────────────────────────────

class _SessionFormContent extends ConsumerStatefulWidget {
  const _SessionFormContent({
    this.existing,
    required this.onSubmit,
    required this.onCancel,
  });

  final SessionProfile? existing;
  final ValueChanged<SessionProfile> onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_SessionFormContent> createState() =>
      _SessionFormContentState();
}

class _SessionFormContentState extends ConsumerState<_SessionFormContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;

  // ── Network discovery ──────────────────────────────────────────────────────
  List<DiscoveredServer> _discovered = [];
  bool _scanning = false;
  StreamSubscription<DiscoveredServer>? _scanSub;

  bool get _isEdit => widget.existing != null;

  /// True when the entered host is a secure tunnel domain (port is ignored).
  bool get _isSecureHost {
    final h = _hostCtrl.text.trim();
    return h.endsWith('.ts.net') ||
        h.endsWith('.trycloudflare.com') ||
        h.startsWith('wss://');
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl = TextEditingController(text: (e?.port ?? 9720).toString());
    _hostCtrl.addListener(() => setState(() {}));
    // Auto-scan on open (only for new sessions, not edits)
    if (!_isEdit) _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _discovered = [];
    });
    final ws = ref.read(wsServiceProvider);
    _scanSub = discoverServers(onLog: ws.log).listen(
      (server) {
        if (mounted) setState(() => _discovered.add(server));
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  void _selectDiscovered(DiscoveredServer server) {
    // One-tap connect: directly create profile and return
    final profile = SessionProfile(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: server.name,
      host: server.host,
      port: server.port,
    );
    widget.onSubmit(profile);
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9720;

    if (name.isEmpty || host.isEmpty) return;

    final profile = SessionProfile(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: port,
    );
    widget.onSubmit(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Network discovery ────────────────────────────────────────────
        _ScanSection(
          scanning: _scanning,
          discovered: _discovered,
          onScan: _startScan,
          onSelect: _selectDiscovered,
        ),
        const SizedBox(height: 20),

        // ── "or enter manually" divider ─────────────────────────────────
        if (!_isEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'або введіть вручну',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),

        // ── Name ────────────────────────────────────────────────────────
        _FieldLabel('Назва'),
        const SizedBox(height: 6),
        _FormField(
          controller: _nameCtrl,
          hintText: 'Робочий MacBook',
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),

        // ── Host ────────────────────────────────────────────────────────
        _FieldLabel('Хост (IP або домен)'),
        const SizedBox(height: 6),
        _FormField(
          controller: _hostCtrl,
          hintText: '100.x.y.z',
          keyboardType: TextInputType.url,
          monospace: true,
        ),
        const SizedBox(height: 16),

        // ── Port ────────────────────────────────────────────────────────
        if (_isSecureHost) ...[
          _FieldLabel('Порт'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E11),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Text(
              'не використовується (Tailscale Funnel)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          _FieldLabel('Порт'),
          const SizedBox(height: 6),
          _FormField(
            controller: _portCtrl,
            hintText: '9720',
            keyboardType: TextInputType.number,
            monospace: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
        ],

        // ── Buttons ──────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.6),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Скасувати'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00C0D1),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(_isEdit ? 'Зберегти' : 'Додати'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Reusable field label ────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ─── Reusable text field ──────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.monospace = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final bool monospace;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final fontFamily = monospace ? 'monospace' : null;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      autocorrect: false,
      inputFormatters: inputFormatters,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontFamily: fontFamily,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontFamily: fontFamily,
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
          borderSide: const BorderSide(color: Color(0xFF00C0D1)),
        ),
      ),
    );
  }
}

// ─── Network scan section ────────────────────────────────────────────────────

class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.scanning,
    required this.discovered,
    required this.onScan,
    required this.onSelect,
  });

  final bool scanning;
  final List<DiscoveredServer> discovered;
  final VoidCallback onScan;
  final ValueChanged<DiscoveredServer> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Сервери в мережі',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: scanning ? null : onScan,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00C0D1),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.wifi_find_outlined, size: 14),
                label: const Text(
                  'Сканувати',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (scanning && discovered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E11),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF00C0D1),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Шукаємо сервери в мережі…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else if (!scanning && discovered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E11),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              'Серверів не знайдено',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 12,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E11),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < discovered.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  _DiscoveredServerTile(
                    server: discovered[i],
                    onTap: () => onSelect(discovered[i]),
                  ),
                ],
                if (scanning)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF00C0D1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Шукаємо…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DiscoveredServerTile extends StatelessWidget {
  const _DiscoveredServerTile({required this.server, required this.onTap});

  final DiscoveredServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.computer_outlined,
              size: 16,
              color: const Color(0xFF00C0D1).withValues(alpha: 0.8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${server.host}:${server.port}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Підключити',
              style: TextStyle(
                color: const Color(0xFF00C0D1).withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
