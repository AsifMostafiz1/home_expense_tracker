import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import 'chat_message_model.dart';

/// A message somebody pinned to the top of the group thread.
///
/// Kept as its own document rather than a flag on the message, for two
/// reasons. The thread only ever streams its most recent hundred messages, so
/// a flag on something older would be invisible to the banner that has to show
/// it. And the pins carry an order the house arranges by hand, which is a
/// property of the pin, not of the message.
///
/// What it shows is denormalised from the message at pin time — the same way a
/// reply quotes what it is replying to. The two paths that could make that
/// stale, an edit and a delete, keep it honest themselves; see
/// `ChatController.deleteMessage` and `_submitEdit`.
class PinnedMessage {
  /// The pinned message's id. Also this document's id.
  final String messageId;

  final String text;
  final String senderName;
  final String senderPhone;
  final String? senderImage;

  /// The picture the message carried, if any.
  final String? imageUrl;

  /// When the message itself was sent — not when it was pinned.
  final DateTime? sentAt;

  final String pinnedBy;
  final String pinnedByName;
  final DateTime? pinnedAt;

  /// Where it sits in the list. Lower is higher up, and the top one is what
  /// the banner under the app bar shows.
  final int order;

  const PinnedMessage({
    required this.messageId,
    this.text = '',
    this.senderName = '',
    this.senderPhone = '',
    this.senderImage,
    this.imageUrl,
    this.sentAt,
    this.pinnedBy = '',
    this.pinnedByName = '',
    this.pinnedAt,
    this.order = 0,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// The pin in one line — what the banner and the list row show. A picture
  /// with no caption has nothing to quote, so it says what it is.
  String get preview {
    final String trimmed = text.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (hasImage) return '📷 ${'photo'.tr}';
    return 'message'.tr;
  }

  factory PinnedMessage.fromMessage(
    ChatMessageModel message, {
    required String pinnedBy,
    required String pinnedByName,
    required int order,
  }) {
    return PinnedMessage(
      messageId: message.id,
      text: message.text,
      senderName: message.senderName,
      senderPhone: message.senderPhone,
      senderImage: message.senderImage,
      imageUrl: message.imageUrl,
      sentAt: message.createdAt,
      pinnedBy: pinnedBy,
      pinnedByName: pinnedByName,
      order: order,
    );
  }

  PinnedMessage copyWith({int? order, String? text}) {
    return PinnedMessage(
      messageId: messageId,
      text: text ?? this.text,
      senderName: senderName,
      senderPhone: senderPhone,
      senderImage: senderImage,
      imageUrl: imageUrl,
      sentAt: sentAt,
      pinnedBy: pinnedBy,
      pinnedByName: pinnedByName,
      pinnedAt: pinnedAt,
      order: order ?? this.order,
    );
  }

  factory PinnedMessage.fromMap(String id, Map<String, dynamic> map) {
    return PinnedMessage(
      messageId: id,
      text: (map['text'] ?? '').toString(),
      senderName: (map['sender_name'] ?? '').toString(),
      senderPhone: (map['sender_phone'] ?? '').toString(),
      senderImage: (map['sender_image'] ?? '').toString().isEmpty
          ? null
          : map['sender_image'].toString(),
      imageUrl: (map['image_url'] ?? '').toString().isEmpty
          ? null
          : map['image_url'].toString(),
      sentAt: (map['sent_at'] as Timestamp?)?.toDate(),
      pinnedBy: (map['pinned_by'] ?? '').toString(),
      pinnedByName: (map['pinned_by_name'] ?? '').toString(),
      pinnedAt: (map['pinned_at'] as Timestamp?)?.toDate(),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'message_id': messageId,
        'text': text,
        'sender_name': senderName,
        'sender_phone': senderPhone,
        if (senderImage != null) 'sender_image': senderImage,
        if (imageUrl != null) 'image_url': imageUrl,
        if (sentAt != null) 'sent_at': Timestamp.fromDate(sentAt!),
        'pinned_by': pinnedBy,
        'pinned_by_name': pinnedByName,
        'pinned_at': FieldValue.serverTimestamp(),
        'order': order,
      };

  /// Newly pinned messages go to the top, which is where somebody who has
  /// just pinned one looks for it. A manual reorder renumbers from zero, so
  /// this only ever runs a little way below it.
  static int nextOrderFor(List<PinnedMessage> existing) =>
      existing.isEmpty ? 0 : existing.first.order - 1;
}
