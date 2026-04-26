import 'package:flutter/material.dart';

/// Rendered in place of a standard chat bubble when a [ChatMessage] has
/// [MessageCategory.taskLinked]. Displays a compact board-task-added row.
class BoardAddedBubble extends StatelessWidget {
  /// Title of the task that was added to the backlog.
  final String title;

  /// Optional callback fired when the user taps "Переглянути".
  final VoidCallback? onView;

  const BoardAddedBubble({super.key, required this.title, this.onView});

  @override
  Widget build(BuildContext context) {
    const stickyYellow = Color(0xFFFFC107);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: stickyYellow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: stickyYellow.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: stickyYellow.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Додано в беклог: "$title"',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onView != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onView,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Переглянути',
                    style: TextStyle(
                      color: stickyYellow.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
