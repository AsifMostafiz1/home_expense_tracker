import 'dart:io';

import 'chat_message_model.dart';

/// A picture chosen in the composer, measured the moment it was picked.
///
/// The size is read once, here, rather than at upload time: the bubble that
/// appears while the upload runs needs the right shape straight away, and the
/// receiving side needs it stamped on the message for the same reason.
class PickedImage {
  final File file;
  final double width;
  final double height;

  const PickedImage({
    required this.file,
    required this.width,
    required this.height,
  });

  double get aspectRatio =>
      (width <= 0 || height <= 0) ? 1 : width / height;
}

/// A picture on its way out: queued, uploading, not yet in the thread.
///
/// It exists so the chat can show the photo the moment it is sent instead of
/// after the upload. Text messages need no equivalent — Firestore's local
/// write puts those on screen immediately, while an upload genuinely takes
/// seconds.
class OutgoingImage {
  /// Identity for the list and the retry buttons. Not a Firestore id — this
  /// message does not exist on the server yet.
  final String localId;

  final PickedImage picked;

  /// Caption typed alongside the picture. Only the first of a batch carries
  /// one, the way every chat app does it.
  final String caption;

  final ChatMessageModel? replyTo;

  /// Set when the upload failed. A failed item stays in the list, out of the
  /// queue's way, until the sender retries or drops it.
  bool failed;

  OutgoingImage({
    required this.localId,
    required this.picked,
    this.caption = '',
    this.replyTo,
    this.failed = false,
  });

  File get file => picked.file;
}
