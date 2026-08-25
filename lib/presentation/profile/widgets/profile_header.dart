import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/profile_avatar.dart';

/// The profile page's top section: one identity — avatar, name, number — that
/// travels from the middle of an open header into the toolbar as the page is
/// scrolled, with the three running figures following it up and coming to
/// rest as a strip along the bottom of the bar.
///
/// Nothing here is given up on the way. The figures are the reason to open
/// this page, so they stay on it: three cards while there is room for them,
/// three small ones once the bar has closed, and the same three numbers
/// throughout.
///
/// It is one moving element, not two that swap over. A cross-fade between a
/// large block and a compact bar has a moment in the middle where both are
/// half there and neither is anywhere in particular; here every position, size
/// and weight is read off [offset], so any point in the scroll is a real frame
/// of the same motion and the eye can follow the avatar all the way up.
///
/// The whole thing is absolutely placed rather than laid out in a column,
/// because a [SliverAppBar] hands its flexible space a box that shrinks a
/// pixel at a time and each piece has to move at its own rate inside it.
///
/// Two rates, in fact, and which is which is what keeps the header from
/// running into itself:
///
///  * The name and number rise at exactly the scroll's rate. The cards below
///    rise a little slower, having less far to go, so the gap between the two
///    can only open — they can never catch the name up.
///  * The avatar shrinks and slides into the corner on a shorter schedule, so
///    it is out of the text's way well before the two come level and sit down
///    side by side.
class ProfileHeader extends StatelessWidget {
  /// How far the page has been scrolled, in pixels, from nothing to the whole
  /// of [heightFor] — the header is placed from the reader's own measure
  /// rather than a fraction, since what must not collide is measured in
  /// pixels too.
  final double offset;

  /// The status bar inset. The header fills the bar, notch included, so every
  /// vertical figure below is measured from the very top of the screen.
  final double topPadding;

  final String name;
  final String phone;
  final String? imageUrl;
  final bool isAdmin;

  final String mealCount;
  final String mealPaid;
  final String otherPaid;

  const ProfileHeader({
    super.key,
    required this.offset,
    required this.topPadding,
    required this.name,
    required this.phone,
    required this.imageUrl,
    required this.isAdmin,
    required this.mealCount,
    required this.mealPaid,
    required this.otherPaid,
  });

  static const double hPad = 20;

  /// What separates the stat cards from the first section below. The list adds
  /// no top padding of its own, so this one figure covers the whole gap.
  static const double gapBelow = 32;

  /// A toolbar cannot grow, so the reader's setting is capped here. It still
  /// moves the open header, which carries the same name at full size.
  static const double maxTextScale = 1.3;

  static const double _avatarOpen = 100;
  static const double _avatarDocked = 36;
  static const double _gapTop = 4;
  static const double _gapAvatarName = 16;
  static const double _gapNamePhone = 4;
  static const double _gapPhoneStats = 28;
  static const double _gapAvatarText = 12;

  /// How much of the identity's climb the avatar takes to finish its own move
  /// out of the way. Short enough that it is standing in the corner at its
  /// docked size while the name is still on its way up, which is what leaves
  /// the two clear of one another the whole time.
  static const double _avatarShare = 0.45;

  static const double _nameOpen = 22;
  static const double _nameDocked = 17;
  static const double _phoneOpen = 14;
  static const double _phoneDocked = 11.5;
  static const double _statValue = 20;
  static const double _statLabel = 12;
  static const double _statPadV = 20;
  static const double _statGap = 12;
  static const double _statValueDocked = 16;
  static const double _statLabelDocked = 10.5;
  static const double _statPadVDocked = 5;
  static const double _statGapDocked = 8;

  /// What the bar keeps below the toolbar once it has closed: a little air,
  /// the strip of figures, and enough of a gap that the first section of the
  /// list does not sit against it.
  static const double _stripGapAbove = 8;
  static const double _stripGapBelow = 8;

  /// A line of text at [fontSize], at a generous multiple of it: Bengali sits
  /// taller in the line than Latin does, and a few spare pixels under the stat
  /// cards cost nothing while a few short of them clips the cards.
  static double _line(double fontSize, double s) => fontSize * 1.35 * s;

  static double _clampScale(double textScale) =>
      math.min(textScale, maxTextScale);

  static double _nameBlock(double s) =>
      _line(_nameOpen, s) + _gapNamePhone + _line(_phoneOpen, s);

  static double _statsHeight(double s) =>
      _statPadV * 2 + _line(_statValue, s) + 4 + _line(_statLabel, s);

  static double _stripHeight(double s) =>
      _statPadVDocked * 2 +
      _line(_statValueDocked, s) +
      2 +
      _line(_statLabelDocked, s);

  /// Where the stat cards sit when the header is open, measured from the
  /// bottom of the toolbar.
  static double _statsTop(double s) =>
      _gapTop + _avatarOpen + _gapAvatarName + _nameBlock(s) + _gapPhoneStats;

  /// The stacked name and number at their docked size.
  static double _dockedTextHeight(double s) =>
      _line(_nameDocked, s) + _gapNamePhone + _line(_phoneDocked, s);

  /// How far the page has to scroll for the identity to finish docking — the
  /// climb the name makes, which it makes at the scroll's own rate.
  ///
  /// The status bar drops out of it: both ends of the climb sit below it.
  static double dockDistance(double textScale) {
    final double s = _clampScale(textScale);
    return (kToolbarHeight + _gapTop + _avatarOpen + _gapAvatarName) -
        (kToolbarHeight - _dockedTextHeight(s)) / 2;
  }

  /// The header's height below the toolbar at a given font scale — what the
  /// bar has to give up as it collapses.
  ///
  /// Derived from the same figures the layout uses, so the two cannot drift
  /// apart and leave the stat cards clipped against the bar's edge.
  static double heightFor(double textScale) {
    final double s = _clampScale(textScale);
    return _statsTop(s) + _statsHeight(s) + gapBelow;
  }

  /// What the bar keeps below the toolbar once it has closed — the strip of
  /// figures and the air around it.
  static double collapsedFor(double textScale) {
    final double s = _clampScale(textScale);
    return _stripGapAbove + _stripHeight(s) + _stripGapBelow;
  }

  /// The scroll the header answers to: what it gives up between open and
  /// closed. Past it the page scrolls on and the bar stays as it is.
  static double travelFor(double textScale) =>
      heightFor(textScale) - collapsedFor(textScale);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double s =
        _clampScale(MediaQuery.textScalerOf(context).scale(100) / 100);
    final double travel = travelFor(s);
    final double dock = dockDistance(s);
    final double scrolled = offset.clamp(0.0, travel);

    // The cards' own progress. They have less ground to cover than the name
    // does and take the whole scroll to cover it, so they rise a touch slower
    // than the page — which is what keeps them off the name's heels.
    final double q = travel <= 0 ? 1 : (scrolled / travel).clamp(0.0, 1.0);

    // How far the identity has got. The name climbs at the scroll's own rate,
    // so this is simply how much of its climb is behind it.
    final double p = (scrolled / dock).clamp(0.0, 1.0);

    // The avatar's own progress, finished well before the name's. Eased at
    // both ends so it leaves the middle of the page and arrives in the corner
    // without a corner of its own to turn.
    final double m =
        Curves.easeInOut.transform((p / _avatarShare).clamp(0.0, 1.0));

    final double blockTop = topPadding + kToolbarHeight;
    final double toolbarMid = topPadding + kToolbarHeight / 2;

    // Up on the name's schedule, out of its way on the avatar's: by the time
    // the two are level the avatar is a small circle in the corner and the
    // name has already stepped to the right of it.
    final double avatarTop =
        lerpDouble(blockTop + _gapTop, toolbarMid - _avatarDocked / 2, p)!;
    final double avatarScale = lerpDouble(1, _avatarDocked / _avatarOpen, m)!;

    final double textTop = lerpDouble(
      blockTop + _gapTop + _avatarOpen + _gapAvatarName,
      toolbarMid - _dockedTextHeight(s) / 2,
      p,
    )!;
    final double textLeft =
        lerpDouble(hPad, hPad + _avatarDocked + _gapAvatarText, m)!;

    // Centred while open, flush left once docked — an alignment rather than an
    // offset, so it holds for a name of any width.
    final Alignment lineAlign = Alignment(lerpDouble(0, -1, m)!, 0);

    // The page title goes early: the identity crosses that spot on its way up,
    // and two labels in one place read as a mistake.
    final double titleOpacity = (1 - m / 0.5).clamp(0.0, 1.0);
    // Only in the last of the collapse: any earlier and the line would be
    // drawn across the middle of the page.
    final double edgeOpacity =
        ((scrolled - (travel - 24)) / 24).clamp(0.0, 1.0);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      // The bar's box is the whole of it — anything reaching past the bottom
      // edge on its way out has to be cut off there.
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Up behind the identity and no further: the strip comes to
                // rest just under the toolbar and stays there for the whole of
                // the page.
                Positioned(
                  left: hPad,
                  right: hPad,
                  top: lerpDouble(
                      blockTop + _statsTop(s), blockTop + _stripGapAbove, q)!,
                  child: Row(
                    children: [
                      _statCard(theme, q, title: 'meal'.tr, value: mealCount),
                      SizedBox(width: lerpDouble(_statGap, _statGapDocked, q)),
                      _statCard(theme, q,
                          title: 'meal_paid'.tr, value: mealPaid),
                      SizedBox(width: lerpDouble(_statGap, _statGapDocked, q)),
                      _statCard(theme, q,
                          title: 'other_paid'.tr, value: otherPaid),
                    ],
                  ),
                ),

                Positioned(
                  left: hPad,
                  top: topPadding,
                  height: kToolbarHeight,
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'profile'.tr,
                        style: TextStyle(
                          color: theme.textTheme.titleLarge?.color ??
                              Colors.black87,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Drawn at its open size and scaled down from the top left, so
                // the circle keeps its edge the whole way instead of being
                // laid out again — and its picture is fetched once.
                Positioned(
                  left: lerpDouble((width - _avatarOpen) / 2, hPad, m)!,
                  top: avatarTop,
                  child: Transform.scale(
                    scale: avatarScale,
                    alignment: Alignment.topLeft,
                    child: ProfileAvatar(
                      name: name,
                      phone: phone,
                      imageUrl: imageUrl,
                      isMe: true,
                      size: _avatarOpen,
                      background: theme.colorScheme.primary,
                      foreground: Colors.white,
                      fontSize: 36,
                    ),
                  ),
                ),

                Positioned(
                  left: textLeft,
                  right: hPad,
                  top: textTop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: lineAlign,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name.isNotEmpty ? name : 'unknown_user'.tr,
                                style: TextStyle(
                                  fontSize:
                                      lerpDouble(_nameOpen, _nameDocked, m),
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.titleLarge?.color ??
                                      Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isAdmin) _badge(m),
                          ],
                        ),
                      ),
                      const SizedBox(height: _gapNamePhone),
                      Align(
                        alignment: lineAlign,
                        child: Text(
                          phone,
                          style: TextStyle(
                            fontSize: lerpDouble(_phoneOpen, _phoneDocked, m),
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // A hairline instead of a shadow: it holds its weight in both
                // themes, where a shadow all but vanishes in the dark one.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: edgeOpacity,
                    child: Container(
                      height: 0.6,
                      color: theme.dividerColor,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The admin mark. Open, it is a pill with a word in it; docked, the pill
  /// has folded down to the shield alone — there is no room beside a name in a
  /// toolbar, and the shield says it on its own.
  Widget _badge(double m) {
    final double away = 1 - m;

    return Padding(
      padding: EdgeInsets.only(left: lerpDouble(8, 6, m)!),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: lerpDouble(8, 0, m)!,
          vertical: lerpDouble(4, 0, m)!,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.shade100.withOpacity(away),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user,
                size: lerpDouble(14, 13, m), color: Colors.blue.shade700),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: away,
                child: Opacity(
                  opacity: away,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'admin'.tr,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One figure, at whatever size the scroll has left it: a card while the
  /// header is open, a chip along the bottom of the bar once it has closed.
  /// The same box the whole way — there is no second version of it to swap in.
  Widget _statCard(ThemeData theme, double q,
      {required String title, required String value}) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: lerpDouble(_statPadV, _statPadVDocked, q)!,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(lerpDouble(16, 12, q)!),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: lerpDouble(_statValue, _statValueDocked, q),
                fontWeight: FontWeight.bold,
                color: theme.textTheme.titleLarge?.color ?? Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: lerpDouble(4, 2, q)),
            Text(
              title,
              style: TextStyle(
                fontSize: lerpDouble(_statLabel, _statLabelDocked, q),
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
