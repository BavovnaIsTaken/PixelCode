/// Sanitization helpers for the device-name portion of the client handshake.
library;

import 'dart:io';

/// Returns a human-friendly device name derived from [Platform.localHostname].
///
/// Strips the `.local` mDNS suffix (common on macOS/iOS) and replaces the
/// meaningless `localhost` (returned by some iOS simulator/device configurations)
/// with a platform-appropriate fallback.
String sanitizeDeviceName(String raw, String platform) {
  var name = raw.trim();
  if (name.toLowerCase().endsWith('.local')) {
    name = name.substring(0, name.length - '.local'.length);
  }
  if (name.isEmpty || name.toLowerCase() == 'localhost') {
    return switch (platform) {
      'ios' => 'iPhone',
      'android' => 'Android',
      'macos' => 'Mac',
      'linux' => 'Linux',
      'windows' => 'Windows',
      _ => 'Device',
    };
  }
  return name;
}

String currentPlatformName() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  return 'unknown';
}
