/// Compact, responsive AI provider auth section.
///
/// Replaces the previous one-row-per-provider layout with a card grid that
/// scales to many providers across desktop and mobile. Each provider renders
/// as a self-contained card; API-key flows expand inline rather than opening
/// a separate modal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/claude_auth_provider.dart';
import '../../providers/deepseek_auth_provider.dart';
import '../../providers/gemini_auth_provider.dart';
import '../../providers/kimi_auth_provider.dart';

const _accent = Color(0xFF00C0D1);
const _connected = Color(0xFF22C55E);
const _danger = Color(0xFFEF4444);
const _warning = Color(0xFFFFB347);

class AuthProvidersSection extends ConsumerWidget {
  const AuthProvidersSection({super.key});

  static const double _gap = 10;
  static const double _twoColBreakpoint = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[
      _claudeCard(ref),
      _geminiCard(ref),
      _deepseekCard(ref),
      _kimiCard(ref),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final twoCol = constraints.maxWidth >= _twoColBreakpoint;
        if (!twoCol) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i != 0) const SizedBox(height: _gap),
                cards[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += 2) {
          if (i != 0) rows.add(const SizedBox(height: _gap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[i]),
                const SizedBox(width: _gap),
                Expanded(
                  child: i + 1 < cards.length
                      ? cards[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  Widget _claudeCard(WidgetRef ref) {
    final async = ref.watch(claudeAuthProvider);
    return async.when(
      loading: () => const _ProviderCard(
        name: 'Claude',
        kind: _AuthKind.oauth,
        glyph: 'A',
        state: _CardState.loading,
      ),
      error: (_, _) => _ProviderCard(
        name: 'Claude',
        kind: _AuthKind.oauth,
        glyph: 'A',
        state: _CardState.error,
        onPrimary: () => ref.read(claudeAuthProvider.notifier).refresh(),
      ),
      data: (status) {
        if (status.loggedIn) {
          final plan = status.subscriptionType ?? status.authMethod;
          final org = status.orgName;
          final meta = (plan != null && org != null) ? '$plan · $org' : plan;
          return _ProviderCard(
            name: 'Claude',
            kind: _AuthKind.oauth,
            glyph: 'A',
            state: _CardState.connected,
            metadata: meta,
            onPrimary: () => ref.read(claudeAuthProvider.notifier).logout(),
          );
        }
        return _ProviderCard(
          name: 'Claude',
          kind: _AuthKind.oauth,
          glyph: 'A',
          state: _CardState.offline,
          onPrimary: () => ref.read(claudeAuthProvider.notifier).login(),
        );
      },
    );
  }

  Widget _geminiCard(WidgetRef ref) {
    final async = ref.watch(geminiAuthProvider);
    return async.when(
      loading: () => const _ProviderCard(
        name: 'Gemini',
        kind: _AuthKind.oauth,
        glyph: 'G',
        state: _CardState.loading,
      ),
      error: (_, _) => _ProviderCard(
        name: 'Gemini',
        kind: _AuthKind.oauth,
        glyph: 'G',
        state: _CardState.error,
        onPrimary: () => ref.read(geminiAuthProvider.notifier).refresh(),
      ),
      data: (status) {
        if (status.loggedIn) {
          return _ProviderCard(
            name: 'Gemini',
            kind: _AuthKind.oauth,
            glyph: 'G',
            state: _CardState.connected,
            metadata: status.email,
            onPrimary: () => ref.read(geminiAuthProvider.notifier).logout(),
          );
        }
        return _ProviderCard(
          name: 'Gemini',
          kind: _AuthKind.oauth,
          glyph: 'G',
          state: _CardState.offline,
          onPrimary: () => ref.read(geminiAuthProvider.notifier).login(),
        );
      },
    );
  }

  Widget _deepseekCard(WidgetRef ref) {
    final async = ref.watch(deepseekAuthProvider);
    return async.when(
      loading: () => const _ProviderCard(
        name: 'DeepSeek',
        kind: _AuthKind.apiKey,
        glyph: 'D',
        state: _CardState.loading,
      ),
      error: (_, _) => _ProviderCard(
        name: 'DeepSeek',
        kind: _AuthKind.apiKey,
        glyph: 'D',
        state: _CardState.error,
        onPrimary: () => ref.read(deepseekAuthProvider.notifier).refresh(),
      ),
      data: (status) {
        if (status.linked) {
          return _ProviderCard(
            name: 'DeepSeek',
            kind: _AuthKind.apiKey,
            glyph: 'D',
            state: _CardState.connected,
            metadata: status.maskedKey,
            onPrimary: () =>
                ref.read(deepseekAuthProvider.notifier).clearKey(),
          );
        }
        return _ProviderCard(
          name: 'DeepSeek',
          kind: _AuthKind.apiKey,
          glyph: 'D',
          state: _CardState.offline,
          onSubmitKey: (key) =>
              ref.read(deepseekAuthProvider.notifier).saveKey(key),
        );
      },
    );
  }

  Widget _kimiCard(WidgetRef ref) {
    final async = ref.watch(kimiAuthProvider);
    const warning = 'Дані запитів проходять через сервер у КНР. '
        'Не використовуйте з приватним кодом.';
    return async.when(
      loading: () => const _ProviderCard(
        name: 'Kimi',
        kind: _AuthKind.apiKey,
        glyph: 'K',
        state: _CardState.loading,
        warning: warning,
      ),
      error: (_, _) => _ProviderCard(
        name: 'Kimi',
        kind: _AuthKind.apiKey,
        glyph: 'K',
        state: _CardState.error,
        warning: warning,
        onPrimary: () => ref.read(kimiAuthProvider.notifier).refresh(),
      ),
      data: (status) {
        if (status.linked) {
          return _ProviderCard(
            name: 'Kimi',
            kind: _AuthKind.apiKey,
            glyph: 'K',
            state: _CardState.connected,
            warning: warning,
            metadata: status.maskedKey,
            onPrimary: () => ref.read(kimiAuthProvider.notifier).clearKey(),
          );
        }
        return _ProviderCard(
          name: 'Kimi',
          kind: _AuthKind.apiKey,
          glyph: 'K',
          state: _CardState.offline,
          warning: warning,
          onSubmitKey: (key) =>
              ref.read(kimiAuthProvider.notifier).saveKey(key),
        );
      },
    );
  }
}

enum _AuthKind { oauth, apiKey }

enum _CardState { offline, loading, connected, error }

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({
    required this.name,
    required this.kind,
    required this.glyph,
    required this.state,
    this.metadata,
    this.warning,
    this.onPrimary,
    this.onSubmitKey,
  });

  final String name;
  final _AuthKind kind;
  final String glyph;
  final _CardState state;
  final String? metadata;
  final String? warning;
  final VoidCallback? onPrimary;
  final void Function(String key)? onSubmitKey;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _expanded = false;
  bool _obscure = true;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ProviderCard old) {
    super.didUpdateWidget(old);
    if (_expanded && widget.state != _CardState.offline) {
      _expanded = false;
      _ctrl.clear();
    }
  }

  bool get _canExpand =>
      widget.kind == _AuthKind.apiKey &&
      widget.state == _CardState.offline &&
      widget.onSubmitKey != null;

  void _submit() {
    final key = _ctrl.text.trim();
    if (key.isEmpty) return;
    widget.onSubmitKey?.call(key);
  }

  String get _ctaLabel {
    switch (widget.state) {
      case _CardState.loading:
        return '';
      case _CardState.error:
        return 'RETRY';
      case _CardState.connected:
        return widget.kind == _AuthKind.oauth ? 'LOGOUT' : 'CLEAR';
      case _CardState.offline:
        return widget.kind == _AuthKind.oauth ? 'CONNECT' : 'ADD KEY';
    }
  }

  VoidCallback? get _ctaOnPressed {
    switch (widget.state) {
      case _CardState.loading:
        return null;
      case _CardState.offline:
        return _canExpand
            ? () => setState(() => _expanded = !_expanded)
            : widget.onPrimary;
      case _CardState.connected:
      case _CardState.error:
        return widget.onPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.state == _CardState.connected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isConnected
            ? _connected.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color: isConnected
              ? _connected.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _titleRow(),
          if (widget.metadata != null && widget.metadata!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _metadataLine(widget.metadata!),
          ],
          const SizedBox(height: 8),
          _bottomRow(),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded ? _expandedKeyForm() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _titleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _glyph(),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.warning != null) ...[
                    const SizedBox(width: 5),
                    _warningGlyph(widget.warning!),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.kind == _AuthKind.oauth ? 'OAUTH' : 'API KEY',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.32),
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _glyph() {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.glyph,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          height: 1.0,
        ),
      ),
    );
  }

  Widget _warningGlyph(String message) {
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border.all(color: _warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Container(
        width: 14,
        height: 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _warning.withValues(alpha: 0.18),
          border: Border.all(color: _warning.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text(
          '!',
          style: TextStyle(
            color: _warning,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            height: 1.0,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _metadataLine(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 11,
        fontFamily: 'monospace',
        height: 1.15,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _bottomRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _statusBadge(),
        const Spacer(),
        if (!_expanded) _ctaButton(),
      ],
    );
  }

  Widget _statusBadge() {
    final Color color;
    final String label;
    switch (widget.state) {
      case _CardState.connected:
        color = _connected;
        label = 'CONNECTED';
      case _CardState.loading:
        color = Colors.white.withValues(alpha: 0.35);
        label = '· · ·';
      case _CardState.error:
        color = _danger;
        label = 'ERROR';
      case _CardState.offline:
        color = Colors.white.withValues(alpha: 0.35);
        label = 'OFFLINE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontFamily: 'monospace',
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _ctaButton() {
    if (widget.state == _CardState.loading) {
      return SizedBox(
        width: 28,
        height: 22,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ),
      );
    }
    final isOffline = widget.state == _CardState.offline;
    final isConnected = widget.state == _CardState.connected;
    final isError = widget.state == _CardState.error;

    final bg = isOffline ? _accent : Colors.transparent;
    final fg = isOffline
        ? Colors.black
        : (isError ? _accent : Colors.white.withValues(alpha: 0.55));
    final border = isOffline
        ? _accent
        : (isConnected
            ? Colors.white.withValues(alpha: 0.18)
            : _accent.withValues(alpha: 0.4));

    return SizedBox(
      height: 22,
      child: TextButton(
        onPressed: _ctaOnPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 22),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: border),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        child: Text(
          _ctaLabel,
          style: const TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _expandedKeyForm() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'sk-...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: _accent),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _expanded = false;
                      _ctrl.clear();
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    child: const Text(
                      'SAVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
