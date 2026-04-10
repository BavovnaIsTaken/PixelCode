/// A pixel-art coin that spins around its Y axis using sprite animation.
///
/// 6 hand-drawn frames show the coin rotating from face-on → edge → back →
/// edge → face-on. Each frame is a 16×16 grid rendered pixel by pixel.
library;

import 'dart:async';

import 'package:flutter/material.dart';

// ─── Palette ────────────────────────────────────────────────────────────────

const _coinColors = <String, Color>{
  '.': Color(0x00000000), // transparent
  'G': Color(0xFFFFE066), // gold highlight
  'g': Color(0xFFFFD700), // gold
  'D': Color(0xFFDAA520), // dark gold
  'R': Color(0xFFB8860B), // rim
  'r': Color(0xFF8B6914), // rim dark
  'S': Color(0xFF6B4F0A), // shadow
  'T': Color(0xFF4A3000), // symbol / deep shadow
};

// ─── Frames ─────────────────────────────────────────────────────────────────
//
// 8 frames of a 16×16 coin rotating around Y.
// Frame 0: face-on (full circle)
// Frame 1-3: turning towards edge
// Frame 4: edge-on (thin cylinder)
// Frame 5-7: turning back (showing back face)

/// Frame 0 — front face, full circle with ₲ symbol.
const _frame0 = [
  '......gggg......',
  '....GGggggDD....',
  '...GGggggggDD...',
  '..GGggTTTTggDD..',
  '..GgggT..TggDD..',
  '.GggggTTTTgggDD.',
  '.GggggT..TgggDD.',
  '.GggggT..TgggDD.',
  '.GggggTTTTgggDD.',
  '.GggggT...gggDD.',
  '.GggggT...gggDD.',
  '..GgggggggggDD..',
  '..GGggggggggDD..',
  '...GGggggggDD...',
  '....GGggggDD....',
  '......gggg......',
];

/// Frame 1 — slightly turned.
const _frame1 = [
  '.......ggg......',
  '.....GGgggD.....',
  '....GGgggggD....',
  '...GGgTTTggDD...',
  '...GggT.TggDD...',
  '..GgggTTTgggDD..',
  '..GgggT.TgggDD..',
  '..GgggT.TgggDD..',
  '..GgggTTTgggDD..',
  '..GgggT..gggDD..',
  '..GgggT..gggDD..',
  '...GggggggggD...',
  '...GGgggggggD...',
  '....GGgggggD....',
  '.....GGgggD.....',
  '.......ggg......',
];

/// Frame 2 — more turned, narrower.
const _frame2 = [
  '........gg......',
  '.......GggD.....',
  '......GgggDD....',
  '.....GGTTggDD...',
  '.....GgT.ggDD...',
  '....GgTTTggDDD..',
  '....GgT.TggDDD..',
  '....GgT.TggDDD..',
  '....GgTTTggDDD..',
  '....GgT..ggDDD..',
  '....GgT..ggDDD..',
  '.....GgggggDD...',
  '.....GGggggDD...',
  '......GgggDD....',
  '.......GggD.....',
  '........gg......',
];

/// Frame 3 — nearly edge, very narrow face.
const _frame3 = [
  '.........g......',
  '........gRD.....',
  '.......gRRDD....',
  '.......gRRDD....',
  '......gRRRDD....',
  '......gRRRDDD...',
  '......gRRRDDD...',
  '......gRRRDDD...',
  '......gRRRDDD...',
  '......gRRRDDD...',
  '......gRRRDD....',
  '.......gRRDD....',
  '.......gRRDD....',
  '.......gRDD.....',
  '........gRD.....',
  '.........g......',
];

/// Frame 4 — edge-on (thinnest, just the rim).
const _frame4 = [
  '..........R.....',
  '.........RR.....',
  '.........RR.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '........RRS.....',
  '.........RR.....',
  '.........RR.....',
  '..........R.....',
];

/// Frame 5 — past edge, showing back face (mirrored of frame 3).
const _frame5 = [
  '......g.........',
  '.....DR.........',
  '....DDRRg.......',
  '....DDRRg.......',
  '....DDRRRg......',
  '...DDDRRRg......',
  '...DDDRRRg......',
  '...DDDRRRg......',
  '...DDDRRRg......',
  '...DDDRRRg......',
  '....DDRRRg......',
  '....DDRRg.......',
  '....DDRRg.......',
  '.....DDRg.......',
  '.....DRg........',
  '......g.........',
];

/// Frame 6 — back face, wider (mirrored of frame 2).
const _frame6 = [
  '......gg........',
  '.....DggG.......',
  '....DDggG.......',
  '...DDggTGG......',
  '...DDgg.TGG.....',
  '..DDDggTTTgG....',
  '..DDDggT.TgG....',
  '..DDDggT.TgG....',
  '..DDDggTTTgG....',
  '..DDDgg..TgG....',
  '..DDDgg..TgG....',
  '...DDgggggG.....',
  '...DDggggGG.....',
  '....DDgggG......',
  '.....DggG.......',
  '......gg........',
];

/// Frame 7 — back face, almost full (mirrored of frame 1).
const _frame7 = [
  '......ggg.......',
  '.....DgggGG.....',
  '....DgggggGG....',
  '...DDggTTTgGG...',
  '...DDgg.T.gGG...',
  '..DDgggTTTggGG..',
  '..DDggT..TggGG..',
  '..DDggT..TggGG..',
  '..DDgggTTTggGG..',
  '..DDggg..TggGG..',
  '..DDggg..TggGG..',
  '...DgggggggGG...',
  '...DgggggggGG...',
  '....DgggggGG....',
  '.....DgggGG.....',
  '......ggg.......',
];

const _frames = [
  _frame0, _frame1, _frame2, _frame3,
  _frame4, _frame5, _frame6, _frame7,
];

// ─── Widget ─────────────────────────────────────────────────────────────────

/// Pixel-art spinning coin. Renders a 16×16 sprite animation.
///
/// [pixelSize] controls how large each logical pixel is drawn on screen.
class SpinningCoin extends StatefulWidget {
  final double pixelSize;

  const SpinningCoin({super.key, this.pixelSize = 2.0});

  @override
  State<SpinningCoin> createState() => _SpinningCoinState();
}

class _SpinningCoinState extends State<SpinningCoin> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final px = widget.pixelSize;
    return CustomPaint(
      size: Size(16 * px, 16 * px),
      painter: _CoinSpritePainter(frame: _frames[_frame], px: px),
    );
  }
}

// ─── Painter ────────────────────────────────────────────────────────────────

class _CoinSpritePainter extends CustomPainter {
  final List<String> frame;
  final double px;

  const _CoinSpritePainter({required this.frame, required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < frame.length; y++) {
      final row = frame[y];
      for (var x = 0; x < row.length; x++) {
        final key = row[x];
        if (key == '.') continue;
        final color = _coinColors[key];
        if (color == null) continue;

        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * px, y * px, px, px),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CoinSpritePainter old) => old.frame != frame;
}
