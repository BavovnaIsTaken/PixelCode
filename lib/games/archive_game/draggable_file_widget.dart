// Draggable File Widget — interactive file tile with drag-and-drop support

import 'package:flutter/material.dart';
import '../../models/archive_crush/archive_file.dart';

class DraggableFileWidget extends StatefulWidget {
  final ArchiveFile file;
  final VoidCallback onDragStart;
  final Function(Offset delta) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDroppedInArchive;

  const DraggableFileWidget({
    super.key,
    required this.file,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDroppedInArchive,
  });

  @override
  State<DraggableFileWidget> createState() => _DraggableFileWidgetState();
}

class _DraggableFileWidgetState extends State<DraggableFileWidget>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  Offset _dragStart = Offset.zero;
  Offset _currentDragOffset = Offset.zero;
  late AnimationController _hoverController;
  bool _isOverArchive = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _isDragging = true;
      _dragStart = event.position;
      _currentDragOffset = Offset.zero;
    });
    widget.onDragStart();
    _hoverController.forward();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDragging) return;

    final delta = event.position - _dragStart;
    final newDragOffset = Offset(
      _currentDragOffset.dx + (event.position.dx - _dragStart.dx),
      _currentDragOffset.dy + (event.position.dy - _dragStart.dy),
    );

    setState(() {
      _currentDragOffset = newDragOffset;
    });

    widget.onDragUpdate(delta);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDragging) return;

    setState(() {
      _isDragging = false;
      _currentDragOffset = Offset.zero;
    });
    widget.onDragEnd();
    _hoverController.reverse();

    // Check if dropped in archive box (rough detection)
    if (_isInArchiveZone(event.position)) {
      widget.onDroppedInArchive();
    }
  }

  bool _isInArchiveZone(Offset position) {
    // Archive box is at bottom (220-370 px vertically, 20-340 px horizontally)
    const archiveTop = 220.0;
    const archiveBottom = 370.0;
    const archiveLeft = 20.0;
    const archiveRight = 340.0;

    return position.dy >= archiveTop &&
        position.dy <= archiveBottom &&
        position.dx >= archiveLeft &&
        position.dx <= archiveRight;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: MouseRegion(
        onEnter: (_) {
          if (_isDragging) {
            setState(() => _isOverArchive = true);
          }
        },
        onExit: (_) {
          setState(() => _isOverArchive = false);
        },
        child: AnimatedBuilder(
          animation: _hoverController,
          builder: (context, child) {
            final scale = 1.0 + (_hoverController.value * 0.2);
            final elevation = _hoverController.value * 8;

            return Transform.scale(
              scale: scale,
              child: Container(
                decoration: BoxDecoration(
                  color: _getFileColor(widget.file.fileType),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3 + elevation / 80),
                      blurRadius: 8 + elevation,
                      offset: Offset(0, 2 + elevation / 4),
                    ),
                  ],
                  border: Border.all(
                    color: _isOverArchive
                        ? Colors.green[700]!
                        : Colors.black26,
                    width: _isOverArchive ? 3 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getFileIcon(widget.file.fileType),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 60,
                      child: Text(
                        widget.file.name,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          overflow: TextOverflow.ellipsis,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatFileSize(widget.file.originalSize),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getFileColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'jpg':
      case 'png':
      case 'gif':
        return Colors.purple[200]!;
      case 'pdf':
        return Colors.red[200]!;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Colors.indigo[200]!;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.cyan[200]!;
      case 'zip':
      case 'rar':
      case 'tar':
        return Colors.orange[200]!;
      case 'txt':
      case 'csv':
      case 'json':
        return Colors.green[200]!;
      case 'db':
      case 'sql':
        return Colors.teal[200]!;
      case 'pptx':
      case 'docx':
      case 'xlsx':
        return Colors.blue[200]!;
      default:
        return Colors.grey[200]!;
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
