// Archive Game Painter — renders game canvas, archive box, and animations

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/archive_crush/archive_level.dart';
import '../../models/archive_crush/archive_file.dart';
import '../../models/archive_crush/compression_animation.dart';

class ArchiveGamePainter extends CustomPainter {
  final List<ArchiveFile> files;
  final Map<String, Offset> filePositions;
  final List<CompressionAnimation> animations;
  final ArchiveLevel level;

  ArchiveGamePainter({
    required this.files,
    required this.filePositions,
    required this.animations,
    required this.level,
  });

  static const double archiveBoxTop = 220;
  static const double archiveBoxHeight = 150;
  static const double archiveBoxLeft = 20;
  static const double archiveBoxRight = 340;
  static const double archiveBoxWidth = archiveBoxRight - archiveBoxLeft;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background gradient
    _drawBackground(canvas, size);

    // Draw archive box (drop zone)
    _drawArchiveBox(canvas, size);

    // Draw files inside archive with compression animations
    _drawFilesInArchive(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.blue[50]!,
        Colors.blue[100]!,
      ],
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      ),
    );

    // Draw grid pattern for visual interest
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;

    const gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, archiveBoxTop),
        gridPaint,
      );
    }
    for (double y = 0; y < archiveBoxTop; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
  }

  void _drawArchiveBox(Canvas canvas, Size size) {
    final boxRect = Rect.fromLTWH(
      archiveBoxLeft,
      archiveBoxTop,
      archiveBoxWidth,
      archiveBoxHeight,
    );

    // Box background
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(12)),
      Paint()
        ..color = Colors.amber[100]!
        ..style = PaintingStyle.fill,
    );

    // Box border
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(12)),
      Paint()
        ..color = Colors.amber[700]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Top label
    const labelPaint = TextPainter(
      text: TextSpan(
        text: '📦 Archive Box',
        style: TextStyle(
          color: Colors.amber,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPaint.layout();
    labelPaint.paint(
      canvas,
      Offset(
        archiveBoxLeft + 12,
        archiveBoxTop - 22,
      ),
    );

    // Dashed lines showing drop zone
    _drawDashedBorder(canvas, boxRect, Colors.amber[800]!);
  }

  void _drawDashedBorder(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashWidth = 8.0;
    const dashSpace = 4.0;
    const spacing = dashWidth + dashSpace;

    // Top
    for (double x = rect.left; x < rect.right; x += spacing) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset((x + dashWidth).clamp(0, rect.right), rect.top),
        paint,
      );
    }

    // Bottom
    for (double x = rect.left; x < rect.right; x += spacing) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset((x + dashWidth).clamp(0, rect.right), rect.bottom),
        paint,
      );
    }

    // Left
    for (double y = rect.top; y < rect.bottom; y += spacing) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.left, (y + dashWidth).clamp(0, rect.bottom)),
        paint,
      );
    }

    // Right
    for (double y = rect.top; y < rect.bottom; y += spacing) {
      canvas.drawLine(
        Offset(rect.right, y),
        Offset(rect.right, (y + dashWidth).clamp(0, rect.bottom)),
        paint,
      );
    }
  }

  void _drawFilesInArchive(Canvas canvas, Size size) {
    final boxRect = Rect.fromLTWH(
      archiveBoxLeft,
      archiveBoxTop,
      archiveBoxWidth,
      archiveBoxHeight,
    );

    // Draw files with compression animation
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final anim = animations.asMap().entries
          .firstWhere(
            (e) => e.value.fileId == file.name,
            orElse: () => MapEntry(-1, CompressionAnimation(fileId: file.name)),
          )
          .value;

      _drawCompressedFile(
        canvas,
        file,
        anim,
        boxRect,
        i,
        files.length,
      );
    }

    // Draw count indicator
    if (files.isNotEmpty) {
      final countText = TextPainter(
        text: TextSpan(
          text: '${files.length} files archived',
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      countText.layout();
      countText.paint(
        canvas,
        Offset(
          boxRect.center.dx - countText.width / 2,
          boxRect.center.dy + 20,
        ),
      );
    }
  }

  void _drawCompressedFile(
    Canvas canvas,
    ArchiveFile file,
    CompressionAnimation anim,
    Rect boxRect,
    int index,
    int totalFiles,
  ) {
    // Position files in grid inside box
    final cols = 3;
    final rows = (totalFiles / cols).ceil();
    final cellWidth = boxRect.width / cols;
    final cellHeight = boxRect.height / rows;

    final col = index % cols;
    final row = (index / cols).floor();

    double x = boxRect.left + col * cellWidth + cellWidth / 2;
    double y = boxRect.top + row * cellHeight + cellHeight / 2;

    // Apply animation transform if compressing
    if (anim.isCompressing) {
      x += anim.offsetX;
      y += anim.offsetY;
    }

    // Draw file icon/rect
    final fileSize = 24.0 * anim.scaleX;
    final fileRect = Rect.fromCenter(
      center: Offset(x, y),
      width: fileSize,
      height: fileSize * anim.scaleY,
    );

    // Save canvas state for rotation
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(anim.rotationAngle);
    canvas.translate(-x, -y);

    // File background
    canvas.drawRRect(
      RRect.fromRectAndRadius(fileRect, const Radius.circular(4)),
      Paint()
        ..color = _getFileColor(file.fileType).withOpacity(
          anim.opacity,
        )
        ..style = PaintingStyle.fill,
    );

    // File icon text
    final iconText = TextPainter(
      text: TextSpan(
        text: _getFileIcon(file.fileType),
        style: const TextStyle(fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    iconText.layout();
    iconText.paint(
      canvas,
      Offset(
        x - iconText.width / 2,
        y - iconText.height / 2,
      ),
    );

    canvas.restore();

    // Draw compression progress bar below file
    if (anim.isCompressing) {
      final progressBarWidth = 30.0;
      final progressBarRect = Rect.fromLTWH(
        x - progressBarWidth / 2,
        y + fileSize / 2 + 8,
        progressBarWidth,
        3,
      );

      canvas.drawRect(
        progressBarRect,
        Paint()..color = Colors.grey[400]!,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          x - progressBarWidth / 2,
          y + fileSize / 2 + 8,
          progressBarWidth * anim.compressionProgress,
          3,
        ),
        Paint()..color = Colors.green,
      );
    }
  }

  Color _getFileColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'jpg':
      case 'png':
      case 'gif':
        return Colors.purple[300]!;
      case 'pdf':
        return Colors.red[300]!;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Colors.indigo[300]!;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.cyan[300]!;
      case 'zip':
      case 'rar':
      case 'tar':
        return Colors.orange[300]!;
      case 'txt':
      case 'csv':
      case 'json':
        return Colors.green[300]!;
      case 'db':
      case 'sql':
        return Colors.teal[300]!;
      case 'pptx':
      case 'docx':
      case 'xlsx':
        return Colors.blue[300]!;
      default:
        return Colors.grey[300]!;
    }
  }

  String _getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'jpg':
      case 'png':
      case 'gif':
        return '🖼️';
      case 'pdf':
        return '📄';
      case 'mp4':
      case 'mov':
      case 'avi':
        return '🎬';
      case 'mp3':
      case 'wav':
      case 'flac':
        return '🎵';
      case 'zip':
      case 'rar':
      case 'tar':
        return '📦';
      case 'txt':
      case 'csv':
      case 'json':
        return '📝';
      case 'db':
      case 'sql':
        return '🗄️';
      case 'pptx':
        return '📊';
      case 'docx':
        return '📋';
      case 'xlsx':
        return '📈';
      default:
        return '📁';
    }
  }

  @override
  bool shouldRepaint(ArchiveGamePainter oldDelegate) {
    return oldDelegate.files != files ||
        oldDelegate.filePositions != filePositions ||
        oldDelegate.animations != animations;
  }
}
