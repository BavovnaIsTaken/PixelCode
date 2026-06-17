import 'package:flutter/material.dart';

/// Піксельарт іконки для різних типів файлів у грі архівації
class FileIconPainter extends CustomPainter {
  final FileType fileType;
  final bool isSelected;
  final bool isAnimating;
  final double animationProgress;
  final Color primaryColor;
  final Color accentColor;

  FileIconPainter({
    required this.fileType,
    this.isSelected = false,
    this.isAnimating = false,
    this.animationProgress = 0.0,
    this.primaryColor = const Color(0xFF2196F3),
    this.accentColor = const Color(0xFFFFEB3B),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Базовий фон іконки (файл)
    const double cornerRadius = 4;
    final rect = Rect.fromLTWH(8, 8, 48, 56);

    // Рисуємо корпус файла
    paint.color = _getFileColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(cornerRadius)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(cornerRadius)),
      outlinePaint,
    );

    // Загин сторінки (верхній правий кут)
    paint.color = Colors.white70;
    final foldPath = Path()
      ..moveTo(48, 8)
      ..lineTo(56, 8)
      ..lineTo(48, 16)
      ..close();
    canvas.drawPath(foldPath, paint);
    canvas.drawPath(foldPath, outlinePaint);

    // Малюємо тип файла
    switch (fileType) {
      case FileType.text:
        _paintTextFile(canvas, paint, outlinePaint);
      case FileType.image:
        _paintImageFile(canvas, paint, outlinePaint);
      case FileType.music:
        _paintMusicFile(canvas, paint, outlinePaint);
      case FileType.video:
        _paintVideoFile(canvas, paint, outlinePaint);
    }

    // Вибрана іконка — рамка
    if (isSelected) {
      outlinePaint.color = Colors.yellow;
      outlinePaint.strokeWidth = 3;
      final selectionRect = Rect.fromLTWH(6, 6, 52, 60);
      canvas.drawRect(selectionRect, outlinePaint);
    }
  }

  void _paintTextFile(Canvas canvas, Paint paint, Paint outlinePaint) {
    paint.color = Colors.blue;
    // Три лінії тексту
    canvas.drawRect(Rect.fromLTWH(16, 24, 32, 3), paint);
    canvas.drawRect(Rect.fromLTWH(16, 32, 28, 3), paint);
    canvas.drawRect(Rect.fromLTWH(16, 40, 30, 3), paint);
  }

  void _paintImageFile(Canvas canvas, Paint paint, Paint outlinePaint) {
    // Гора та сонце
    paint.color = Colors.orange;
    // Сонце
    canvas.drawCircle(Offset(38, 22), 5, paint);
    // Гора
    paint.color = Colors.green;
    final mountainPath = Path()
      ..moveTo(16, 44)
      ..lineTo(28, 28)
      ..lineTo(40, 40)
      ..lineTo(48, 32)
      ..lineTo(48, 44)
      ..close();
    canvas.drawPath(mountainPath, paint);
  }

  void _paintMusicFile(Canvas canvas, Paint paint, Paint outlinePaint) {
    paint.color = Colors.purple;
    // Нотні значки
    // Перша нота
    canvas.drawCircle(Offset(26, 42), 4, paint);
    canvas.drawLine(Offset(30, 42), Offset(30, 22), outlinePaint);
    // Друга нота
    canvas.drawCircle(Offset(38, 45), 4, paint);
    canvas.drawLine(Offset(42, 45), Offset(42, 25), outlinePaint);
  }

  void _paintVideoFile(Canvas canvas, Paint paint, Paint outlinePaint) {
    paint.color = Colors.red;
    // Play трикутник
    final playPath = Path()
      ..moveTo(22, 25)
      ..lineTo(22, 45)
      ..lineTo(42, 35)
      ..close();
    canvas.drawPath(playPath, paint);
  }

  Color _getFileColor() {
    switch (fileType) {
      case FileType.text:
        return const Color(0xFFE3F2FD); // Світло-синій
      case FileType.image:
        return const Color(0xFFFFF3E0); // Світло-оранжевий
      case FileType.music:
        return const Color(0xFFF3E5F5); // Світло-фіолетовий
      case FileType.video:
        return const Color(0xFFFFEBEE); // Світло-червоний
    }
  }

  @override
  bool shouldRepaint(FileIconPainter oldDelegate) {
    return oldDelegate.fileType != fileType ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isAnimating != isAnimating ||
        oldDelegate.animationProgress != animationProgress;
  }
}

/// Компонент для динамічного відображення іконки файлу
class FileIcon extends StatelessWidget {
  final FileType fileType;
  final bool isSelected;
  final double size;

  const FileIcon({
    super.key,
    required this.fileType,
    this.isSelected = false,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FileIconPainter(
        fileType: fileType,
        isSelected: isSelected,
      ),
      size: Size(size, size * 1.125), // Файл більш високий ніж широкий
    );
  }
}

/// Анімована іконка файлу (для анімації вхідження в архів)
class AnimatedFileIcon extends StatefulWidget {
  final FileType fileType;
  final Duration duration;
  final AnimationStatus status;
  final double size;

  const AnimatedFileIcon({
    required this.fileType,
    this.duration = const Duration(milliseconds: 500),
    this.status = AnimationStatus.dismissed,
    this.size = 64,
  });

  @override
  State<AnimatedFileIcon> createState() => _AnimatedFileIconState();
}

class _AnimatedFileIconState extends State<AnimatedFileIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    if (widget.status == AnimationStatus.forward) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedFileIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      if (widget.status == AnimationStatus.forward) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: FileIcon(
        fileType: widget.fileType,
        size: widget.size,
      ),
    );
  }
}

enum FileType { text, image, music, video }
