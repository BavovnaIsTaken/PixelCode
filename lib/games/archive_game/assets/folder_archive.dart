import 'package:flutter/material.dart';

/// Спрайт папки
class FolderPainter extends CustomPainter {
  final bool isOpen;
  final bool isSelected;
  final Color folderColor;

  FolderPainter({
    this.isOpen = false,
    this.isSelected = false,
    this.folderColor = const Color(0xFFFFB74D),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Виліпа папки
    final tabRect = Rect.fromLTWH(10, 12, 28, 12);
    paint.color = folderColor.withOpacity(0.8);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        tabRect,
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        tabRect,
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ),
      outlinePaint,
    );

    // Основна частина папки
    final mainRect = Rect.fromLTWH(8, 22, 48, 38);
    paint.color = folderColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(mainRect, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(mainRect, const Radius.circular(3)),
      outlinePaint,
    );

    // Якщо відкрита папка — малюємо позначення
    if (isOpen) {
      paint.color = Colors.white.withOpacity(0.3);
      canvas.drawRect(Rect.fromLTWH(12, 28, 40, 6), paint);
      canvas.drawRect(Rect.fromLTWH(12, 38, 40, 6), paint);
    }

    // Вибрана папка
    if (isSelected) {
      outlinePaint.color = Colors.yellow;
      outlinePaint.strokeWidth = 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(6, 10, 52, 52),
          const Radius.circular(4),
        ),
        outlinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(FolderPainter oldDelegate) {
    return oldDelegate.isOpen != isOpen ||
        oldDelegate.isSelected != isSelected;
  }
}

/// Спрайт архіву (ZIP файл)
class ArchivePainter extends CustomPainter {
  final bool isSelected;
  final double compressionLevel;

  ArchivePainter({
    this.isSelected = false,
    this.compressionLevel = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Основна форма архіву (як замок)
    final rect = Rect.fromLTWH(10, 14, 44, 52);
    paint.color = const Color(0xFFE91E63); // Яскравий рожевий
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      outlinePaint,
    );

    // Архів — блискавка спереду
    paint.color = Colors.yellow;
    final zipPath = Path()
      ..moveTo(24, 24)
      ..lineTo(28, 28)
      ..lineTo(24, 32)
      ..lineTo(28, 36)
      ..lineTo(24, 40)
      ..lineTo(28, 44);
    canvas.drawPath(zipPath, paint);
    outlinePaint.color = Colors.black87;
    canvas.drawPath(zipPath, outlinePaint);

    // Індикатор компресії
    if (compressionLevel < 1.0) {
      paint.color = Colors.green;
      final compressRect = Rect.fromLTWH(
        12,
        60,
        40 * compressionLevel,
        4,
      );
      canvas.drawRect(compressRect, paint);
      outlinePaint.color = Colors.black87;
      canvas.drawRect(
        Rect.fromLTWH(12, 60, 40, 4),
        outlinePaint,
      );
    }

    // Вибрана іконка
    if (isSelected) {
      outlinePaint.color = Colors.yellow;
      outlinePaint.strokeWidth = 3;
      final selectionRect = Rect.fromLTWH(8, 12, 48, 56);
      canvas.drawRect(selectionRect, outlinePaint);
    }
  }

  @override
  bool shouldRepaint(ArchivePainter oldDelegate) {
    return oldDelegate.isSelected != isSelected ||
        oldDelegate.compressionLevel != compressionLevel;
  }
}

/// Анімована архівна коробка з молнією (відкривається/закривається)
class AnimatedArchiveBoxPainter extends CustomPainter {
  final double openProgress; // 0.0 закрита, 1.0 відкрита
  final bool isSelected;

  AnimatedArchiveBoxPainter({
    required this.openProgress,
    this.isSelected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Основна форма коробки
    final boxRect = Rect.fromLTWH(8, 20 + (openProgress * 5), 48, 40 - (openProgress * 10));
    paint.color = const Color(0xFFE91E63);
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(4)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(4)),
      outlinePaint,
    );

    // Верхня кришка (піднімається при відкритті)
    final lidOffset = openProgress * 25;
    final lidRect = Rect.fromLTWH(8, 16 - lidOffset, 48, 8);
    paint.color = const Color(0xFFD81B60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lidRect, const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lidRect, const Radius.circular(2)),
      outlinePaint,
    );

    // Молнія (ZIP) на коробці
    paint.color = Colors.yellow;
    final zipX = 24 + (openProgress * 3);
    final zipStartY = 26;
    for (int i = 0; i < 3; i++) {
      final y = zipStartY + (i * 8);
      canvas.drawLine(
        Offset(zipX, y),
        Offset(zipX + 4, y + 2),
        paint..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(zipX + 4, y + 2),
        Offset(zipX, y + 4),
        paint..strokeWidth = 1.5,
      );
    }

    // Замок символ (коли закрита)
    if (openProgress < 0.3) {
      paint.color = Colors.orange;
      canvas.drawCircle(Offset(38, 26), 3, paint);
      canvas.drawRect(Rect.fromLTWH(36, 30, 4, 4), paint);
    }

    // Вибрана коробка
    if (isSelected) {
      outlinePaint.color = Colors.yellow;
      outlinePaint.strokeWidth = 3;
      canvas.drawRect(Rect.fromLTWH(6, 14, 52, 54), outlinePaint);
    }
  }

  @override
  bool shouldRepaint(AnimatedArchiveBoxPainter oldDelegate) {
    return oldDelegate.openProgress != openProgress ||
        oldDelegate.isSelected != isSelected;
  }
}

/// Компонент для анімованої архівної коробки
class AnimatedArchiveBox extends StatefulWidget {
  final VoidCallback? onOpenComplete;
  final Duration duration;
  final double size;

  const AnimatedArchiveBox({
    this.onOpenComplete,
    this.duration = const Duration(milliseconds: 800),
    this.size = 80,
  });

  @override
  State<AnimatedArchiveBox> createState() => _AnimatedArchiveBoxState();
}

class _AnimatedArchiveBoxState extends State<AnimatedArchiveBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _openAnimation;
  bool _isOpening = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _openAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void open() {
    if (!_isOpening) {
      _isOpening = true;
      _controller.forward().then((_) {
        widget.onOpenComplete?.call();
      });
    }
  }

  void reset() {
    _isOpening = false;
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _openAnimation,
      builder: (context, _) {
        return CustomPaint(
          painter: AnimatedArchiveBoxPainter(
            openProgress: _openAnimation.value,
          ),
          size: Size(widget.size, widget.size),
        );
      },
    );
  }
}

/// Контейнер для файлів та архіву
class ContainerPainter extends CustomPainter {
  final int fileCount;
  final bool isEmpty;
  final Color containerColor;

  ContainerPainter({
    this.fileCount = 0,
    this.isEmpty = true,
    this.containerColor = const Color(0xFF90CAF9),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Основа контейнера
    final rect = Rect.fromLTWH(10, 10, 44, 44);
    paint.color = containerColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      outlinePaint,
    );

    if (isEmpty) {
      // Порожній контейнер — знак запитання
      paint.color = Colors.grey;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2 - 2), 8, paint);
    } else {
      // Показуємо кількість файлів
      paint.color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(16, 18, 4, 4), paint);
      canvas.drawRect(Rect.fromLTWH(24, 18, 4, 4), paint);
      canvas.drawRect(Rect.fromLTWH(32, 18, 4, 4), paint);

      if (fileCount > 1) {
        canvas.drawRect(Rect.fromLTWH(16, 26, 4, 4), paint);
        canvas.drawRect(Rect.fromLTWH(24, 26, 4, 4), paint);
      }

      if (fileCount > 2) {
        canvas.drawRect(Rect.fromLTWH(32, 26, 4, 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(ContainerPainter oldDelegate) {
    return oldDelegate.fileCount != fileCount ||
        oldDelegate.isEmpty != isEmpty;
  }
}
