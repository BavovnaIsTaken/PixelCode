/// Session handoff is fully automatic — this widget intentionally renders nothing.
library;

import 'package:flutter/widgets.dart';

/// Always returns a zero-size Positioned so the parent Stack never has a bare
/// non-positioned child, which would collapse the Stack to 0×0 under loose
/// cross-axis constraints (Column → Expanded → Stack).
class SessionBanner extends StatelessWidget {
  const SessionBanner({super.key});

  @override
  Widget build(BuildContext context) => const Positioned(
        left: 0,
        top: 0,
        child: SizedBox.shrink(),
      );
}
