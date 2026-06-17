import 'package:flutter/material.dart';

/// Піксельарт кнопка для гри
class GameButtonPainter extends CustomPainter {
  final String label;
  final GameButtonType buttonType;
  final bool isPressed;
  final bool isHovered;
  final bool isDisabled;

  GameButtonPainter({
    required this.label,
    required this.buttonType,
    this.isPressed = false,
    this.isHovered = false,
    this.isDisabled = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Основний колір кнопки
    paint.color = _getButtonColor();

    // Малюємо кнопку
    final buttonRect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(buttonRect, const Radius.circular(4)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(buttonRect, const Radius.circular(4)),
      outlinePaint,
    );

    // 3D ефект — світла та темна лінія
    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black38;

    // Тінь внизу та справа
    canvas.drawLine(
      Offset(8, size.height - 10),
      Offset(size.width - 8, size.height - 10),
      shadowPaint,
    );
    canvas.drawLine(
      Offset(size.width - 10, 8),
      Offset(size.width - 10, size.height - 8),
      shadowPaint,
    );

    // Якщо натиснута — затемнюємо
    if (isPressed) {
      paint.color = Colors.black12;
      canvas.drawRRect(
        RRect.fromRectAndRadius(buttonRect, const Radius.circular(4)),
        paint,
      );
    }

    // Якщо вимкнена — сірий фільтр
    if (isDisabled) {
      paint.color = Colors.grey.withOpacity(0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(buttonRect, const Radius.circular(4)),
        paint,
      );
    }
  }

  Color _getButtonColor() {
    if (isDisabled) return Colors.grey.shade300;
    
    switch (buttonType) {
      case GameButtonType.archive:
        return const Color(0xFF4CAF50); // Зелений — архівувати
      case GameButtonType.extract:
        return const Color(0xFF2196F3); // Синій — розпакувати
      case GameButtonType.next:
        return const Color(0xFFFF9800); // Оранжевий — далі
      case GameButtonType.reset:
        return const Color(0xFFF44336); // Червоний — повернути
    }
  }

  @override
  bool shouldRepaint(GameButtonPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.buttonType != buttonType ||
        oldDelegate.isPressed != isPressed ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.isDisabled != isDisabled;
  }
}

enum GameButtonType { archive, extract, next, reset }

/// Текстова мітка для кнопок
class ButtonLabel extends StatelessWidget {
  final String label;
  final bool isDisabled;

  const ButtonLabel({
    required this.label,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: isDisabled ? Colors.grey : Colors.white,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Компонент кнопки з піксельартом
class ArchiveGameButton extends StatefulWidget {
  final String label;
  final GameButtonType buttonType;
  final VoidCallback? onPressed;
  final bool isDisabled;

  const ArchiveGameButton({
    required this.label,
    required this.buttonType,
    this.onPressed,
    this.isDisabled = false,
  });

  @override
  State<ArchiveGameButton> createState() => _ArchiveGameButtonState();
}

class _ArchiveGameButtonState extends State<ArchiveGameButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: widget.isDisabled ? null : (_) => setState(() => _isPressed = true),
        onTapUp: widget.isDisabled
            ? null
            : (_) {
                setState(() => _isPressed = false);
                widget.onPressed?.call();
              },
        onTapCancel: widget.isDisabled ? null : () => setState(() => _isPressed = false),
        child: CustomPaint(
          painter: GameButtonPainter(
            label: widget.label,
            buttonType: widget.buttonType,
            isPressed: _isPressed,
            isHovered: _isHovered,
            isDisabled: widget.isDisabled,
          ),
          size: const Size(120, 48),
          child: Center(
            child: ButtonLabel(
              label: widget.label,
              isDisabled: widget.isDisabled,
            ),
          ),
        ),
      ),
    );
  }
}

/// Шкала компресії файлів
class CompressionProgressBar extends StatelessWidget {
  final double progress; // 0.0 - 1.0
  final String label;

  const CompressionProgressBar({
    required this.progress,
    this.label = 'Компресія',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 4),
        CustomPaint(
          painter: ProgressBarPainter(
            progress: progress,
            backgroundColor: const Color(0xFFE0E0E0),
            foregroundColor: const Color(0xFF4CAF50),
          ),
          size: const Size(200, 20),
        ),
        const SizedBox(height: 4),
        Text(
          '${(progress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF757575),
          ),
        ),
      ],
    );
  }
}

/// Паinter для прогресс-бару
class ProgressBarPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color foregroundColor;

  ProgressBarPainter({
    required this.progress,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final fgPaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Фон шкали
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      borderPaint,
    );

    // Прогрес
    final fgRect = Rect.fromLTWH(0, 0, size.width * progress.clamp(0.0, 1.0), size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fgRect, const Radius.circular(3)),
      fgPaint,
    );

    // Маркери прогресу
    final markerCount = 4;
    for (int i = 1; i < markerCount; i++) {
      final x = (size.width / markerCount) * i;
      final markerPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Компонент для показу статистики (розмір, файли)
class StatisticsWidget extends StatelessWidget {
  final int fileCount;
  final int totalSize; // в умовних одиницях
  final int compressedSize;
  final Duration duration;

  const StatisticsWidget({
    required this.fileCount,
    required this.totalSize,
    required this.compressedSize,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final compression = totalSize > 0 ? (1 - (compressedSize / totalSize)).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: Colors.black87, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatItem(
            label: 'Файлів:',
            value: fileCount.toString(),
            icon: '📄',
          ),
          const SizedBox(height: 8),
          _StatItem(
            label: 'Розмір:',
            value: '$totalSize → $compressedSize KB',
            icon: '📦',
          ),
          const SizedBox(height: 8),
          _StatItem(
            label: 'Економія:',
            value: '${(compression * 100).toStringAsFixed(1)}%',
            icon: '💾',
            color: compression > 0.3 ? Colors.green : Colors.orange,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  final Color? color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          icon,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color ?? const Color(0xFF2196F3),
          ),
        ),
      ],
    );
  }
}

/// Індикатор розміру файлу (як мініатюра)
class FileSizeIndicator extends StatelessWidget {
  final int sizeInKB;
  final double maxWidth;

  const FileSizeIndicator({
    required this.sizeInKB,
    this.maxWidth = 150,
  });

  @override
  Widget build(BuildContext context) {
    // Логарифмічна шкала для візуалізації
    final logSize = (sizeInKB.toDouble() + 1).log() / 10;
    final width = (logSize * maxWidth).clamp(20.0, maxWidth);

    return CustomPaint(
      painter: FileSizeIndicatorPainter(
        width: width,
        maxWidth: maxWidth,
      ),
      size: Size(maxWidth + 20, 24),
    );
  }
}

class FileSizeIndicatorPainter extends CustomPainter {
  final double width;
  final double maxWidth;

  FileSizeIndicatorPainter({
    required this.width,
    required this.maxWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF2196F3);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black87;

    // Контейнер для індикатора
    final containerRect = Rect.fromLTWH(0, 4, maxWidth + 2, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(containerRect, const Radius.circular(2)),
      outlinePaint,
    );

    // Заповнена частина
    final fillRect = Rect.fromLTWH(1, 5, width.clamp(0, maxWidth), 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, const Radius.circular(1)),
      paint,
    );
  }

  @override
  bool shouldRepaint(FileSizeIndicatorPainter oldDelegate) {
    return oldDelegate.width != width;
  }
}
