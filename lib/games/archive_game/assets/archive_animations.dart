import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Анімація файлу, що входить у архів
class FileToArchiveAnimation extends StatefulWidget {
  final String fileLabel;
  final Duration duration;
  final VoidCallback? onComplete;

  const FileToArchiveAnimation({
    required this.fileLabel,
    this.duration = const Duration(milliseconds: 1500),
    this.onComplete,
  });

  @override
  State<FileToArchiveAnimation> createState() => _FileToArchiveAnimationState();
}

class _FileToArchiveAnimationState extends State<FileToArchiveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _xAnimation;
  late Animation<double> _yAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..forward().whenComplete(() {
        widget.onComplete?.call();
      });

    // Рух вправо та вверх (до архіву)
    _xAnimation = Tween<double>(begin: 0, end: 100).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _yAnimation = Tween<double>(begin: 0, end: -80).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Зменшення розміру
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // Легке обертання
    _rotationAnimation = Tween<double>(begin: 0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
        return Transform.translate(
          offset: Offset(_xAnimation.value, _yAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: 64,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          border: Border.all(color: Colors.black87, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            widget.fileLabel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Анімація стискання архіву
class CompressionAnimation extends StatefulWidget {
  final Duration duration;

  const CompressionAnimation({
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<CompressionAnimation> createState() => _CompressionAnimationState();
}

class _CompressionAnimationState extends State<CompressionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat(reverse: true);
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
        // Архів зменшується та збільшується
        final scale = 1.0 - (_controller.value * 0.2);
        final opacity = 0.7 + (_controller.value * 0.3);

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: CustomPaint(
              painter: CompressingArchivePainter(
                compressionValue: _controller.value,
              ),
              size: const Size(80, 80),
            ),
          ),
        );
      },
    );
  }
}

/// Паinter для архіву, що стискається
class CompressingArchivePainter extends CustomPainter {
  final double compressionValue;

  CompressingArchivePainter({required this.compressionValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE91E63);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    // Основа архіву
    final rect = Rect.fromLTWH(8, 10, 64, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      outlinePaint,
    );

    // Анімовані хвилі (як показ стискання)
    for (int i = 0; i < 3; i++) {
      final waveOpacity = (1.0 - compressionValue) * (1.0 - (i * 0.3));
      paint.color = Colors.yellow.withOpacity(waveOpacity);
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        20 + (compressionValue * 30) + (i * 10),
        paint,
      );
    }

    // Блискавка (ZIP символ)
    paint.color = Colors.yellow;
    final zipPath = Path()
      ..moveTo(30, 25)
      ..lineTo(34, 29)
      ..lineTo(30, 33)
      ..lineTo(34, 37)
      ..lineTo(30, 41)
      ..lineTo(34, 45);
    canvas.drawPath(zipPath, paint);
  }

  @override
  bool shouldRepaint(CompressingArchivePainter oldDelegate) {
    return oldDelegate.compressionValue != compressionValue;
  }
}

/// Анімація розпакування архіву
class ExtractionAnimation extends StatefulWidget {
  final Duration duration;
  final int fileCount;

  const ExtractionAnimation({
    this.duration = const Duration(seconds: 2),
    this.fileCount = 3,
  });

  @override
  State<ExtractionAnimation> createState() => _ExtractionAnimationState();
}

class _ExtractionAnimationState extends State<ExtractionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Архів у центрі
          CustomPaint(
            painter: ArchiveSourcePainter(),
            size: const Size(60, 60),
          ),
          // Файли, що вилітають
          ...List.generate(
            widget.fileCount,
            (index) {
              final angle = (2 * 3.14159 / widget.fileCount) * index;
              final distance = 80 + (_controller.value * 40);
              final x = distance * Math.cos(angle);
              final y = distance * Math.sin(angle);

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(x, y),
                    child: child,
                  );
                },
                child: CustomPaint(
                  painter: ExtractionFilePainter(),
                  size: const Size(40, 50),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ArchiveSourcePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE91E63);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black87;

    final rect = Rect.fromLTWH(6, 8, 48, 44);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      outlinePaint,
    );

    // ZIP символ
    paint.color = Colors.yellow;
    final zipPath = Path()
      ..moveTo(20, 18)
      ..lineTo(23, 21)
      ..lineTo(20, 24)
      ..lineTo(23, 27)
      ..lineTo(20, 30)
      ..lineTo(23, 33)
      ..lineTo(20, 36);
    canvas.drawPath(zipPath, paint);
  }

  @override
  bool shouldRepaint(ArchiveSourcePainter oldDelegate) => false;
}

class ExtractionFilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE3F2FD);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black87;

    final rect = Rect.fromLTWH(4, 2, 32, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      outlinePaint,
    );

    // Строки тексту
    paint.color = Colors.blue;
    canvas.drawRect(Rect.fromLTWH(8, 10, 16, 2), paint);
    canvas.drawRect(Rect.fromLTWH(8, 16, 14, 2), paint);
  }

  @override
  bool shouldRepaint(ExtractionFilePainter oldDelegate) => false;
}

// Допоміжний клас для математики
class Math {
  static double cos(double angle) => math.cos(angle);
  static double sin(double angle) => math.sin(angle);
}

/// Анімація стрілок, що вказують на архів
class ArrowToArchiveAnimation extends StatefulWidget {
  final int arrowCount;
  final Duration duration;

  const ArrowToArchiveAnimation({
    this.arrowCount = 4,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<ArrowToArchiveAnimation> createState() => _ArrowToArchiveAnimationState();
}

class _ArrowToArchiveAnimationState extends State<ArrowToArchiveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Архів у центрі
          CustomPaint(
            painter: ArchiveCenterPainter(),
            size: const Size(60, 60),
          ),
          // Стрілки, що вказують на архів
          ...List.generate(
            widget.arrowCount,
            (index) {
              final angle = (2 * 3.14159 / widget.arrowCount) * index;
              final distance = 60 + (_controller.value * 20);
              final x = distance * Math.cos(angle);
              final y = distance * Math.sin(angle);

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(x, y),
                    child: Transform.rotate(
                      angle: angle + 3.14159, // Стрілка вказує на центр
                      child: child,
                    ),
                  );
                },
                child: CustomPaint(
                  painter: ArrowPainter(),
                  size: const Size(24, 24),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ArchiveCenterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE91E63);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black87;

    final rect = Rect.fromLTWH(10, 10, 40, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      outlinePaint,
    );

    // ZIP символ
    paint.color = Colors.yellow;
    final zipPath = Path()
      ..moveTo(18, 18)
      ..lineTo(21, 21)
      ..lineTo(18, 24)
      ..lineTo(21, 27)
      ..lineTo(18, 30)
      ..lineTo(21, 33);
    canvas.drawPath(zipPath, paint);
  }

  @override
  bool shouldRepaint(ArchiveCenterPainter oldDelegate) => false;
}

class ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.amber;

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black87;

    // Рисуємо стрілку
    final arrowPath = Path()
      ..moveTo(12, 6) // Вершина
      ..lineTo(16, 14) // Праве крило
      ..lineTo(12, 12) // Вер низ
      ..lineTo(8, 14) // Ліве крило
      ..close();

    canvas.drawPath(arrowPath, paint);
    canvas.drawPath(arrowPath, outlinePaint);

    // Древко стрілки
    paint.color = Colors.amber;
    canvas.drawRect(Rect.fromLTWH(10, 14, 4, 8), paint);
    outlinePaint.color = Colors.black87;
    canvas.drawRect(Rect.fromLTWH(10, 14, 4, 8), outlinePaint);
  }

  @override
  bool shouldRepaint(ArrowPainter oldDelegate) => false;
}

/// Анімація променів (промінків енергії), що вилітають з архіву
class RadialRaysAnimation extends StatefulWidget {
  final Duration duration;
  final int rayCount;

  const RadialRaysAnimation({
    this.duration = const Duration(milliseconds: 1500),
    this.rayCount = 8,
  });

  @override
  State<RadialRaysAnimation> createState() => _RadialRaysAnimationState();
}

class _RadialRaysAnimationState extends State<RadialRaysAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Архів у центрі
          CustomPaint(
            painter: ArchiveCenterPainter(),
            size: const Size(50, 50),
          ),
          // Промені
          ...List.generate(
            widget.rayCount,
            (index) {
              final angle = (2 * 3.14159 / widget.rayCount) * index;
              final distance = 10 + (_controller.value * 60);
              final x = distance * Math.cos(angle);
              final y = distance * Math.sin(angle);
              final opacity = 1.0 - _controller.value;

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(x, y),
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
                  );
                },
                child: CustomPaint(
                  painter: RayPainter(),
                  size: const Size(16, 16),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class RayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.yellow;

    // Маленька зірочка/промінь
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 3, paint);

    // Хвіст променю
    final path = Path()
      ..moveTo(size.width / 2, size.height / 2 + 3)
      ..lineTo(size.width / 2, size.height);
    canvas.drawPath(
      path,
      paint..strokeWidth = 1.5..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(RayPainter oldDelegate) => false;
}

/// Анімація поглинання файлу (файл зменшується та щезає)
class FileAbsorptionAnimation extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onComplete;

  const FileAbsorptionAnimation({
    this.duration = const Duration(milliseconds: 1000),
    this.onComplete,
  });

  @override
  State<FileAbsorptionAnimation> createState() => _FileAbsorptionAnimationState();
}

class _FileAbsorptionAnimationState extends State<FileAbsorptionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _moveAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _moveAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(0, 50))
        .animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
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
        return Transform.translate(
          offset: _moveAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: child,
            ),
          ),
        );
      },
      child: CustomPaint(
        painter: FileDisappearingPainter(),
        size: const Size(60, 72),
      ),
    );
  }
}

class FileDisappearingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE3F2FD);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black87;

    final rect = Rect.fromLTWH(6, 6, 48, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      outlinePaint,
    );

    // Строки тексту
    paint.color = Colors.blue;
    canvas.drawRect(Rect.fromLTWH(12, 18, 28, 2), paint);
    canvas.drawRect(Rect.fromLTWH(12, 26, 24, 2), paint);
    canvas.drawRect(Rect.fromLTWH(12, 34, 26, 2), paint);
  }

  @override
  bool shouldRepaint(FileDisappearingPainter oldDelegate) => false;
}
