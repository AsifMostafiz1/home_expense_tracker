import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

class ChatMessageModel {
  final String id;
  final String text;
  final String senderName;
  final String senderPhone;
  final String? senderImage;
  final DateTime createdAt;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderName;

  /// Thumbnail of the message being replied to, when that one was a picture.
  final String? replyToImage;

  /// Public URL of the picture this message carries. Text and picture are not
  /// exclusive — a captioned photo is one message with both.
  final String? imageUrl;

  /// Pixel size of that picture, stamped when it was sent so a bubble can hold
  /// the right shape before any bytes arrive. Without it the thread reflows
  /// under the reader's thumb as each image decodes.
  final double? imageWidth;
  final double? imageHeight;

  /// Deleted messages are emptied, not removed: replies quote by id, and a
  /// hole in the thread reads worse than a line saying the message went away.
  final bool deleted;

  /// Set when the person who deleted it was not the person who wrote it.
  final bool deletedByAdmin;

  /// When the text was last changed, and who changed it. The editor is kept
  /// because an admin correcting somebody else's words has to be visible.
  final DateTime? editedAt;
  final String? editedByPhone;

  final Map<String, String>? reactions;

  /// True while this message — or an edit, a reaction, a delete on it — is
  /// stored on this device only, waiting for a connection to reach the
  /// server. Read off Firestore's own queue; clears by itself once delivered.
  final bool isPending;

  ChatMessageModel({
    required this.id,
    required this.text,
    required this.senderName,
    required this.senderPhone,
    this.senderImage,
    required this.createdAt,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderName,
    this.replyToImage,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.deleted = false,
    this.deletedByAdmin = false,
    this.editedAt,
    this.editedByPhone,
    this.reactions,
    this.isPending = false,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get isEdited => editedAt != null;

  /// Whether the last edit came from somebody other than the author — the only
  /// case worth spelling out to a reader.
  bool get editedByOther =>
      editedByPhone != null && editedByPhone != senderPhone;

  /// Width over height, falling back to a square for anything sent before the
  /// dimensions were recorded.
  double get imageAspectRatio {
    final double? w = imageWidth;
    final double? h = imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return 1;
    return w / h;
  }

  /// The message in one line — what a reply preview, a notification and a
  /// quoted bubble show. A bare picture has no text to quote, so it says so.
  String get preview {
    if (deleted) return 'message_deleted'.tr;
    return text.trim().isNotEmpty ? text.trim() : '📷 ${'photo'.tr}';
  }

  factory ChatMessageModel.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool isPending = false,
  }) {
    return ChatMessageModel(
      id: id,
      text: map['text'] ?? '',
      senderName: map['sender_name'] ?? 'Unknown',
      senderPhone: map['sender_phone'] ?? '',
      senderImage: map['sender_image'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      replyToMessageId: map['reply_to_id'],
      replyToText: map['reply_to_text'],
      replyToSenderName: map['reply_to_name'],
      replyToImage: map['reply_to_image'],
      imageUrl: map['image_url'],
      imageWidth: (map['image_width'] as num?)?.toDouble(),
      imageHeight: (map['image_height'] as num?)?.toDouble(),
      deleted: map['deleted'] == true,
      deletedByAdmin: map['deleted_by_admin'] == true,
      editedAt: (map['edited_at'] as Timestamp?)?.toDate(),
      editedByPhone: map['edited_by'],
      reactions: map['reactions'] != null ? Map<String, String>.from(map['reactions']) : null,
      isPending: isPending,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'sender_name': senderName,
      'sender_phone': senderPhone,
      'sender_image': senderImage,
      'createdAt': FieldValue.serverTimestamp(),
      if (replyToMessageId != null) 'reply_to_id': replyToMessageId,
      if (replyToText != null) 'reply_to_text': replyToText,
      if (replyToSenderName != null) 'reply_to_name': replyToSenderName,
      if (replyToImage != null) 'reply_to_image': replyToImage,
      if (imageUrl != null) 'image_url': imageUrl,
      if (imageWidth != null) 'image_width': imageWidth,
      if (imageHeight != null) 'image_height': imageHeight,
      if (reactions != null) 'reactions': reactions,
    };
  }
}
