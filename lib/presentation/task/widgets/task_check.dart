import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The round box a task is ticked in.
///
/// One control for every row in the feature — the list, the day's sheet, the
/// finished view — so ticking feels the same wherever it is done. The ring is
/// drawn in the task's own accent, fills on a tap and grows a tick that
/// overshoots a little before settling, with a light tap under the finger:
/// finishing something should feel like something.
class TaskCheck extends StatelessWidget {
  final bool done;
  final Color accent;
  final VoidCallback onTap;
  final double size;

  const TaskCheck({
    super.key,
    required this.done,
    required this.accent,
    required this.onTap,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        // A generous target around a small ring: the row's own tap opens the
        // editor, so the tick has to be easy to land on without hitting that.
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? accent : Colors.transparent,
              border: Border.all(
                color: done ? accent : accent.withOpacity(0.7),
                width: 2,
              ),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              scale: done ? 1 : 0,
              child: Icon(
                Icons.check_rounded,
                size: size * 0.62,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
