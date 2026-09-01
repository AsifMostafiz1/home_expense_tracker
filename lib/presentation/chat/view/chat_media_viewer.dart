import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../services/image_download_service.dart';
import '../../../utils/app_enums.dart';
import '../model/chat_message_model.dart';

/// Ties a picture in the grid to the same picture full screen, so one flies
/// into the other. Unique per message, which is all a hero tag has to be.
String chatMediaHeroTag(String messageId) => 'chat_media_$messageId';

/// The gallery's own tag, in the shape [ChatMediaViewer.heroTagFor] wants.
String chatMediaHeroTagFor(ChatMessageModel message) =>
    chatMediaHeroTag(message.id);

/// Every picture in a conversation, full screen, one swipe apart.
///
/// The gallery hands over the list it is showing and which one was tapped —
/// filter and all — so what can be swiped through is exactly what was on
/// screen a moment ago.
///
/// A tap puts the furniture away and leaves nothing but the photograph; a
/// double tap zooms into the spot the finger landed on. While a picture is
/// zoomed the pages stop swiping under it, so a drag moves the picture
/// rather than the album.
class ChatMediaViewer extends StatefulWidget {
  final List<ChatMessageModel> items;
  final int initialIndex;

  /// The width the grid decoded its thumbnails at. Reused here so the picture
  /// already in memory can stand in — full size and soft — for the instant
  /// before the real one arrives.
  final int thumbCacheWidth;

  /// Back to the conversation, landing on the message this picture came in.
  final void Function(ChatMessageModel message) onJumpToMessage;

  /// How a picture on screen is tied to the thumbnail it flew out of. The
  /// gallery and the thread tag theirs differently, and a flight only happens
  /// when both ends name it the same thing.
  final String Function(ChatMessageModel message) heroTagFor;

  const ChatMediaViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.thumbCacheWidth,
    required this.onJumpToMessage,
    this.heroTagFor = chatMediaHeroTagFor,
  });

  @override
  State<ChatMediaViewer> createState() => _ChatMediaViewerState();
}

class _ChatMediaViewerState extends State<ChatMediaViewer> {
  late final PageController _pages;
  late int _index;

  /// The strip of thumbnails along the bottom.
  final ScrollController _strip = ScrollController();

  /// One thumbnail plus the gap after it — the strip is centred by arithmetic
  /// rather than by measuring, so every item is the same width.
  static const double _stripItem = 50;
  static const double _stripGap = 8;
  static const double _stripPad = 16;

  /// Whether the bars are showing. A tap hides them: what somebody opened is
  /// the photograph, not the caption above it.
  bool _chrome = true;

  /// Whether the picture on screen is zoomed in, which is what decides
  /// between panning a picture and turning a page.
  bool _zoomed = false;

  bool _precached = false;

  /// Whether a picture is on its way down. One at a time — the button is the
  /// spinner while it runs, so there is nothing to tap twice.
  bool _saving = false;

  /// Which pointers may drag a page along, or the strip under it.
  ///
  /// Flutter's own set leaves the mouse and the trackpad out, on the grounds
  /// that a desktop scrolls with a wheel. In a photo viewer that leaves no
  /// way at all to reach the next picture — dragging is the only gesture it
  /// offers — so a picture opened in a browser sits there and does nothing.
  static const Set<PointerDeviceKind> _dragDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pages = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreStrip(_index));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs a context with a MediaQuery in it, so not `initState`.
    if (!_precached) {
      _precached = true;
      _precacheNeighbours(_index);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  ChatMessageModel get _current => widget.items[_index];

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      // A new picture starts whole, and the pages start swiping again.
      _zoomed = false;
    });
    HapticFeedback.selectionClick();
    _centreStrip(index);
    _precacheNeighbours(index);
  }

  /// The next picture and the last one, fetched while this one is being
  /// looked at — a swipe then lands on a photograph rather than a spinner.
  void _precacheNeighbours(int index) {
    for (final int i in <int>[index - 1, index + 1]) {
      if (i < 0 || i >= widget.items.length) continue;
      final String? url = widget.items[i].imageUrl;
      if (url == null || url.isEmpty) continue;
      precacheImage(NetworkImage(url), context, onError: (_, __) {});
    }
  }

  void _centreStrip(int index) {
    if (!_strip.hasClients) return;
    const double stride = _stripItem + _stripGap;
    final double target = _stripPad +
        (index * stride) +
        (_stripItem / 2) -
        (_strip.position.viewportDimension / 2);
    _strip.animateTo(
      target.clamp(0.0, _strip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  /// Keeps the picture on screen: onto the phone's gallery, into the desktop's
  /// Downloads folder, or through the browser's own download.
  ///
  /// The URL is read before the wait rather than after, so swiping on to the
  /// next photograph mid-download still saves the one that was asked for.
  Future<void> _saveCurrent() async {
    if (_saving) return;

    final String? url = _current.imageUrl;
    if (url == null || url.isEmpty) return;

    setState(() => _saving = true);
    final ImageSaveOutcome outcome =
        await ImageDownloadService.saveFromUrl(url);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (outcome) {
      case ImageSaveOutcome.saved:
        HapticFeedback.lightImpact();
        CustomSnackbar.show(
          message: kIsWeb ? 'image_downloaded'.tr : 'image_saved'.tr,
          type: SnackbarType.success,
        );
      case ImageSaveOutcome.permissionDenied:
        CustomSnackbar.show(
          message: 'gallery_permission_denied'.tr,
          type: SnackbarType.warning,
          duration: const Duration(seconds: 4),
        );
      case ImageSaveOutcome.failed:
        CustomSnackbar.show(
          message: 'image_save_failed'.tr,
          type: SnackbarType.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Black behind, white icons over it, whatever the app's theme is.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        // Around both of the things that scroll here — the pager and the
        // strip of thumbnails at the bottom — see [_dragDevices].
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: _dragDevices, scrollbars: false),
          child: Stack(
            children: [
              Positioned.fill(child: _buildPager()),
              Positioned(
                  top: 0, left: 0, right: 0, child: _buildTopBar(context)),
              Positioned(
                  bottom: 0, left: 0, right: 0, child: _buildBottomBar(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPager() {
    return PageView.builder(
      controller: _pages,
      physics: _zoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: widget.items.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        final ChatMessageModel message = widget.items[i];
        return _ZoomablePhoto(
          key: ValueKey<String>(message.id),
          message: message,
          heroTag: widget.heroTagFor(message),
          thumbCacheWidth: widget.thumbCacheWidth,
          isCurrent: i == _index,
          onTap: _toggleChrome,
          onZoomChanged: (bool zoomed) {
            if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
          },
        );
      },
    );
  }

  /// Who sent this and when, how far through the album it is, and the way
  /// back to the message it arrived in.
  Widget _buildTopBar(BuildContext context) {
    final ChatMessageModel message = _current;

    return _chromeWrap(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        padding: EdgeInsets.fromLTRB(
            4, MediaQuery.of(context).padding.top + 4, 6, 26),
        child: Row(
          children: [
            IconButton(
              tooltip: 'close'.tr,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Get.back(),
            ),
            ProfileAvatar(
              name: message.senderName,
              phone: message.senderPhone,
              imageUrl: message.senderImage,
              size: 34,
              background: Colors.white.withOpacity(0.22),
              foreground: Colors.white,
              fontSize: 12.5,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.senderName.trim().isEmpty
                        ? 'unknown'.tr
                        : message.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(message.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.items.length > 1) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_index + 1}/${widget.items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
            ],
            _buildSaveButton(),
            IconButton(
              tooltip: 'jump_to_message'.tr,
              icon: const Icon(Icons.forum_outlined, color: Colors.white),
              onPressed: () => widget.onJumpToMessage(message),
            ),
          ],
        ),
      ),
    );
  }

  /// Keeping the picture. Turns into its own spinner while the bytes come
  /// down, in the space the icon already occupies, so the bar does not shuffle
  /// under a thumb that is about to tap something else.
  Widget _buildSaveButton() {
    if (_saving) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'save_image'.tr,
      icon: const Icon(Icons.file_download_outlined, color: Colors.white),
      onPressed: _saveCurrent,
    );
  }

  /// The caption, if the picture came with one, over a strip of everything
  /// else in the album.
  Widget _buildBottomBar(BuildContext context) {
    final String caption = _current.text.trim();

    return _chromeWrap(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Color(0x00000000)],
          ),
        ),
        padding: const EdgeInsets.only(top: 34),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: Text(
                    caption,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
              if (widget.items.length > 1) _buildStrip(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  /// Where in the album this picture sits, and a shortcut to any other one —
  /// the difference between swiping forty times and tapping once.
  Widget _buildStrip() {
    return SizedBox(
      height: _stripItem,
      child: ListView.separated(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _stripPad),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: _stripGap),
        itemBuilder: (context, i) {
          final bool selected = i == _index;
          final ChatMessageModel message = widget.items[i];

          return GestureDetector(
            onTap: () => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            ),
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0.55,
              duration: const Duration(milliseconds: 180),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _stripItem,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.network(
                    message.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: widget.thumbCacheWidth,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Colors.white10,
                      child: Icon(Icons.broken_image_outlined,
                          size: 16, color: Colors.white38),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Fades the bars away with the tap that hides them, and stops them taking
  /// taps meant for the picture underneath while they are gone.
  Widget _chromeWrap({required Widget child}) {
    return IgnorePointer(
      ignoring: !_chrome,
      child: AnimatedOpacity(
        opacity: _chrome ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// One picture in the pager.
///
/// Zoom is entered deliberately — a double tap, or a pinch once zoomed —
/// rather than by wrapping every page in something that pans. A pan gesture
/// living on top of a page every swipe has to travel through is what makes
/// photo viewers feel like they are fighting the thumb.
class _ZoomablePhoto extends StatefulWidget {
  final ChatMessageModel message;

  /// What the thumbnail this picture came from is tagged with.
  final String heroTag;

  final int thumbCacheWidth;

  /// Whether this is the page on screen. Only that one carries the hero, so
  /// closing the viewer flies exactly one picture back into the grid.
  final bool isCurrent;

  final VoidCallback onTap;

  /// Tells the pager to stop turning pages while this picture is zoomed.
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    super.key,
    required this.message,
    required this.heroTag,
    required this.thumbCacheWidth,
    required this.isCurrent,
    required this.onTap,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;

  /// Where the second tap landed, so the picture grows out of the spot under
  /// the finger rather than the middle of the screen.
  Offset? _doubleTapAt;

  bool _zoomed = false;

  static const double _doubleTapScale = 2.6;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final Animation<Matrix4>? tween = _zoomTween;
        if (tween != null) _transform.value = tween.value;
      });
  }

  @override
  void didUpdateWidget(covariant _ZoomablePhoto old) {
    super.didUpdateWidget(old);
    // Swiped away while zoomed in. Reset in place — the parent has already
    // put the pages back to swiping, and telling it again mid-build would be
    // a rebuild inside a rebuild.
    if (!widget.isCurrent && _zoomed) {
      _zoomAnimation.stop();
      _transform.value = Matrix4.identity();
      _zoomed = false;
    }
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target, {VoidCallback? then}) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
    );
    _zoomAnimation.forward(from: 0).whenComplete(() {
      if (mounted) then?.call();
    });
  }

  void _handleDoubleTap() {
    if (_zoomed) {
      _animateTo(Matrix4.identity(), then: _leaveZoom);
      return;
    }

    final Offset? focus = _doubleTapAt;
    if (focus == null) return;

    // The viewer has to be in place before the transform means anything, so
    // this happens first and the animation starts on the frame after.
    setState(() => _zoomed = true);
    widget.onZoomChanged(true);

    // Translate first, then scale: the composed matrix maps the tapped point
    // back onto itself, so it stays put under the finger.
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(
          -focus.dx * (_doubleTapScale - 1),
          -focus.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1),
    );
  }

  void _leaveZoom() {
    _transform.value = Matrix4.identity();
    setState(() => _zoomed = false);
    widget.onZoomChanged(false);
  }

  /// Pinched back down to nothing: hand the pages over again rather than
  /// leaving somebody stuck on a picture that no longer looks zoomed.
  void _onInteractionEnd(ScaleEndDetails _) {
    if (_transform.value.getMaxScaleOnAxis() <= 1.02) _leaveZoom();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SizedBox.expand(child: _photo(context));

    if (_zoomed) {
      content = InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: _onInteractionEnd,
        child: content,
      );
    }

    if (widget.isCurrent) {
      content = Hero(
        tag: widget.heroTag,
        child: content,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: content,
    );
  }

  Widget _photo(BuildContext context) {
    final String url = widget.message.imageUrl!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The grid's own thumbnail, already decoded and sitting in memory,
        // blown up underneath: the picture is there the instant it opens and
        // sharpens a moment later, rather than a spinner on black.
        Image.network(
          url,
          fit: BoxFit.contain,
          cacheWidth: widget.thumbCacheWidth,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          frameBuilder: (context, child, frame, wasSynchronous) {
            if (wasSynchronous) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: child,
            );
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.85),
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                    ),
                  ),
                ),
              ],
            );
          },
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 44),
                const SizedBox(height: 12),
                Text(
                  'image_load_failed'.tr,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
