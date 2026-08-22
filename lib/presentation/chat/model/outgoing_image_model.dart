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

  double get aspectRatio => (width <= 0 || height <= 0) ? 1 : width / height;
}

/// A message on its way out: queued on this device, not yet in the thread.
///
/// Every message the composer sends becomes one of these first — text or
/// picture, online or not — and the outbox delivers it as soon as it can. It
/// exists so a send feels immediate whatever the network is doing: the bubble
/// is on screen the moment the button is tapped, and stays there, across
/// restarts, until the message is really in Firestore.
///
/// Carries everything delivery needs, so nothing has to be looked up later —
/// in particular the push notification, worked out at send time from the
/// mentions and the reply, because the job that finally sends it may run in
/// the background with no controller around to ask.
class OutgoingMessage {
  /// Identity for the list and the retry buttons. Not a Firestore id — this
  /// message does not exist on the server yet.
  final String localId;

  /// The words — a message on its own, or the caption under a picture. Only
  /// the first picture of a batch carries one, the way every chat app does it.
  final String text;

  /// Which thread this is going to: null for the house group, otherwise the
  /// direct thread's id. Kept on the message rather than looked up later
  /// because the job that finally delivers it may be the OS background one,
  /// with no controller around to ask.
  final String? conversationId;

  /// The other person in a direct thread — whose unread count goes up when
  /// this lands. Null for the group.
  final String? peerPhone;

  /// The outbox's own copy of the picture, when there is one. Null for text.
  final String? imagePath;
  final double? imageWidth;
  final double? imageHeight;

  // Snapshot of the message being replied to, denormalised the same way the
  // real message will store it.
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderName;
  final String? replyToSenderPhone;
  final String? replyToImage;

  // Who is sending, as of the moment they sent — a later name change must
  // not rewrite history.
  final String senderName;
  final String senderPhone;
  final String? senderImage;

  // The push notification to fire once the message is in.
  final String pushTitle;
  final String pushBody;
  final List<String>? pushTargets;
  final Map<String, String> pushData;

  /// Set when delivery hit an error that is not going to fix itself — a
  /// storage rejection, a file that has gone. A failed item stays in the list,
  /// out of the queue's way, until the sender retries or drops it. Network
  /// trouble is not a failure: those simply wait.
  bool failed;

  final DateTime queuedAt;

  OutgoingMessage({
    required this.localId,
    required this.text,
    this.conversationId,
    this.peerPhone,
    this.imagePath,
    this.imageWidth,
    this.imageHeight,
    this.replyToId,
    this.replyToText,
    this.replyToSenderName,
    this.replyToSenderPhone,
    this.replyToImage,
    required this.senderName,
    required this.senderPhone,
    this.senderImage,
    required this.pushTitle,
    required this.pushBody,
    this.pushTargets,
    this.pushData = const {},
    this.failed = false,
    required this.queuedAt,
  });

  bool get isGroup => conversationId == null;

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  File? get file => hasImage ? File(imagePath!) : null;

  /// Width over height; a square for anything that could not be measured.
  double get aspectRatio {
    final double? w = imageWidth;
    final double? h = imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return 1;
    return w / h;
  }

  bool get hasReply => replyToId != null;

  /// The reply, rebuilt as the model the repository expects. Only the fields
  /// the message will quote are real; the rest are placeholders.
  ChatMessageModel? get replyTo {
    if (!hasReply) return null;
    return ChatMessageModel(
      id: replyToId!,
      text: replyToText ?? '',
      senderName: replyToSenderName ?? '',
      senderPhone: replyToSenderPhone ?? '',
      createdAt: queuedAt,
      imageUrl: replyToImage,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'text': text,
        'conversationId': conversationId,
        'peerPhone': peerPhone,
        'imagePath': imagePath,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'replyToSenderName': replyToSenderName,
        'replyToSenderPhone': replyToSenderPhone,
        'replyToImage': replyToImage,
        'senderName': senderName,
        'senderPhone': senderPhone,
        'senderImage': senderImage,
        'pushTitle': pushTitle,
        'pushBody': pushBody,
        'pushTargets': pushTargets,
        'pushData': pushData,
        'failed': failed,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory OutgoingMessage.fromJson(Map<String, dynamic> json) {
    return OutgoingMessage(
      localId: json['localId'] as String,
      text: (json['text'] ?? '') as String,
      conversationId: json['conversationId'] as String?,
      peerPhone: json['peerPhone'] as String?,
      imagePath: json['imagePath'] as String?,
      imageWidth: (json['imageWidth'] as num?)?.toDouble(),
      imageHeight: (json['imageHeight'] as num?)?.toDouble(),
      replyToId: json['replyToId'] as String?,
      replyToText: json['replyToText'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      replyToSenderPhone: json['replyToSenderPhone'] as String?,
      replyToImage: json['replyToImage'] as String?,
      senderName: (json['senderName'] ?? '') as String,
      senderPhone: (json['senderPhone'] ?? '') as String,
      senderImage: json['senderImage'] as String?,
      pushTitle: (json['pushTitle'] ?? '') as String,
      pushBody: (json['pushBody'] ?? '') as String,
      pushTargets: (json['pushTargets'] as List?)?.cast<String>(),
      pushData: Map<String, String>.from(
          (json['pushData'] as Map?) ?? const <String, String>{}),
      failed: json['failed'] == true,
      queuedAt: DateTime.tryParse((json['queuedAt'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}
