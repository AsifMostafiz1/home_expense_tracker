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

  /// The send this picture arrived in, when several were picked at once.
  ///
  /// Every picture stays its own message — the gallery, the viewer, a reply
  /// and a delete all work on one picture at a time — but the thread draws a
  /// run of them as one grid, the way every chat app does. Null for anything
  /// sent on its own.
  final String? albumId;

  /// How many pictures that send carried. Read only to decide whether a grid
  /// is worth drawing at all before the siblings have loaded, and to count
  /// the ones a preview cannot show.
  final int? albumCount;

  /// Public URL of the voice message this one carries, when it is one. A
  /// voice note has no words: it is the whole message.
  final String? audioUrl;

  /// How long it runs, in milliseconds, stamped at send time. The bubble
  /// shows a length before a byte is fetched, and the player only learns the
  /// real one once it has loaded the file.
  final int? audioMs;

  /// The bars the bubble draws, 0–100, sampled off the microphone while it
  /// was being spoken.
  ///
  /// Stored rather than worked out on the receiving side: reading the shape
  /// of a sound means decoding the whole file, which is the thing a bubble
  /// must not do to show something the size of a sentence. Empty for anything
  /// sent before the waveform was recorded — the bubble then draws a flat
  /// bar, which is honest about knowing nothing.
  final List<int>? audioWave;

  /// Deleted messages are emptied, not removed: replies quote by id, and a
  /// hole in the thread reads worse than a line saying the message went away.
  final bool deleted;

  /// Set when the person who deleted it was not the person who wrote it.
  final bool deletedByAdmin;

  /// When the text was last changed, and who changed it. The editor is kept
  /// because an admin correcting somebody else's words has to be visible.
  final DateTime? editedAt;
  final String? editedByPhone;

  /// What tapping this message opens, when it is more than words.
  ///
  /// Null for anything somebody typed. A message the app composed on their
  /// behalf — the month ledger shared into the chat — carries the screen it
  /// came from, so the bubble can offer a way back to it instead of the
  /// reader having to go looking.
  ///
  /// A plain key rather than a route: what a build does with it is that
  /// build's business, and an older one simply shows the words.
  final String? action;

  /// The month ledger, shared as a message. See [action].
  static const String actionMonthlySummary = 'monthly_summary';

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
    this.albumId,
    this.albumCount,
    this.audioUrl,
    this.audioMs,
    this.audioWave,
    this.deleted = false,
    this.deletedByAdmin = false,
    this.editedAt,
    this.editedByPhone,
    this.action,
    this.reactions,
    this.isPending = false,
  });

  bool get hasAction => action != null && action!.isNotEmpty;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Whether this picture was one of several sent together.
  bool get isInAlbum =>
      albumId != null && albumId!.isNotEmpty && (albumCount ?? 1) > 1;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  /// How long the voice message runs, or zero for anything that is not one.
  Duration get audioDuration => Duration(milliseconds: audioMs ?? 0);

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
    if (hasAudio) return '🎤 ${'voice_message'.tr}';
    if (text.trim().isNotEmpty) return text.trim();
    if (isInAlbum) {
      return '📷 ${'photo_count'.trParams({'count': '$albumCount'})}';
    }
    return '📷 ${'photo'.tr}';
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
      albumId: (map['album_id'] ?? '').toString().isEmpty
          ? null
          : map['album_id'].toString(),
      albumCount: (map['album_count'] as num?)?.toInt(),
      audioUrl: map['audio_url'],
      audioMs: (map['audio_ms'] as num?)?.toInt(),
      audioWave: (map['audio_wave'] as List?)
          ?.map((dynamic level) => (level as num).toInt())
          .toList(),
      deleted: map['deleted'] == true,
      deletedByAdmin: map['deleted_by_admin'] == true,
      editedAt: (map['edited_at'] as Timestamp?)?.toDate(),
      editedByPhone: map['edited_by'],
      action: (map['action'] ?? '').toString().isEmpty
          ? null
          : map['action'].toString(),
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
      if (albumId != null) 'album_id': albumId,
      if (albumCount != null) 'album_count': albumCount,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (audioMs != null) 'audio_ms': audioMs,
      if (audioWave != null) 'audio_wave': audioWave,
      if (action != null) 'action': action,
      if (reactions != null) 'reactions': reactions,
    };
  }
}
