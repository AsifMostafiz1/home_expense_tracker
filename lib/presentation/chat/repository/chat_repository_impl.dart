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
  Future<void> sendMessage(String text, String senderName, String senderPhone, {String? senderImage, ChatMessageModel? replyTo}) async {
    final message = ChatMessageModel(
      id: '', // Firestore will auto-generate
      text: text,
      senderName: senderName,
      senderPhone: senderPhone,
      senderImage: senderImage,
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

  @override
  Future<void> toggleReaction(String messageId, String userPhone, String emoji) async {
    final docRef = _firestore.collection(AppConstant.collectionChats).doc(messageId);
    
    _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      Map<String, dynamic> reactions = data['reactions'] != null 
          ? Map<String, dynamic>.from(data['reactions']) 
          : {};

      if (reactions[userPhone] == emoji) {
        reactions.remove(userPhone);
      } else {
        reactions[userPhone] = emoji;
      }

      transaction.update(docRef, {'reactions': reactions});
    });
  }
}
