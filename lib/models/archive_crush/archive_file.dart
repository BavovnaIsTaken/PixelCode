import 'package:equatable/equatable.dart';

/// Файл, що потрібно архівувати в грі Archive Crush
class ArchiveFile extends Equatable {
  final String name;
  final int originalSize; // байти
  final double compressionRatio; // 0.0 - 1.0, як файл стискується
  final String fileType; // jpg, pdf, mp4, etc.
  double currentCompression; // поточний рівень стиснення під час анімації
  double currentSize; // поточний розмір

  ArchiveFile({
    required this.name,
    required this.originalSize,
    required this.compressionRatio,
    required this.fileType,
    this.currentCompression = 0.0,
  }) : currentSize = originalSize.toDouble();

  /// Розраховує поточний розмір на основі прогресу компресії
  int getCompressedSize() {
    final compressed =
        originalSize * (1 - (compressionRatio * currentCompression));
    return compressed.toInt();
  }

  /// Копіювання з новими значеннями
  ArchiveFile copyWith({
    String? name,
    int? originalSize,
    double? compressionRatio,
    String? fileType,
    double? currentCompression,
    double? currentSize,
  }) {
    return ArchiveFile(
      name: name ?? this.name,
      originalSize: originalSize ?? this.originalSize,
      compressionRatio: compressionRatio ?? this.compressionRatio,
      fileType: fileType ?? this.fileType,
      currentCompression: currentCompression ?? this.currentCompression,
    )..currentSize = currentSize ?? this.currentSize;
  }

  @override
  List<Object?> get props => [
        name,
        originalSize,
        compressionRatio,
        fileType,
        currentCompression,
      ];
}
