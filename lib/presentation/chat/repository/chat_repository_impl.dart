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
  Future<void> sendMessage(
    String text,
    String senderName,
    String senderPhone, {
    String? senderImage,
    ChatMessageModel? replyTo,
    String? imageUrl,
    double? imageWidth,
    double? imageHeight,
  }) async {
    final message = ChatMessageModel(
      id: '', // Firestore will auto-generate
      text: text,
      senderName: senderName,
      senderPhone: senderPhone,
      senderImage: senderImage,
      createdAt: DateTime.now(), // Local timestamp, will be overwritten by serverTimestamp in toMap
      replyToMessageId: replyTo?.id,
      // The quote is denormalised, so a picture with no caption has to carry
      // its own stand-in text — there is nothing to quote otherwise.
      replyToText: replyTo?.preview,
      replyToSenderName: replyTo?.senderName,
      replyToImage: replyTo?.imageUrl,
      imageUrl: imageUrl,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    await _firestore.collection(AppConstant.collectionChats).add(message.toMap());
  }

  @override
  Future<void> editMessage(
      String messageId, String text, String editorPhone) async {
    await _firestore
        .collection(AppConstant.collectionChats)
        .doc(messageId)
        .update({
      'text': text,
      'edited_at': FieldValue.serverTimestamp(),
      'edited_by': editorPhone,
    });
  }

  @override
  Future<void> deleteMessage(
    String messageId, {
    required bool byAdmin,
    required String actorPhone,
  }) async {
    await _firestore
        .collection(AppConstant.collectionChats)
        .doc(messageId)
        .update({
      'deleted': true,
      'deleted_by_admin': byAdmin,
      // Never read back by the app — it is here so the security rules can tell
      // whose five-minute window to measure, and so a deletion has an author
      // on the record.
      'deleted_by': actorPhone,
      // Emptied rather than left in place: a deleted message must not still be
      // readable by anyone who scrolls back, and its reactions no longer mean
      // anything.
      'text': '',
      'image_url': FieldValue.delete(),
      'image_width': FieldValue.delete(),
      'image_height': FieldValue.delete(),
      'reactions': FieldValue.delete(),
    });
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

  @override
  Future<void> updateSeenStatus(String messageId, String userPhone, String userName, String? userImage) async {
    await _firestore
        .collection(AppConstant.collectionSeenStatus)
        .doc(userPhone)
        .set({
      'lastSeenMessageId': messageId,
      'userPhone': userPhone,
      'userName': userName,
      'userImage': userImage,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<List<Map<String, dynamic>>> getSeenStatusStream() {
    return _firestore
        .collection(AppConstant.collectionSeenStatus)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
