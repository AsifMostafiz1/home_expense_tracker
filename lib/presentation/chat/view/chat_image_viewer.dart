import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../model/chat_message_model.dart';

/// One chat picture, full screen and zoomable.
///
/// Deliberately its own route rather than a dialog: the picture gets the whole
/// screen, the system back gesture closes it, and the bubble it came from
/// flies into place through the shared [Hero] tag.
class ChatImageViewer extends StatelessWidget {
  final ChatMessageModel message;

  const ChatImageViewer({super.key, required this.message});

  /// Shared with the bubble so the two ends of the transition find each other.
  static String heroTag(ChatMessageModel message) =>
      'chat_image_${message.id}';

  @override
  Widget build(BuildContext context) {
    final String caption = message.text.trim();

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.senderName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              DateFormat('dd MMM, hh:mm a').format(message.createdAt),
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
      body: Center(
        child: Hero(
          tag: heroTag(message),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.network(
              message.imageUrl ?? '',
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
            ),
          ),
        ),
      ),
      bottomNavigationBar: caption.isEmpty
          ? null
          : Container(
              width: double.infinity,
              color: Colors.black.withOpacity(0.6),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: SafeArea(
                top: false,
                child: Text(
                  caption,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.4),
                ),
              ),
            ),
    );
  }
}
