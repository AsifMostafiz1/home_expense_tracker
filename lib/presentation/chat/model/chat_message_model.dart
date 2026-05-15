import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  factory ChatMessageModel.fromMap(String id, Map<String, dynamic> map) {
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
    };
  }
}
