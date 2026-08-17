import '../model/chat_message_model.dart';

abstract class ChatRepository {
  Stream<List<ChatMessageModel>> getMessagesStream();
  Future<void> sendMessage(
    String text,
    String senderName,
    String senderPhone, {
    String? senderImage,
    ChatMessageModel? replyTo,
    String? imageUrl,
    double? imageWidth,
    double? imageHeight,
  });
  /// Rewrites the text of an existing message, stamping who changed it.
  Future<void> editMessage(String messageId, String text, String editorPhone);

  /// Empties a message in place, leaving a tombstone the thread can still
  /// quote and scroll to.
  Future<void> deleteMessage(
    String messageId, {
    required bool byAdmin,
    required String actorPhone,
  });

  Future<List<Map<String, dynamic>>> fetchChatUsers();
  Future<void> toggleReaction(String messageId, String userPhone, String emoji);
  Future<void> updateSeenStatus(String messageId, String userPhone, String userName, String? userImage);
  Stream<List<Map<String, dynamic>>> getSeenStatusStream();
}
