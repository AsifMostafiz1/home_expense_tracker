import '../model/chat_message_model.dart';

abstract class ChatRepository {
  Stream<List<ChatMessageModel>> getMessagesStream();
  Future<void> sendMessage(String text, String senderName, String senderPhone, {String? senderImage, ChatMessageModel? replyTo});
  Future<List<Map<String, dynamic>>> fetchChatUsers();
  Future<void> toggleReaction(String messageId, String userPhone, String emoji);
  Future<void> updateSeenStatus(String messageId, String userPhone, String userName, String? userImage);
  Stream<List<Map<String, dynamic>>> getSeenStatusStream();
}
