// Archive Game Main Widget
// Handles: game loop, drag-and-drop, physics, compression logic
// Uses Riverpod for state management

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/archive_crush/archive_level.dart';
import '../../models/archive_crush/archive_file.dart';
import '../../models/archive_crush/compression_animation.dart';
import '../../providers/archive_crush/archive_game_state_provider.dart';
import 'archive_levels.dart';
import 'archive_game_painter.dart';
import 'draggable_file_widget.dart';
import 'archive_statistics_panel.dart';
import 'level_selection_menu.dart';
import 'hint_display_widget.dart';

class ArchiveGame extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const ArchiveGame({super.key, required this.onClose});

  @override
  ConsumerState<ArchiveGame> createState() => _ArchiveGameState();
}

class _ArchiveGameState extends ConsumerState<ArchiveGame>
    with TickerProviderStateMixin {
  // Game state
  Timer? _gameLoopTimer;
  Timer? _compressionTimer;
  int _elapsedFrames = 0;
  int _elapsedSeconds = 0;

  // Physics state for dragged files
  final Map<String, DragPhysics> _fileDragPhysics = {};
  final Map<String, Offset> _filePositions = {};

  // UI state
  bool _showLevelMenu = true;
  int _selectedLevelIndex = -1;
  ArchiveLevel? _currentLevel;

  // Animation controller for compression animation
  late AnimationController _compressionController;

  @override
  void initState() {
    super.initState();
    _compressionController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _gameLoopTimer?.cancel();
    _compressionTimer?.cancel();
    _compressionController.dispose();
    super.dispose();
  }

  /// Starts a new game with selected level
  void _startGameWithLevel(int levelIndex) {
    final level = getLevelByIndex(levelIndex);
    if (level == null) return;

    setState(() {
      _selectedLevelIndex = levelIndex;
      _currentLevel = level;
      _showLevelMenu = false;
      _elapsedFrames = 0;
      _elapsedSeconds = 0;
      _fileDragPhysics.clear();
      _filePositions.clear();
    });

    // Initialize provider state
    ref
        .read(archiveGameStateProvider.notifier)
        .initializeLevel(level, levelIndex);

    // Initialize file positions (random in upper area)
    for (var file in level.files) {
      _initializeFilePosition(file.name);
    }

    // Start game loop
    _startGameLoop();
  }

  void _initializeFilePosition(String fileName) {
    // Random position in upper 2/3 of screen
    _filePositions[fileName] =
        const Offset(50, 80); // Will be randomized per-file in painter
    _fileDragPhysics[fileName] = DragPhysics();
  }

  void _startGameLoop() {
    _gameLoopTimer?.cancel();
    _gameLoopTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _tick();
    });
  }

  void _tick() {
    setState(() {
      _elapsedFrames++;
      if (_elapsedFrames % 60 == 0) {
        _elapsedSeconds++;
        ref
            .read(archiveGameStateProvider.notifier)
            .updateElapsedTime(_elapsedSeconds);

        // Check time limit
        if (_currentLevel != null &&
            _elapsedSeconds >= _currentLevel!.timeLimitSeconds) {
          _endGame(levelCompleted: false);
        }
      }

      // Update physics for all dragged files
      _updateFileDragPhysics();
    });
  }

  void _updateFileDragPhysics() {
    for (var entry in _fileDragPhysics.entries) {
      final physics = entry.value;
      if (physics.isDragging) {
        // Physics only applies when not actively dragging
        continue;
      }

      // Apply gravity-like drag to bottom
      physics.velocity = Offset(
        physics.velocity.dx * 0.92, // air resistance
        (physics.velocity.dy + 0.15).clamp(-10, 15), // gravity
      );

      final currentPos = _filePositions[entry.key] ?? Offset.zero;
      _filePositions[entry.key] = currentPos + physics.velocity;

      // Bounce off bottom (archive box)
      if (_filePositions[entry.key]!.dy > 250) {
        _filePositions[entry.key] =
            Offset(_filePositions[entry.key]!.dx, 250);
        physics.velocity = Offset(
          physics.velocity.dx,
          -physics.velocity.dy * 0.7, // elastic bounce
        );
      }

      // Bounce off sides
      if (_filePositions[entry.key]!.dx < 0) {
        _filePositions[entry.key] = const Offset(0, 0);
        physics.velocity = Offset(-physics.velocity.dx * 0.8, physics.velocity.dy);
      }
      if (_filePositions[entry.key]!.dx > 300) {
        _filePositions[entry.key] = const Offset(300, 0);
        physics.velocity = Offset(-physics.velocity.dx * 0.8, physics.velocity.dy);
      }
    }
  }

  void _onFileDragStart(String fileName) {
    _fileDragPhysics[fileName]?.isDragging = true;
  }

  void _onFileDragUpdate(String fileName, Offset delta) {
    final current = _filePositions[fileName] ?? Offset.zero;
    _filePositions[fileName] = current + delta;
    _fileDragPhysics[fileName]?.velocity = delta * 0.5; // momentum
  }

  void _onFileDragEnd(String fileName) {
    _fileDragPhysics[fileName]?.isDragging = false;
  }

  void _onFileDroppedInArchive(ArchiveFile file) {
    ref.read(archiveGameStateProvider.notifier).addFile(file);
    // Remove from display
    _filePositions.remove(file.name);
    _fileDragPhysics.remove(file.name);
    setState(() {});
  }

  void _startCompression() {
    final gameState = ref.read(archiveGameStateProvider);
    if (gameState.filesInArchive.isEmpty) return;

    ref.read(archiveGameStateProvider.notifier).startCompression();

    // Animate compression progress
    _compressionTimer?.cancel();
    _compressionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final current = ref.read(archiveGameStateProvider).compressionProgress;
      final next = (current + 0.05).clamp(0.0, 1.0);

      ref.read(archiveGameStateProvider.notifier).updateCompressionProgress(next);

      if (next >= 1.0) {
        _compressionTimer?.cancel();
        _checkLevelCompletion();
      }
    });
  }

  void _checkLevelCompletion() {
    if (_currentLevel == null) return;

    final gameState = ref.read(archiveGameStateProvider);
    final totalOriginal = gameState.currentLevel?.getTotalSize() ?? 0;
    final totalCompressed = gameState.currentLevel?.getCurrentTotalSize() ?? 0;
    final actualRatio = 1.0 - (totalCompressed / totalOriginal);

    if (actualRatio >= _currentLevel!.targetCompression) {
      _endGame(levelCompleted: true);
    } else {
      // Show message: not enough compression
      _showCompressionFailureMessage();
    }
  }

  void _showCompressionFailureMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not enough compression. Try again!'),
        duration: Duration(seconds: 2),
      ),
    );
    ref.read(archiveGameStateProvider.notifier).clearFiles();
  }

  void _endGame({required bool levelCompleted}) {
    _gameLoopTimer?.cancel();
    _compressionTimer?.cancel();

    if (levelCompleted) {
      ref.read(archiveGameStateProvider.notifier).completeLevel();
      _showLevelCompletedDialog();
    } else {
      _showGameOverDialog();
    }
  }

  void _showLevelCompletedDialog() {
    final gameState = ref.read(archiveGameStateProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Level Completed! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time: ${_elapsedSeconds}s'),
            Text('Files archived: ${gameState.filesInArchive.length}'),
            const SizedBox(height: 8),
            if (_selectedLevelIndex < 4)
              const Text('Ready for the next challenge?')
            else
              const Text('You completed all levels!'),
          ],
        ),
        actions: [
          if (_selectedLevelIndex < 4)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startGameWithLevel(_selectedLevelIndex + 1);
              },
              child: const Text('Next Level'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _returnToLevelMenu();
            },
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Time\'s Up!'),
        content: Text('Time elapsed: ${_elapsedSeconds}s'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startGameWithLevel(_selectedLevelIndex);
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _returnToLevelMenu();
            },
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }

  void _returnToLevelMenu() {
    setState(() {
      _showLevelMenu = true;
      _selectedLevelIndex = -1;
      _currentLevel = null;
      _fileDragPhysics.clear();
      _filePositions.clear();
    });
    _gameLoopTimer?.cancel();
    _compressionTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(archiveGameStateProvider);

    if (_showLevelMenu) {
      return LevelSelectionMenu(
        onLevelSelected: _startGameWithLevel,
        onClose: widget.onClose,
      );
    }

    if (_currentLevel == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Loading level...'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onClose,
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Header with level info
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Level ${_selectedLevelIndex + 1}: ${_currentLevel!.name}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  'Time: $_elapsedSeconds/${_currentLevel!.timeLimitSeconds}s',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                if (_currentLevel!.hint.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => HintInfoDialog(
                          hint: _currentLevel!.hint,
                          levelName: _currentLevel!.name,
                        ),
                      );
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Підказка'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[500],
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _returnToLevelMenu,
                  child: const Text('Menu'),
                )
              ],
            ),
          ),
          // Game canvas
          Expanded(
            child: Stack(
              children: [
                // Background canvas with archive box
                CustomPaint(
                  painter: ArchiveGamePainter(
                    files: gameState.filesInArchive,
                    filePositions: _filePositions,
                    animations: gameState.animations,
                    level: _currentLevel!,
                  ),
                  child: Container(),
                ),
                // Draggable files overlay
                ..._currentLevel!.files
                    .where((file) => !gameState.filesInArchive
                        .any((f) => f.name == file.name))
                    .map((file) {
                  final pos = _filePositions[file.name] ?? const Offset(50, 80);
                  return Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: DraggableFileWidget(
                      file: file,
                      onDragStart: () => _onFileDragStart(file.name),
                      onDragUpdate: (delta) => _onFileDragUpdate(file.name, delta),
                      onDragEnd: () => _onFileDragEnd(file.name),
                      onDroppedInArchive: () => _onFileDroppedInArchive(file),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Statistics panel
          ArchiveStatisticsPanel(
            level: _currentLevel!,
            gameState: gameState,
            onCompressionStarted: _startCompression,
            isCompressionRunning: gameState.isCompressing,
          ),
        ],
      ),
    );
  }
}

/// Simple physics state for dragged files
class DragPhysics {
  Offset velocity = Offset.zero;
  bool isDragging = false;
}
