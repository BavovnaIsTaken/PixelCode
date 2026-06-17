import 'package:equatable/equatable.dart';
import 'dart:math';

/// Стан анімації для файлу під час компресії
class CompressionAnimation extends Equatable {
  final String fileId;
  final double scaleX; // 1.0 - нормальний розмір, 0.5 - половина
  final double scaleY;
  final double offsetX; // зміщення від центру
  final double offsetY;
  final double rotationAngle; // радіани
  final double opacity; // 1.0 - повна видимість
  final bool isCompressing; // в процесі?
  final double compressionProgress; // 0.0 - 1.0

  const CompressionAnimation({
    required this.fileId,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.rotationAngle = 0.0,
    this.opacity = 1.0,
    this.isCompressing = false,
    this.compressionProgress = 0.0,
  });

  /// Оновлює анімацію на основі прогресу (0.0 - 1.0)
  CompressionAnimation updateProgress(double progress) {
    if (!isCompressing || progress >= 1.0) {
      return copyWith(
        scaleX: 0.8,
        scaleY: 0.8,
        rotationAngle: 0.0,
        compressionProgress: 1.0,
        isCompressing: false,
      );
    }

    // Анімація: зміщення, обертання, масштабування
    final squishFactor = (sin(progress * pi) * 0.3) + 0.7; // 0.7 - 1.0
    final rotangle = progress * pi * 2; // один повний оберт
    final offsetMod = sin(progress * pi * 2) * 20;

    return copyWith(
      scaleX: squishFactor,
      scaleY: squishFactor * 0.8, // стиснення по вертикалі
      rotationAngle: rotangle,
      offsetX: offsetMod,
      offsetY: offsetMod * 0.5,
      compressionProgress: progress,
    );
  }

  /// Копіювання з новими значеннями
  CompressionAnimation copyWith({
    String? fileId,
    double? scaleX,
    double? scaleY,
    double? offsetX,
    double? offsetY,
    double? rotationAngle,
    double? opacity,
    bool? isCompressing,
    double? compressionProgress,
  }) {
    return CompressionAnimation(
      fileId: fileId ?? this.fileId,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      opacity: opacity ?? this.opacity,
      isCompressing: isCompressing ?? this.isCompressing,
      compressionProgress: compressionProgress ?? this.compressionProgress,
    );
  }

  @override
  List<Object?> get props => [
        fileId,
        scaleX,
        scaleY,
        offsetX,
        offsetY,
        rotationAngle,
        opacity,
        isCompressing,
        compressionProgress,
      ];
}
