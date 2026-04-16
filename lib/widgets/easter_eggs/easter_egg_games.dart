import 'package:flutter/material.dart';

import 'arkanoid_game.dart';
import 'xquest2_game.dart';

/// Tab wrapper for easter egg games — Arkanoid and XQuest.
class EasterEggGames extends StatefulWidget {
  final VoidCallback onClose;

  const EasterEggGames({super.key, required this.onClose});

  @override
  State<EasterEggGames> createState() => _EasterEggGamesState();
}

class _EasterEggGamesState extends State<EasterEggGames> {
  int _tab = 0; // 0 = Arkanoid, 1 = XQuest

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 28,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                _tabBtn('ARKANOID', 0),
                _tabBtn('XQUEST 2', 1),
              ],
            ),
          ),
          // Game
          Expanded(
            child: _tab == 0
                ? ArkanoidGame(onClose: widget.onClose)
                : XQuest2Game(onClose: widget.onClose),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final selected = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? const Color(0xFF00C0D1)
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF00C0D1)
                  : Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
