import 'package:flutter/material.dart';

/// Контролер фону для рівнів з анімацією
class LevelBackgroundPainter extends CustomPainter {
  final int levelNumber;
  final double animationValue;

  LevelBackgroundPainter({
    this.levelNumber = 1,
    this.animationValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Базовий градієнт для кожного рівня
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _getGradientColors(levelNumber),
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Малюємо градієнт фон
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Декоративні елементи (хмари, з'їжджання, тощо)
    switch (levelNumber) {
      case 1:
        _paintLevel1Decorations(canvas, size);
      case 2:
        _paintLevel2Decorations(canvas, size);
      case 3:
        _paintLevel3Decorations(canvas, size);
      default:
        _paintLevel1Decorations(canvas, size);
    }

    // Анімація — мерехтіння огірків
    _paintAnimatedElements(canvas, size);
  }

  void _paintLevel1Decorations(Canvas canvas, Size size) {
    // Рівень 1 — простий, сонячний
    final paint = Paint()
      ..color = Colors.yellow.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Сонце
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.2), 40, paint);

    // Хмари
    paint.color = Colors.white.withOpacity(0.4);
    _drawCloud(canvas, Offset(size.width * 0.2, size.height * 0.15), paint);
    _drawCloud(canvas, Offset(size.width * 0.7, size.height * 0.3), paint);
  }

  void _paintLevel2Decorations(Canvas canvas, Size size) {
    // Рівень 2 — більш складний, бурхливих
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Більше хмар
    _drawCloud(canvas, Offset(size.width * 0.1, size.height * 0.15), paint);
    _drawCloud(canvas, Offset(size.width * 0.5, size.height * 0.25), paint);
    _drawCloud(canvas, Offset(size.width * 0.8, size.height * 0.1), paint);

    // Повітряні потоки
    paint.color = Colors.blueGrey.withOpacity(0.2);
    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.5),
      Offset(size.width * 0.25, size.height * 0.7),
      paint,
    );
  }

  void _paintLevel3Decorations(Canvas canvas, Size size) {
    // Рівень 3 — бурхливо, складна гра
    final paint = Paint()
      ..color = Colors.deepPurple.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Молнії (як намік на складність)
    paint.color = Colors.amber.withOpacity(0.3);
    _drawLightning(canvas, Offset(size.width * 0.8, size.height * 0.2), paint);
    _drawLightning(canvas, Offset(size.width * 0.2, size.height * 0.3), paint);
  }

  void _paintAnimatedElements(Canvas canvas, Size size) {
    // Пульсуючі крапки (як частинки архівації)
    final paint = Paint()
      ..color = Colors.yellow.withOpacity(0.6 + 0.4 * animationValue)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.1 + i * 0.15);
      final y = size.height * (0.7 + (animationValue % 0.3) * 0.2);
      canvas.drawCircle(Offset(x, y), 3, paint);
    }
  }

  void _drawCloud(Canvas canvas, Offset offset, Paint paint) {
    // Просто хмара з кількох кіл
    canvas.drawCircle(offset, 12, paint);
    canvas.drawCircle(Offset(offset.dx + 12, offset.dy), 12, paint);
    canvas.drawCircle(Offset(offset.dx + 24, offset.dy), 12, paint);
    canvas.drawCircle(Offset(offset.dx + 6, offset.dy - 8), 10, paint);
    canvas.drawCircle(Offset(offset.dx + 18, offset.dy - 8), 10, paint);
  }

  void _drawLightning(Canvas canvas, Offset offset, Paint paint) {
    // Просто молнія — зигзаг
    final path = Path()
      ..moveTo(offset.dx, offset.dy)
      ..lineTo(offset.dx + 4, offset.dy + 12)
      ..lineTo(offset.dx - 2, offset.dy + 16)
      ..lineTo(offset.dx + 2, offset.dy + 28)
      ..lineTo(offset.dx - 4, offset.dy + 32);

    canvas.drawPath(path, paint);
  }

  List<Color> _getGradientColors(int level) {
    switch (level) {
      case 1:
        // Поле: синій-зелений
        return [
          const Color(0xFF87CEEB),
          const Color(0xFF90EE90),
        ];
      case 2:
        // Буря: сіро-синій
        return [
          const Color(0xFF708090),
          const Color(0xFF4A90E2),
        ];
      case 3:
        // Ночь: фіолетовий-чорний
        return [
          const Color(0xFF5E35B1),
          const Color(0xFF1A1A2E),
        ];
      default:
        return [Colors.blue, Colors.green];
    }
  }

  @override
  bool shouldRepaint(LevelBackgroundPainter oldDelegate) {
    return oldDelegate.levelNumber != levelNumber ||
        oldDelegate.animationValue != animationValue;
  }
}

/// Компонент фону рівня
class LevelBackground extends StatefulWidget {
  final int levelNumber;
  final Widget child;

  const LevelBackground({
    required this.levelNumber,
    required this.child,
  });

  @override
  State<LevelBackground> createState() => _LevelBackgroundState();
}

class _LevelBackgroundState extends State<LevelBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: LevelBackgroundPainter(
            levelNumber: widget.levelNumber,
            animationValue: _controller.value,
          ),
          child: widget.child,
        );
      },
    );
  }
}
