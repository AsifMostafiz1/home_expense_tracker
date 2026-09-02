import 'package:flutter/material.dart';

/// The colours the MessBook launcher icon is cut from.
///
/// They live here rather than in [AppTheme] on purpose: these are the icon's
/// own palette, fixed across light and dark, while the theme's colours answer
/// to the surface they sit on.
class MessBookBrand {
  const MessBookBrand._();

  /// The icon's background gradient, running top-left to bottom-right.
  static const Color gradientStart = Color(0xFF5B4BF0);
  static const Color gradientEnd = Color(0xFF7C3AED);
  static const List<Color> gradient = [gradientStart, gradientEnd];

  /// The book, and the plate's centre.
  static const Color cream = Color(0xFFFDFBF6);

  /// The plate's rim.
  static const Color deep = Color(0xFF4338CA);

  /// The spine: [deep] at 70%, resolved here so the paint stays const.
  static const Color spine = Color(0xB34338CA);

  /// Corner radius as a fraction of the icon's width — 24 of the 100-unit
  /// design canvas. Anything showing the mark on a tile should use this, so
  /// the tile is the same shape as the icon on the launcher.
  static const double cornerRatio = 0.24;
}

/// The MessBook mark — book, spine and plate — drawn rather than shipped as an
/// image, so it stays sharp at any size and cannot drift out of step with the
/// launcher icon.
///
/// This paints the foreground only. Put it on the brand gradient (see
/// [MessBookBrand.gradient]) to get the icon as the launcher shows it.
class MessBookGlyph extends StatelessWidget {
  const MessBookGlyph({super.key, this.size});

  /// Side of the square the mark is drawn into. Null fills the parent.
  final double? size;

  @override
  Widget build(BuildContext context) {
    const Widget paint = CustomPaint(
      painter: _MessBookGlyphPainter(),
      isComplex: false,
      willChange: false,
    );
    return size == null
        ? paint
        : SizedBox.square(dimension: size, child: paint);
  }
}

/// Every coordinate below is on the 100x100 design canvas the launcher and
/// iOS icons are generated from, so the proportions here and there are one
/// set of numbers rather than two that have to be kept in agreement.
class _MessBookGlyphPainter extends CustomPainter {
  const _MessBookGlyphPainter();

  static const Rect _book = Rect.fromLTWH(27, 23, 46, 54);
  static const Rect _spine = Rect.fromLTWH(31.5, 28, 3, 44);
  static const Offset _plate = Offset(55, 50);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / 100.0;

    canvas.save();
    // Centre the square canvas in whatever box we were handed.
    canvas.translate((size.width - 100 * scale) / 2,
        (size.height - 100 * scale) / 2);
    canvas.scale(scale);

    final Paint cream = Paint()..color = MessBookBrand.cream;
    canvas.drawRRect(
      RRect.fromRectAndRadius(_book, const Radius.circular(7)),
      cream,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(_spine, const Radius.circular(1.5)),
      Paint()..color = MessBookBrand.spine,
    );
    canvas.drawCircle(_plate, 14, Paint()..color = MessBookBrand.deep);
    canvas.drawCircle(_plate, 7, cream);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MessBookGlyphPainter oldDelegate) => false;
}
