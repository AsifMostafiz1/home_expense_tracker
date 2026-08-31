import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'local_image.dart';

/// One picture, full screen and zoomable — a chat photo, a receipt, anything
/// the app can point at.
///
/// Takes either a URL or a local file: a receipt is worth reading at full size
/// before it has been saved as much as after.
///
/// Deliberately its own route rather than a dialog: the picture gets the whole
/// screen, the system back gesture closes it, and the thumbnail it came from
/// flies into place through a shared [heroTag].
class ImageViewerScreen extends StatefulWidget {
  final String? imageUrl;

  /// A picture that is still only on this device — a file path on mobile, a
  /// blob URL on web. See [LocalImage] for why it is a string.
  final String? localPath;

  /// Shown in the bar. The chat puts the sender here and the time underneath;
  /// an expense puts what was bought and what it cost.
  final String? title;
  final String? subtitle;

  /// Wording that belongs under the picture rather than over it — a chat
  /// caption, say.
  final String? caption;

  /// Matches the widget that opened this screen. Null skips the flight.
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    this.imageUrl,
    this.localPath,
    this.title,
    this.subtitle,
    this.caption,
    this.heroTag,
  }) : assert(imageUrl != null || localPath != null,
            'ImageViewerScreen needs something to show');

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;

  /// Where the second tap landed, so the zoom grows out of the spot the finger
  /// is on rather than the middle of the screen.
  Offset? _doubleTapAt;

  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final tween = _zoomTween;
        if (tween != null) _transform.value = tween.value;
      });
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
    );
    _zoomAnimation.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }

    final Offset? focus = _doubleTapAt;
    if (focus == null) return;

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

  @override
  Widget build(BuildContext context) {
    final String text = widget.caption?.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Get.back(),
        ),
        title: widget.title == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
      ),
      extendBodyBehindAppBar: true,
      body: SizedBox.expand(child: _hero(_viewer())),
      bottomNavigationBar: text.isEmpty
          ? null
          : Container(
              width: double.infinity,
              color: Colors.black.withOpacity(0.6),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: SafeArea(
                top: false,
                child: Text(
                  text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.4),
                ),
              ),
            ),
    );
  }

  Widget _hero(Widget child) =>
      widget.heroTag == null ? child : Hero(tag: widget.heroTag!, child: child);

  /// The zoomable surface is the whole screen, not the picture's own box: a
  /// letterboxed photo still pans and pinches from the black beside it, the way
  /// it does in a messaging app.
  Widget _viewer() {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: widget.localPath != null
              ? LocalImage(widget.localPath!, fit: BoxFit.contain)
              : _network(),
        ),
      ),
    );
  }

  Widget _network() {
    return Image.network(
      widget.imageUrl!,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            value: progress.expectedTotalBytes == null
                ? null
                : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
          ),
        );
      },
      errorBuilder: (_, __, ___) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              'image_load_failed'.tr,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
