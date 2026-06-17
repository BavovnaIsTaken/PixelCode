import 'package:equatable/equatable.dart';
import 'archive_file.dart';

/// Рівень гри Archive Crush
class ArchiveLevel extends Equatable {
  final int id;
  final String name;
  final String description;
  final List<ArchiveFile> files;
  final double targetCompression; // скільки % має бути стиснення
  final int timeLimitSeconds;
  final int difficulty; // 1-5
  final String hint; // Поясна підказка для учнів

  const ArchiveLevel({
    required this.id,
    required this.name,
    required this.description,
    required this.files,
    required this.targetCompression,
    required this.timeLimitSeconds,
    this.difficulty = 1,
    this.hint = '',
  });

  /// Копіювання з новими значеннями
  ArchiveLevel copyWith({
    int? id,
    String? name,
    String? description,
    List<ArchiveFile>? files,
    double? targetCompression,
    int? timeLimitSeconds,
    int? difficulty,
    String? hint,
  }) {
    return ArchiveLevel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      files: files ?? this.files,
      targetCompression: targetCompression ?? this.targetCompression,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
      difficulty: difficulty ?? this.difficulty,
      hint: hint ?? this.hint,
    );
  }

  /// Загальний розмір всіх файлів
  int getTotalSize() {
    return files.fold(0, (sum, file) => sum + file.originalSize);
  }

  /// Загальний поточний розмір (з урахуванням компресії)
  int getCurrentTotalSize() {
    return files.fold(0, (sum, file) => sum + file.getCompressedSize());
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        files,
        targetCompression,
        timeLimitSeconds,
        difficulty,
        hint,
      ];
}
