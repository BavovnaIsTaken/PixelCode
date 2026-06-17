// Level Selection Menu — shows available levels and difficulty

import 'package:flutter/material.dart';
import 'archive_levels.dart';
import 'hint_display_widget.dart';

class LevelSelectionMenu extends StatelessWidget {
  final Function(int levelIndex) onLevelSelected;
  final VoidCallback onClose;

  const LevelSelectionMenu({
    super.key,
    required this.onLevelSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final levels = generateArchiveLevels();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue[50]!,
              Colors.blue[100]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Text(
                      '📦 Archive Crush 📦',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compress files to free up space!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              // Levels grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: levels.length,
                  itemBuilder: (context, index) {
                    return LevelCard(
                      level: levels[index],
                      levelIndex: index,
                      onTap: () => onLevelSelected(index),
                    );
                  },
                ),
              ),
              // Footer
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: onClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[400],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Close Game',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LevelCard extends StatefulWidget {
  final dynamic level;
  final int levelIndex;
  final VoidCallback onTap;

  const LevelCard({
    super.key,
    required this.level,
    required this.levelIndex,
    required this.onTap,
  });

  @override
  State<LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<LevelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;

    return MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: GestureDetector(
        onTap: () {
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 1.0 + (_controller.value * 0.05);
            final elevation = _controller.value * 8;

            return Transform.scale(
              scale: scale,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8 + elevation,
                      offset: Offset(0, 2 + elevation / 4),
                    ),
                  ],
                  border: Border.all(
                    color: _getDifficultyColor(level.difficulty),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Level title and icon
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _getLevelIcon(widget.levelIndex),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Level ${widget.levelIndex + 1}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            level.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Level info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(
                              '📁 Files:',
                              '${level.files.length}',
                            ),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                              '⏱️ Time:',
                              '${level.timeLimitSeconds}s',
                            ),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                              '📊 Target:',
                              '${(level.targetCompression * 100).toStringAsFixed(0)}%',
                            ),
                            const SizedBox(height: 8),
                            // Difficulty stars
                            Wrap(
                              spacing: 2,
                              children: List.generate(
                                5,
                                (i) => Text(
                                  i < level.difficulty ? '⭐' : '☆',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Hint button
                            if (level.hint.isNotEmpty)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => HintInfoDialog(
                                        hint: level.hint,
                                        levelName: level.name,
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber[100],
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.amber[400]!,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.info_outline,
                                          size: 14,
                                          color: Colors.amber,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Підказка',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.amber[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey[700],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Color _getDifficultyColor(int difficulty) {
    switch (difficulty) {
      case 1:
        return Colors.green[400]!;
      case 2:
        return Colors.blue[400]!;
      case 3:
        return Colors.orange[400]!;
      case 4:
        return Colors.red[400]!;
      case 5:
        return Colors.purple[600]!;
      default:
        return Colors.grey[400]!;
    }
  }

  Widget _getLevelIcon(int index) {
    const icons = ['🥚', '🐣', '🐥', '🦆', '🦅'];
    return Text(
      icons[index % icons.length],
      style: const TextStyle(fontSize: 16),
    );
  }
}
