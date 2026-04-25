/// Tiny terminal-style status widget shown next to the mobile session picker
/// while a WebSocket session is being established. Displays a `>` prompt and a
/// short phase token (≤5 chars). On every phase change the new token is
/// revealed left-to-right with a "matrix glitch" — each position scrambles
/// through random ASCII for a moment, then locks to the target character.
///
/// When the connection is established (phase becomes `null`) the widget hides
/// itself, freeing the slot for the regular header UI (coins, devices, etc).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/agent_provider.dart';

class ConnectionTerminal extends ConsumerStatefulWidget {
  const ConnectionTerminal({super.key});

  @override
  ConsumerState<ConnectionTerminal> createState() => _ConnectionTerminalState();
}

class _ConnectionTerminalState extends ConsumerState<ConnectionTerminal> {
  // Pool of glyphs that show up during the scramble. Mix of symbols + alnum
  // gives a recognizable "matrix-y" look without going full katakana.
  static const String _glitchChars =
      '!<>-_\\/[]{}=+*^?#%&abcdefghijklmnopqrstuvwxyz0123456789';

  // Per-position scramble window (ms) and how long each character keeps
  // glitching before snapping to the target.
  static const int _staggerMs = 55;
  static const int _glitchDurMs = 140;
  static const int _tickMs = 32;

  final Random _rng = Random();
  Timer? _ticker;
  String _target = '';
  DateTime _animStart = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final initial = ref.read(connectionPhaseProvider).valueOrNull;
    if (initial != null && initial.isNotEmpty) {
      // Run after first frame so setState in _startGlitch is safe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startGlitch(initial);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startGlitch(String newTarget) {
    _target = newTarget;
    _animStart = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: _tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final totalMs =
          _staggerMs * max(_target.length - 1, 0) + _glitchDurMs;
      final elapsed = DateTime.now().difference(_animStart).inMilliseconds;
      if (elapsed >= totalMs) {
        t.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _target = '';
  }

  String _frame() {
    if (_target.isEmpty) return '';
    final elapsed = DateTime.now().difference(_animStart).inMilliseconds;
    final buf = StringBuffer();
    for (int i = 0; i < _target.length; i++) {
      final lockAt = i * _staggerMs + _glitchDurMs;
      if (elapsed >= lockAt) {
        buf.write(_target[i]);
      } else {
        buf.write(_glitchChars[_rng.nextInt(_glitchChars.length)]);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(connectionPhaseProvider, (prev, next) {
      final phase = next.valueOrNull;
      if (phase == null || phase.isEmpty) {
        _stop();
        return;
      }
      if (phase != _target) _startGlitch(phase);
    });

    final phase = ref.watch(connectionPhaseProvider).valueOrNull;
    if (phase == null || phase.isEmpty) return const SizedBox.shrink();

    // First mount path: build runs before initState's post-frame callback,
    // so _target may still be empty for one frame. Show the target directly
    // in that case so the user never sees a blank box.
    final text = _target.isEmpty ? phase : _frame();

    const phosphor = Color(0xFF00FF66);

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: phosphor.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '>',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: phosphor.withValues(alpha: 0.7),
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: phosphor,
              height: 1.0,
              letterSpacing: 0.5,
              shadows: [
                Shadow(color: phosphor, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
