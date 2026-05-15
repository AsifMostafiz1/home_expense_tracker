import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_constant.dart';
import '../model/chat_message_model.dart';
import 'chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<ChatMessageModel>> getMessagesStream() {
    return _firestore
        .collection(AppConstant.collectionChats)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessageModel.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Future<void> sendMessage(String text, String senderName, String senderPhone, {ChatMessageModel? replyTo}) async {
    final message = ChatMessageModel(
      id: '', // Firestore will auto-generate
      text: text,
      senderName: senderName,
      senderPhone: senderPhone,
      createdAt: DateTime.now(), // Local timestamp, will be overwritten by serverTimestamp in toMap
      replyToMessageId: replyTo?.id,
      replyToText: replyTo?.text,
      replyToSenderName: replyTo?.senderName,
    );
    await _firestore.collection(AppConstant.collectionChats).add(message.toMap());
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChatUsers() async {
    final snapshot = await _firestore.collection(AppConstant.collectionUsers).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
