import 'package:flutter/material.dart';

import '../../utils/app_ui.dart';

/// ---------------------------------------------------------------------------
/// Shimmer placeholders.
///
/// A band of light dragged across the placeholder shapes, rather than the
/// whole block fading in and out: the sweep reads as "content is on its way",
/// where a pulse reads as "something here is blinking at me".
///
/// One [Shimmer] wraps a whole skeleton — the gradient is measured against
/// that subtree, so every shape in it is lit by the same pass rather than each
/// box running its own little animation.
/// ---------------------------------------------------------------------------

Color _shimmerBase(BuildContext context) =>
    AppUi.isDark(context) ? const Color(0xFF2C2C2C) : const Color(0xFFEDEDF1);

Color _shimmerHighlight(BuildContext context) =>
    AppUi.isDark(context) ? const Color(0xFF3D3D3D) : const Color(0xFFF9F9FC);

class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  // Bounds run past 0..1 on both sides so the band enters from off-screen and
  // leaves the same way, instead of appearing and dying mid-surface.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: -0.7,
    upperBound: 1.7,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = _shimmerBase(context);
    final Color highlight = _shimmerHighlight(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          // srcATop paints the gradient onto whatever the skeleton drew, so
          // the shapes decide the silhouette and the gradient decides colour.
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
            tileMode: TileMode.clamp,
            transform: _SlidingGradient(_controller.value),
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradient extends GradientTransform {
  final double slide;

  const _SlidingGradient(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}

/// One placeholder shape. Solid on its own, lit when it sits inside a
/// [Shimmer].
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const ShimmerBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 10,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: _shimmerBase(context),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}
