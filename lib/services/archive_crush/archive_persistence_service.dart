import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/archive_crush/game_result.dart';

/// Сервіс для збереження результатів рівнів
class ArchivePersistenceService {
  static final ArchivePersistenceService _instance =
      ArchivePersistenceService._internal();

  factory ArchivePersistenceService() {
    return _instance;
  }

  ArchivePersistenceService._internal();

  static const String _resultsKey = 'archive_crush_results';
  static const String _totalScoreKey = 'archive_crush_total_score';

  /// Зберігає результат рівня
  Future<void> saveResult(GameResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final results = await getResults();

      // Замінює результат якщо рівень вже пройден
      results.removeWhere((r) => r.levelId == result.levelId);
      results.add(result);

      final jsonList = results
          .map((r) => jsonEncode({
                'levelId': r.levelId,
                'levelName': r.levelName,
                'isCompleted': r.isCompleted,
                'timeSpent': r.timeSpent,
                'timeLimit': r.timeLimit,
                'compressionAchieved': r.compressionAchieved,
                'targetCompression': r.targetCompression,
                'score': r.score,
              }))
          .toList();

      await prefs.setStringList(_resultsKey, jsonList);

      // Оновлює загальний рахунок
      final totalScore =
          results.fold<int>(0, (sum, r) => sum + r.score);
      await prefs.setInt(_totalScoreKey, totalScore);
    } catch (e) {
      print('Error saving result: $e');
    }
  }

  /// Отримує всі результати
  Future<List<GameResult>> getResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_resultsKey) ?? [];

      return jsonList
          .map((json) {
            final map = jsonDecode(json) as Map<String, dynamic>;
            return GameResult(
              levelId: map['levelId'] as int,
              levelName: map['levelName'] as String,
              isCompleted: map['isCompleted'] as bool,
              timeSpent: map['timeSpent'] as int,
              timeLimit: map['timeLimit'] as int,
              compressionAchieved: map['compressionAchieved'] as double,
              targetCompression: map['targetCompression'] as double,
              score: map['score'] as int,
            );
          })
          .toList();
    } catch (e) {
      print('Error getting results: $e');
      return [];
    }
  }

  /// Отримує результат для конкретного рівня
  Future<GameResult?> getResultForLevel(int levelId) async {
    final results = await getResults();
    try {
      return results.firstWhere((r) => r.levelId == levelId);
    } catch (_) {
      return null;
    }
  }

  /// Отримує загальний рахунок
  Future<int> getTotalScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_totalScoreKey) ?? 0;
    } catch (e) {
      print('Error getting total score: $e');
      return 0;
    }
  }

  /// Очищує всі результати
  Future<void> clearResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resultsKey);
      await prefs.remove(_totalScoreKey);
    } catch (e) {
      print('Error clearing results: $e');
    }
  }

  /// Перевіряє чи рівень пройден
  Future<bool> isLevelCompleted(int levelId) async {
    final result = await getResultForLevel(levelId);
    return result?.isCompleted ?? false;
  }

  /// Отримує список ID рівнів що пройдені
  Future<List<int>> getCompletedLevels() async {
    final results = await getResults();
    return results.where((r) => r.isCompleted).map((r) => r.levelId).toList();
  }
}
