import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Today's share of tasks finished, as a ring.
///
/// Drawn rather than borrowed from `CircularProgressIndicator` because the
/// arc has to start at the top, end with round caps, and animate from where
/// it was to where it is now — a completion should visibly move the ring, not
/// swap one static picture for another. The label sits inside, whatever the
/// caller wants said there.
class TaskProgressRing extends StatelessWidget {
  /// 0..1.
  final double value;
  final double size;
  final double stroke;
  final Color track;
  final Color arc;
  final Widget? child;

  const TaskProgressRing({
    super.key,
    required this.value,
    required this.track,
    required this.arc,
    this.size = 60,
    this.stroke = 6,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: t,
              stroke: stroke,
              track: track,
              arc: arc,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color track;
  final Color arc;

  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.arc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect inner = rect.deflate(stroke / 2);

    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(inner, trackPaint);

    if (progress <= 0) return;

    final Paint arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // From twelve o'clock, clockwise.
    canvas.drawArc(inner, -math.pi / 2, 2 * math.pi * progress, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.track != track ||
      old.arc != arc;
}
