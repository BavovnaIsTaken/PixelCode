import 'package:flutter/material.dart';

import '../../models/agent_message.dart';

/// Left-border width for categorised message containers.
const double _kBorderWidth = 3.0;

/// Returns a [BoxDecoration] that overrides the standard bubble border when the
/// message has a non-null [category]. Returns null for regular messages so the
/// caller can fall back to the default decoration unchanged.
BoxDecoration? categoryBubbleDecoration(MessageCategory? category) {
  return switch (category) {
    // Non-uniform borders are only invalid when combined with borderRadius.
    // These decorations intentionally omit borderRadius so Flutter's renderer
    // can handle the left accent without a uniform-color constraint.
    MessageCategory.awaitingReply => BoxDecoration(
        color: const Color(0xFF00C0D1).withValues(alpha: 0.06),
        border: Border(
          left: const BorderSide(color: Color(0xFF00C0D1), width: _kBorderWidth),
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
    MessageCategory.status => BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 2),
        ),
      ),
    _ => null,
  };
}

/// Returns an overriding [TextStyle] for the message body when the category
/// warrants it (e.g. status messages use small monospace).
TextStyle? categoryTextStyle(MessageCategory? category) {
  return switch (category) {
    MessageCategory.status => TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontFamily: 'monospace',
        height: 1.4,
      ),
    _ => null,
  };
}
