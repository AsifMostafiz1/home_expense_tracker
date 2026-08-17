import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One picture, full screen and zoomable — a chat photo, a receipt, anything
/// the app can point at.
///
/// Takes either a URL or a local file: a receipt is worth reading at full size
/// before it has been saved as much as after.
///
/// Deliberately its own route rather than a dialog: the picture gets the whole
/// screen, the system back gesture closes it, and the thumbnail it came from
/// flies into place through a shared [heroTag].
class ImageViewerScreen extends StatelessWidget {
  final String? imageUrl;

  /// A picture that is still only on this device.
  final File? imageFile;

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
    this.imageFile,
    this.title,
    this.subtitle,
    this.caption,
    this.heroTag,
  }) : assert(imageUrl != null || imageFile != null,
            'ImageViewerScreen needs something to show');

  @override
  Widget build(BuildContext context) {
    final String text = caption?.trim() ?? '';

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
        title: title == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
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
      body: Center(child: _hero(_viewer())),
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
      heroTag == null ? child : Hero(tag: heroTag!, child: child);

  Widget _viewer() {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: imageFile != null
          ? Image.file(imageFile!, fit: BoxFit.contain, width: double.infinity)
          : _network(),
    );
  }

  Widget _network() {
    return Image.network(
        imageUrl!,
        fit: BoxFit.contain,
        width: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            height: 220,
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                value: progress.expectedTotalBytes == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.all(32),
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
