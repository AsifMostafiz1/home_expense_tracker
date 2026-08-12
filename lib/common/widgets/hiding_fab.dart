import 'package:flutter/material.dart';

/// A floating action button that retracts while the page is scrolled down and
/// comes back the moment the user scrolls up.
///
/// It sits *above* the [Scaffold] rather than inside it, because scroll
/// notifications bubble up the tree: listening from here catches whichever
/// scroll view the body happens to use — a `SingleChildScrollView`, a
/// `CustomScrollView`, anything — without the screen having to own a
/// [ScrollController] or thread one through its GetX controller.
///
/// ```dart
/// HidingFab(
///   icon: Icons.add_rounded,
///   tooltip: 'add_expense'.tr,
///   onPressed: _add,
///   builder: (context, fab) => Scaffold(floatingActionButton: fab, ...),
/// )
/// ```
class HidingFab extends StatefulWidget {
  /// Builds the page. [fab] is the button to hand to
  /// `Scaffold.floatingActionButton`; it is null while retracted.
  final Widget Function(BuildContext context, Widget? fab) builder;

  final IconData icon;

  /// Also the button's accessible label — the icon alone says nothing to a
  /// screen reader.
  final String tooltip;

  final VoidCallback onPressed;

  const HidingFab({
    super.key,
    required this.builder,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<HidingFab> createState() => _HidingFabState();
}

class _HidingFabState extends State<HidingFab> {
  /// How far the page has travelled in the current direction. Reacting to
  /// `userScrollDirection` directly is too twitchy: the tail of a fling
  /// regularly reports one frame in the opposite direction, which flicked the
  /// button straight back on again the instant it hid.
  double _travelled = 0;

  /// Enough movement to read as intent rather than a stray frame.
  static const double _threshold = 30;

  bool _visible = true;

  bool _onScroll(ScrollUpdateNotification notification) {
    // Horizontal strips inside the page — a month switcher, a chip row — must
    // not drag the button off screen with them.
    if (notification.metrics.axis != Axis.vertical) return false;

    final double delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;

    // Back at the top there is nothing to get out of the way of.
    if (notification.metrics.pixels <= 0) {
      _travelled = 0;
      if (!_visible) setState(() => _visible = true);
      return false;
    }

    // A turn starts the count over, so the threshold measures one continuous
    // movement rather than the net of a whole gesture.
    if (delta.isNegative != _travelled.isNegative) _travelled = 0;
    _travelled += delta;

    if (_travelled > _threshold && _visible) {
      setState(() => _visible = false);
    } else if (_travelled < -_threshold && !_visible) {
      setState(() => _visible = true);
    }

    return false; // Keep bubbling — RefreshIndicator and friends want these.
  }

  @override
  Widget build(BuildContext context) {
    // Handing [Scaffold] a null button — rather than a faded or translated one
    // — lets its own entrance and exit transition do the work, which is both
    // the Material behaviour and the one path that reliably replays when the
    // button comes back.
    final Widget? fab = _visible
        ? FloatingActionButton(
            onPressed: widget.onPressed,
            tooltip: widget.tooltip,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            child: Icon(widget.icon),
          )
        : null;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: widget.builder(context, fab),
    );
  }
}
