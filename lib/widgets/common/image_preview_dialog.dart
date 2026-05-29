import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Opens a full-screen preview of [bytes] with pan/zoom support.
///
/// Tapping the dim background or the close button dismisses the dialog.
/// The image itself ignores taps so users can pan without accidental dismiss.
Future<void> showImagePreviewDialog(
  BuildContext context,
  Uint8List bytes, {
  String? name,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (ctx) => _ImagePreviewDialog(bytes: bytes, name: name),
  );
}

class _ImagePreviewDialog extends StatelessWidget {
  final Uint8List bytes;
  final String? name;

  const _ImagePreviewDialog({required this.bytes, this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Tap on dim background dismisses.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          // Centered, zoomable image. GestureDetector with empty onTap stops
          // tap propagation to the dismiss layer above (pinch/pan still work).
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                onTap: () {},
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.memory(bytes, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          if (name != null && name!.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  name!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Закрити',
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
