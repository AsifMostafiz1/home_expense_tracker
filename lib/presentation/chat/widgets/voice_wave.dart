import 'package:flutter/material.dart';

/// The bars a voice message is drawn as.
///
/// One bar per reading taken while it was being spoken, tall where it was
/// loud. Everything left of [progress] is painted in the played colour, so
/// the same widget serves the bubble that is playing and the fifty that are
/// not.
///
/// A picture of the sound rather than a progress bar with decoration: it is
/// what makes a voice message something you can aim at — the pause before the
/// point, the bit where two people talk at once — instead of a grey pill with
/// a length on it.
class VoiceWave extends StatelessWidget {
  /// Loudness over time, 0–100. Empty draws a flat line, which is what a
  /// message sent before the shape was recorded honestly knows.
  final List<int> levels;

  /// How far through, 0–1.
  final double progress;

  final Color played;
  final Color unplayed;

  final double barWidth;
  final double gap;

  const VoiceWave({
    super.key,
    required this.levels,
    required this.played,
    required this.unplayed,
    this.progress = 0,
    this.barWidth = 3,
    this.gap = 2,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(
        levels: levels,
        progress: progress.clamp(0, 1).toDouble(),
        played: played,
        unplayed: unplayed,
        barWidth: barWidth,
        gap: gap,
      ),
      size: Size.infinite,
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<int> levels;
  final double progress;
  final Color played;
  final Color unplayed;
  final double barWidth;
  final double gap;

  const _WavePainter({
    required this.levels,
    required this.progress,
    required this.played,
    required this.unplayed,
    required this.barWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double step = barWidth + gap;
    final int slots = (size.width / step).floor();
    if (slots <= 0) return;

    final Paint brush = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    // The width decides how many bars there is room for; the recording
    // decides what they say. Whatever was stored is stretched or squeezed
    // onto the slots there are, so the same message is the same shape in a
    // narrow bubble and a wide one.
    final double mid = size.height / 2;
    final double playedUpTo = size.width * progress;

    for (int i = 0; i < slots; i++) {
      final double x = i * step + barWidth / 2;
      final int level = levels.isEmpty
          ? 12
          : levels[(i * levels.length ~/ slots).clamp(0, levels.length - 1)];

      // A floor of a couple of pixels: silence is still part of the message,
      // and a gap in the middle of the bars reads as a bug.
      final double half =
          (level / 100 * (size.height / 2 - 1)).clamp(1.5, size.height / 2);

      brush.color = x <= playedUpTo ? played : unplayed;
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), brush);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.played != played ||
      old.unplayed != unplayed ||
      !identical(old.levels, levels) ||
      old.levels.length != levels.length;
}
