import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ClipboardService {
  static const _channel = MethodChannel('com.pixelcode/clipboard');

  /// Returns PNG bytes of the image currently in the clipboard,
  /// or null if the clipboard contains no image.
  static Future<Uint8List?> getImageFromClipboard() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('getImageFromClipboard');
      return result;
    } catch (e) {
      debugPrint('Clipboard error: $e');
      return null;
    }
  }
}
