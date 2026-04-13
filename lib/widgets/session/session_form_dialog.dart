/// Dialog for creating or editing a session profile.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session_profile.dart';

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

class _SessionFormContent extends StatefulWidget {
  const _SessionFormContent({
    this.existing,
    required this.onSubmit,
    required this.onCancel,
  });

  final SessionProfile? existing;
  final ValueChanged<SessionProfile> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_SessionFormContent> createState() => _SessionFormContentState();
}

class _SessionFormContentState extends State<_SessionFormContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _apiKeyCtrl;
  bool _obscureApiKey = true;

  bool get _isMobile => Platform.isIOS || Platform.isAndroid;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl = TextEditingController(text: (e?.port ?? 9720).toString());
    _apiKeyCtrl = TextEditingController(text: e?.apiKey ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final portText = _portCtrl.text.trim();
    final port = int.tryParse(portText) ?? 9720;
    final apiKey = _isMobile ? null : _apiKeyCtrl.text.trim();

    if (name.isEmpty || host.isEmpty) return;

    final profile = SessionProfile(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: port,
      apiKey: (apiKey != null && apiKey.isNotEmpty) ? apiKey : null,
    );
    widget.onSubmit(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _FieldLabel('Хост (Tailscale IP)'),
        const SizedBox(height: 6),
        _FormField(
          controller: _hostCtrl,
          hintText: '100.x.y.z',
          keyboardType: TextInputType.url,
          monospace: true,
        ),
        const SizedBox(height: 16),

        // ── Port ────────────────────────────────────────────────────────
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

        // ── API Key (desktop only) ────────────────────────────────────
        if (!_isMobile) ...[
          _FieldLabel('API Key'),
          const SizedBox(height: 6),
          _ApiKeyField(
            controller: _apiKeyCtrl,
            obscure: _obscureApiKey,
            onToggleObscure: () =>
                setState(() => _obscureApiKey = !_obscureApiKey),
          ),
          const SizedBox(height: 8),
          Text(
            'ANTHROPIC_API_KEY для локального сервера. '
            'Залиш порожнім для віддалених сесій.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
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
    this.obscureText = false,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final bool monospace;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final fontFamily = monospace ? 'monospace' : null;
    return TextField(
      controller: controller,
      obscureText: obscureText,
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
        suffixIcon: suffixIcon,
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

// ─── API Key field with show/hide toggle ─────────────────────────────────────

class _ApiKeyField extends StatelessWidget {
  const _ApiKeyField({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return _FormField(
      controller: controller,
      hintText: 'sk-ant-...',
      monospace: true,
      obscureText: obscure,
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
          color: Colors.white.withValues(alpha: 0.4),
        ),
        onPressed: onToggleObscure,
      ),
    );
  }
}
