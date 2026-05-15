import '../model/chat_message_model.dart';

abstract class ChatRepository {
  Stream<List<ChatMessageModel>> getMessagesStream();
  Future<void> sendMessage(String text, String senderName, String senderPhone, {ChatMessageModel? replyTo});
  Future<List<Map<String, dynamic>>> fetchChatUsers();
}
