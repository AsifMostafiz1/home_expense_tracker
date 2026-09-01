import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The three dots that say a message is on its way.
///
/// Drawn as an incoming bubble at the bottom of the thread — the place the
/// next message will land — so it reads as something arriving rather than as
/// a status line bolted to the screen. The header says who; this says that
/// something is coming, which is the part worth animating.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  /// One controller for all three dots. They run the same wave a beat apart
  /// rather than three animations that would have to be kept in step.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  /// How far behind the previous dot each one runs, as a fraction of the
  /// cycle. Small enough that the three read as one movement.
  static const double _lag = 0.16;

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      // Matches the gap a message bubble leaves under itself, and keeps the
      // dots off the right-hand half of the screen the way an incoming
      // message is kept.
      padding: const EdgeInsets.only(top: 2, bottom: 6, right: 50),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            // The incoming bubble's own background — see `_MessageBubble`.
            color: dark
                ? Theme.of(context).cardColor
                : Colors.black.withOpacity(0.05),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                _dot(i),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(int index) {
    final Color color = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _wave,
      builder: (BuildContext context, Widget? child) {
        final double phase = (_wave.value + index * _lag) % 1.0;
        // 0 at the bottom of the cycle, 1 at the top — a smooth rise and
        // fall rather than a blink.
        final double lift = (math.sin(phase * 2 * math.pi) + 1) / 2;

        return Transform.translate(
          offset: Offset(0, -3 * lift),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color.withOpacity(0.3 + 0.55 * lift),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
