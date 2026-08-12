import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

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
  /// `Scaffold.floatingActionButton`.
  final Widget Function(BuildContext context, Widget fab) builder;

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
  bool _visible = true;

  bool _onScroll(UserScrollNotification notification) {
    // Horizontal strips inside the page — a month switcher, a chip row — must
    // not drag the button off screen with them.
    if (notification.metrics.axis != Axis.vertical) return false;

    final bool next;
    if (notification.direction == ScrollDirection.reverse) {
      next = false;
    } else if (notification.direction == ScrollDirection.forward) {
      next = true;
    } else {
      // Idle: a scroll came to rest. Leave the button as the gesture left it.
      return false;
    }

    debugPrint('HFAB scroll dir=${notification.direction} next=$next was=$_visible');
    if (next != _visible) setState(() => _visible = next);
    return false; // Keep bubbling — RefreshIndicator and friends want these.
  }

  @override
  Widget build(BuildContext context) {
    // Handing [Scaffold] a null button — rather than wrapping one in a fade or
    // a slide — lets its own entrance and exit transition do the work, which is
    // both the Material behaviour and the one path that reliably re-runs when
    // the button comes back.
    debugPrint('HFAB build visible=$_visible tooltip=${widget.tooltip}');
    final Widget fab = _visible
        ? FloatingActionButton(
            key: const ValueKey('hiding-fab'),
            onPressed: widget.onPressed,
            tooltip: widget.tooltip,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            child: Icon(widget.icon),
          )
        : const SizedBox.shrink(key: ValueKey('hiding-fab-gone'));

    return NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: widget.builder(context, fab),
    );
  }
}
