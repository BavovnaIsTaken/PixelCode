import 'package:equatable/equatable.dart';

/// Результат завершення рівня
class GameResult extends Equatable {
  final int levelId;
  final String levelName;
  final bool isCompleted;
  final int timeSpent; // секунди
  final int timeLimit; // секунди
  final double compressionAchieved; // 0.0 - 1.0
  final double targetCompression;
  final int score; // очки за рівень

  const GameResult({
    required this.levelId,
    required this.levelName,
    required this.isCompleted,
    required this.timeSpent,
    required this.timeLimit,
    required this.compressionAchieved,
    required this.targetCompression,
    required this.score,
  });

  /// Розраховує бонус за час
  int getTimeBonus() {
    if (!isCompleted) return 0;
    final remainingTime = timeLimit - timeSpent;
    return (remainingTime * 10).toInt().clamp(0, 500);
  }

  /// Розраховує бонус за якість компресії
  int getCompressionBonus() {
    if (!isCompleted) return 0;
    final compressionDiff =
        (compressionAchieved - targetCompression).abs();
    if (compressionDiff < 0.05) return 500; // Ідеальна компресія
    if (compressionDiff < 0.1) return 300;
    if (compressionDiff < 0.2) return 100;
    return 0;
  }

  /// Копіювання з новими значеннями
  GameResult copyWith({
    int? levelId,
    String? levelName,
    bool? isCompleted,
    int? timeSpent,
    int? timeLimit,
    double? compressionAchieved,
    double? targetCompression,
    int? score,
  }) {
    return GameResult(
      levelId: levelId ?? this.levelId,
      levelName: levelName ?? this.levelName,
      isCompleted: isCompleted ?? this.isCompleted,
      timeSpent: timeSpent ?? this.timeSpent,
      timeLimit: timeLimit ?? this.timeLimit,
      compressionAchieved: compressionAchieved ?? this.compressionAchieved,
      targetCompression: targetCompression ?? this.targetCompression,
      score: score ?? this.score,
    );
  }

  @override
  List<Object?> get props => [
        levelId,
        levelName,
        isCompleted,
        timeSpent,
        timeLimit,
        compressionAchieved,
        targetCompression,
        score,
      ];
}
