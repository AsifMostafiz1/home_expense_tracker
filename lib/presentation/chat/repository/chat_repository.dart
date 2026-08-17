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

  /// Sets — or, with a null [emoji], removes — [userPhone]'s reaction. The
  /// caller decides the toggle from the message it is holding, so this is a
  /// plain field write that works offline; a transaction would not.
  Future<void> setReaction(String messageId, String userPhone, String? emoji);
  Future<void> updateSeenStatus(String messageId, String userPhone, String userName, String? userImage);
  Stream<List<Map<String, dynamic>>> getSeenStatusStream();
}
