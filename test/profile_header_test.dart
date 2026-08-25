import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/common/widgets/profile_avatar.dart';
import 'package:demo_project/presentation/profile/widgets/profile_header.dart';

/// A notch's worth of status bar, so the header cannot pass by leaving it out.
const double _statusBar = 44;
const double _width = 390;

double get _open => ProfileHeader.heightFor(1);
double get _travel => ProfileHeader.travelFor(1);
double get _dock => ProfileHeader.dockDistance(1);

/// The header as the bar hands it over: a box the height of the bar at that
/// point in the scroll, with the identity placed inside it.
Future<void> _pumpAt(WidgetTester tester, double offset) async {
  final double extent = _statusBar + kToolbarHeight + _open - offset;

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(_width, 844),
          padding: EdgeInsets.only(top: _statusBar),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _width,
            height: extent,
            child: ProfileHeader(
              offset: offset,
              topPadding: _statusBar,
              // Short on purpose: the test font draws every glyph a full em
              // wide, so a name of a realistic length fills the toolbar on its
              // own and leaves nothing to measure beside it.
              name: 'Mostafiz',
              phone: '01700000000',
              imageUrl: null,
              isAdmin: true,
              mealCount: '42',
              mealPaid: '৳3200',
              otherPaid: '৳1150',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('open: the identity is centred and the cards clear the bar',
      (WidgetTester tester) async {
    await _pumpAt(tester, 0);

    final Rect avatar = tester.getRect(find.byType(ProfileAvatar));
    expect(avatar.width, closeTo(100, 0.5));
    expect(avatar.center.dx, closeTo(_width / 2, 0.5),
        reason: 'the avatar sits in the middle of an open header');
    expect(avatar.top, closeTo(_statusBar + kToolbarHeight + 4, 0.5));

    // The page's own title is up in the toolbar while the header is open.
    expect(find.text('profile'), findsOneWidget);
    expect(tester.getRect(find.text('profile')).center.dy,
        closeTo(_statusBar + kToolbarHeight / 2, 0.5));

    // The stat cards, bottom padding included, have to finish above the bar's
    // edge — the figure heightFor() gives the bar is the only thing holding
    // them off it.
    final double barBottom = _statusBar + kToolbarHeight + _open;
    final Rect label = tester.getRect(find.text('meal'));
    expect(label.bottom + 20, lessThan(barBottom),
        reason: 'the cards would be clipped against the bar');

    // ...and not so far above it that the gap below reads as a hole.
    expect(
        barBottom - (label.bottom + 20), lessThan(ProfileHeader.gapBelow + 12));
  });

  testWidgets('docked: the identity has taken its place in the toolbar',
      (WidgetTester tester) async {
    await _pumpAt(tester, _dock);

    final Rect avatar = tester.getRect(find.byType(ProfileAvatar));
    expect(avatar.width, closeTo(36, 0.5), reason: 'scaled down, not swapped');
    expect(avatar.left, closeTo(ProfileHeader.hPad, 0.5));
    expect(avatar.center.dy, closeTo(_statusBar + kToolbarHeight / 2, 0.5));

    final Rect name = tester.getRect(find.text('Mostafiz'));
    expect(name.left, closeTo(ProfileHeader.hPad + 36 + 12, 0.5),
        reason: 'flush against the docked avatar');
    expect(name.top, greaterThanOrEqualTo(_statusBar));
    expect(tester.getRect(find.text('01700000000')).bottom,
        lessThan(_statusBar + kToolbarHeight),
        reason: 'the whole stack fits the toolbar');

    // The page title has gone: the identity has the bar now.
    expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .any((Opacity o) => o.opacity == 0),
        isTrue);

    // The admin pill has folded down to its shield: the label's box is shut
    // (it is still in the tree, clipped to nothing), and the shield has come
    // to rest against the name rather than a pill's width away from it.
    final Iterable<Align> folds = tester.widgetList<Align>(
        find.ancestor(of: find.text('admin'), matching: find.byType(Align)));
    expect(folds.any((Align a) => (a.widthFactor ?? 1) < 0.01), isTrue);
    expect(tester.getRect(find.byIcon(Icons.verified_user)).left - name.right,
        lessThan(10));
  });

  testWidgets('in between: one move, and nothing runs into anything else',
      (WidgetTester tester) async {
    Rect? lastAvatar;

    // Up to the dock only. Past it the identity is already in place and the
    // stat cards, faded out, are free to pass behind it on their way off the
    // top of the page.
    for (int step = 0; step <= 24; step++) {
      final double offset = _dock * step / 24;
      await _pumpAt(tester, offset);
      expect(tester.takeException(), isNull, reason: 'at $offset');

      final Rect avatar = tester.getRect(find.byType(ProfileAvatar));
      final Rect name = tester.getRect(find.text('Mostafiz'));
      final Rect phone = tester.getRect(find.text('01700000000'));
      final Rect card = tester.getRect(find
          .ancestor(of: find.text('42'), matching: find.byType(Container))
          .first);

      expect(avatar.overlaps(name.inflate(-0.5)), isFalse,
          reason: 'avatar over the name at $offset');
      expect(avatar.overlaps(phone.inflate(-0.5)), isFalse,
          reason: 'avatar over the number at $offset');
      // The name climbs at the page's rate and the cards a little slower, so
      // the gap between them can only ever open.
      expect(phone.bottom, lessThan(card.top),
          reason: 'the cards have caught the identity up at $offset');

      if (lastAvatar != null) {
        // Never sideways or back down: one avatar travelling, not two trading
        // places — and no step big enough to read as a cut.
        expect(avatar.top, lessThanOrEqualTo(lastAvatar.top + 0.01));
        expect(avatar.width, lessThanOrEqualTo(lastAvatar.width + 0.01));
        expect(avatar.left, lessThanOrEqualTo(lastAvatar.left + 0.01));
        expect(lastAvatar.top - avatar.top, lessThan(24));
        expect(lastAvatar.width - avatar.width, lessThan(24));
      }
      lastAvatar = avatar;
    }
  });

  testWidgets('the bar hands the header the whole of itself',
      (WidgetTester tester) async {
    // Everything above is the header on its own. This one checks the bargain
    // it has with the bar: that a pixel of scroll is a pixel off the bar's
    // height, and that the flexible space it is given starts at the very top
    // of the screen — the status bar is the header's to fill, and every figure
    // in it is measured from there.
    tester.view.physicalSize = const Size(_width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ScrollController scroll = ScrollController();
    final ValueNotifier<double> offset = ValueNotifier<double>(0);
    scroll.addListener(() => offset.value = scroll.offset.clamp(0.0, _travel));
    addTearDown(() {
      scroll.dispose();
      offset.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(_width, 844),
            padding: EdgeInsets.only(top: _statusBar),
          ),
          child: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SliverAppBar(
                  pinned: true,
                  expandedHeight: kToolbarHeight + _open,
                  collapsedHeight:
                      kToolbarHeight + ProfileHeader.collapsedFor(1),
                  automaticallyImplyLeading: false,
                  flexibleSpace: ValueListenableBuilder<double>(
                    valueListenable: offset,
                    builder: (BuildContext context, double value, _) =>
                        ProfileHeader(
                      offset: value,
                      topPadding: _statusBar,
                      name: 'Mostafiz',
                      phone: '01700000000',
                      imageUrl: null,
                      isAdmin: false,
                      mealCount: '42',
                      mealPaid: '৳3200',
                      otherPaid: '৳1150',
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 1200)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byType(ProfileHeader)).top, 0);
    expect(tester.getRect(find.byType(ProfileAvatar)).center.dx,
        closeTo(_width / 2, 0.5));

    scroll.jumpTo(_dock);
    await tester.pump();

    final Rect docked = tester.getRect(find.byType(ProfileAvatar));
    expect(docked.left, closeTo(ProfileHeader.hPad, 0.5));
    expect(docked.center.dy, closeTo(_statusBar + kToolbarHeight / 2, 0.5),
        reason: 'the avatar has to come to rest on the toolbar');

    scroll.jumpTo(_travel);
    await tester.pump();

    // Spent: the bar is the status bar, the toolbar, and the strip of figures
    // it holds on to.
    expect(
        tester.getSize(find.byType(ProfileHeader)).height,
        closeTo(
            _statusBar + kToolbarHeight + ProfileHeader.collapsedFor(1), 0.5));
    expect(tester.getRect(find.byType(ProfileAvatar)).center.dy,
        closeTo(_statusBar + kToolbarHeight / 2, 0.5));

    // And the figures have come to rest inside it rather than scrolling off
    // with the page — which is the whole point of the bar keeping that much
    // of itself back.
    final Rect strip = tester.getRect(find
        .ancestor(of: find.text('42'), matching: find.byType(Container))
        .first);
    expect(strip.top, greaterThan(_statusBar + kToolbarHeight - 0.5));
    expect(strip.bottom,
        lessThan(_statusBar + kToolbarHeight + ProfileHeader.collapsedFor(1)));
  });

  testWidgets('closed: the figures are still there, along the bar\'s bottom',
      (WidgetTester tester) async {
    await _pumpAt(tester, _travel);

    final double barBottom =
        _statusBar + kToolbarHeight + ProfileHeader.collapsedFor(1);
    final Rect card = tester.getRect(find
        .ancestor(of: find.text('42'), matching: find.byType(Container))
        .first);

    // Under the toolbar, inside the bar, with a gap left below it so the
    // list's first section does not sit against the strip.
    expect(card.top, greaterThanOrEqualTo(_statusBar + kToolbarHeight - 0.5));
    expect(card.bottom, lessThan(barBottom));
    expect(barBottom - card.bottom, greaterThan(8));

    // Still three of them, still legible: a strip, not a leftover.
    expect(find.text('42'), findsOneWidget);
    expect(find.text('meal'), findsOneWidget);
    expect(find.text('meal_paid'), findsOneWidget);
    expect(find.text('other_paid'), findsOneWidget);
    expect(card.height, lessThan(60), reason: 'the cards have shrunk');
    expect(card.height, greaterThan(36), reason: 'and not to nothing');

    // The identity is above them, in the toolbar, out of their way.
    expect(tester.getRect(find.byType(ProfileAvatar)).bottom,
        lessThanOrEqualTo(card.top));
  });
}
