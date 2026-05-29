/// Shared modal-bottom-sheet helper for PixelCode.
///
/// Wraps `showModalBottomSheet` + `DraggableScrollableSheet` with project
/// conventions so callers never re-implement scrim, drag handle, theme
/// colours or side margins. Three legacy sheets used to do this each in
/// their own way (`showAgentDetailDrawer`, `roster_tab::_showMemories`,
/// `ActivityOverlaySheet`) — all three now go through here.
library;

import 'package:flutter/material.dart';

import '../../models/app_theme.dart';

/// Signature for the sheet body. Receives the scroll controller that
/// `DraggableScrollableSheet` provides so the body's scrollable view can
/// hand-off drag-from-content to the sheet's resize gesture seamlessly.
typedef AppSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController scrollController,
);

/// Opens a theme-aware draggable bottom sheet.
///
/// * `initialSize` / `minSize` / `maxSize` are fractions of screen height.
/// * `maxWidth` caps the sheet's width on wide viewports — wider screens get
///   side margins instead of an ocean-wide sheet. Mobile width (< maxWidth)
///   is always full-width. Pass `null` for full-width on every platform.
/// * `showDragHandle` renders the standard pill above the body. Disable it
///   only when the body already has its own header drag affordance.
/// * `showCloseButton` renders a 24×24 close (✕) affordance in the top-right
///   corner. Off by default so callers that have their own close action in
///   the body header (e.g. `AgentDetailDrawer`) don't double up.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required AppSheetBuilder builder,
  double initialSize = 0.6,
  double minSize = 0.35,
  double maxSize = 0.92,
  double? maxWidth = 720,
  bool showDragHandle = true,
  bool showCloseButton = false,
}) {
  final width = MediaQuery.of(context).size.width;
  final useMaxWidth = maxWidth != null && width > maxWidth;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Transparent so we paint the surface ourselves with theme colours —
    // the default Material 3 background here is hardcoded and would defeat
    // [ThemeColors.surface] for premium / seasonal themes.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    constraints: useMaxWidth
        ? BoxConstraints(maxWidth: maxWidth)
        : null,
    builder: (sheetContext) {
      final tc = sheetContext.appColors;
      return DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: minSize,
        maxChildSize: maxSize,
        expand: false,
        snap: true,
        builder: (ctx, scrollController) => Container(
          decoration: BoxDecoration(
            color: tc.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            border: Border(
              top: BorderSide(color: tc.divider),
              left: BorderSide(color: tc.divider),
              right: BorderSide(color: tc.divider),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          // Stack so the close-✕ can float in the top-right corner without
          // forcing the body to reserve a header row.
          child: Stack(
            children: [
              Column(
                children: [
                  if (showDragHandle)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tc.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Expanded(child: builder(ctx, scrollController)),
                ],
              ),
              if (showCloseButton)
                Positioned(
                  top: 4,
                  right: 8,
                  child: _CloseButton(color: tc.textMedium),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Subtle ✕ in the top-right of a sheet. Hover brightens it from
/// [ThemeColors.textMedium] toward white so it's still discoverable but
/// doesn't compete with the body content at rest.
class _CloseButton extends StatefulWidget {
  final Color color;
  const _CloseButton({required this.color});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Tooltip(
          message: 'Закрити',
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: Color.lerp(
                widget.color,
                Colors.white,
                _hovered ? 0.6 : 0.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
