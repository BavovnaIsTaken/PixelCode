import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/archive_crush/archive_level.dart';
import '../../models/archive_crush/archive_file.dart';
import '../../models/archive_crush/compression_animation.dart';

/// Стан гри Archive Crush
class ArchiveGameState {
  final int currentLevelIndex; // 0-based індекс рівня
  final ArchiveLevel? currentLevel;
  final List<ArchiveFile> filesInArchive; // файли що додані до архіву
  final List<CompressionAnimation> animations; // стани анімацій
  final bool isCompressing; // в процесі компресії?
  final double compressionProgress; // 0.0 - 1.0
  final int elapsedSeconds; // скільки секунд пройшло
  final bool gameOver; // рівень закінчений?
  final bool levelCompleted; // рівень завершений успішно?

  const ArchiveGameState({
    this.currentLevelIndex = 0,
    this.currentLevel,
    this.filesInArchive = const [],
    this.animations = const [],
    this.isCompressing = false,
    this.compressionProgress = 0.0,
    this.elapsedSeconds = 0,
    this.gameOver = false,
    this.levelCompleted = false,
  });

  ArchiveGameState copyWith({
    int? currentLevelIndex,
    ArchiveLevel? currentLevel,
    List<ArchiveFile>? filesInArchive,
    List<CompressionAnimation>? animations,
    bool? isCompressing,
    double? compressionProgress,
    int? elapsedSeconds,
    bool? gameOver,
    bool? levelCompleted,
  }) {
    return ArchiveGameState(
      currentLevelIndex: currentLevelIndex ?? this.currentLevelIndex,
      currentLevel: currentLevel ?? this.currentLevel,
      filesInArchive: filesInArchive ?? this.filesInArchive,
      animations: animations ?? this.animations,
      isCompressing: isCompressing ?? this.isCompressing,
      compressionProgress: compressionProgress ?? this.compressionProgress,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      gameOver: gameOver ?? this.gameOver,
      levelCompleted: levelCompleted ?? this.levelCompleted,
    );
  }
}

/// StateNotifier для управління станом гри
class ArchiveGameStateNotifier extends StateNotifier<ArchiveGameState> {
  ArchiveGameStateNotifier() : super(const ArchiveGameState());

  /// Ініціалізує новий рівень
  void initializeLevel(ArchiveLevel level, int levelIndex) {
    state = state.copyWith(
      currentLevelIndex: levelIndex,
      currentLevel: level,
      filesInArchive: [],
      animations: [],
      isCompressing: false,
      compressionProgress: 0.0,
      elapsedSeconds: 0,
      gameOver: false,
      levelCompleted: false,
    );
  }

  /// Додає файл до архіву
  void addFile(ArchiveFile file) {
    if (state.currentLevel == null) return;

    final updatedFiles = [...state.filesInArchive, file];
    final updatedAnimations = [
      ...state.animations,
      CompressionAnimation(fileId: file.name),
    ];

    state = state.copyWith(
      filesInArchive: updatedFiles,
      animations: updatedAnimations,
    );
  }

  /// Видаляє файл з архіву
  void removeFile(String fileName) {
    final updatedFiles =
        state.filesInArchive.where((f) => f.name != fileName).toList();
    final updatedAnimations =
        state.animations.where((a) => a.fileId != fileName).toList();

    state = state.copyWith(
      filesInArchive: updatedFiles,
      animations: updatedAnimations,
    );
  }

  /// Очищує всі файли
  void clearFiles() {
    state = state.copyWith(
      filesInArchive: [],
      animations: [],
      isCompressing: false,
      compressionProgress: 0.0,
    );
  }

  /// Починає анімацію компресії
  void startCompression() {
    if (state.filesInArchive.isEmpty) return;

    state = state.copyWith(isCompressing: true);
  }

  /// Оновлює прогрес компресії (0.0 - 1.0)
  void updateCompressionProgress(double progress) {
    if (!state.isCompressing) return;

    // Оновлює анімації для кожного файлу
    final updatedAnimations = state.animations.map((anim) {
      return anim.copyWith(
        isCompressing: true,
        compressionProgress: progress,
      );
    }).toList();

    // Оновлює стан файлів (їх currentCompression)
    final updatedFiles = state.filesInArchive.map((file) {
      return file.copyWith(currentCompression: progress);
    }).toList();

    state = state.copyWith(
      compressionProgress: progress,
      animations: updatedAnimations,
      filesInArchive: updatedFiles,
      isCompressing: progress < 1.0,
      gameOver: progress >= 1.0,
    );
  }

  /// Оновлює витрачений час
  void updateElapsedTime(int seconds) {
    state = state.copyWith(elapsedSeconds: seconds);

    // Перевіряє чи вийшов час
    if (state.currentLevel != null &&
        seconds >= state.currentLevel!.timeLimitSeconds) {
      state = state.copyWith(gameOver: true);
    }
  }

  /// Позначає рівень як завершений
  void completeLevel() {
    state = state.copyWith(levelCompleted: true, gameOver: true);
  }

  /// Скидає рівень
  void resetLevel() {
    if (state.currentLevel != null) {
      initializeLevel(state.currentLevel!, state.currentLevelIndex);
    }
  }
}

/// Provider для стану гри
final archiveGameStateProvider =
    StateNotifierProvider<ArchiveGameStateNotifier, ArchiveGameState>(
  (ref) => ArchiveGameStateNotifier(),
);
