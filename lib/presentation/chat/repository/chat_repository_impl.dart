import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/chat_message_model.dart';
import 'chat_repository.dart';

/// Firestore-backed, and offline-first — the same shape as the expense
/// repository. Every write lands in Firestore's local store at once and is
/// queued for the server; the futures below only wait for the server's
/// acknowledgement while there is a connection to wait on, and even then not
/// for long. See `ExpenseRepositoryImpl` for the reasoning in full.
class ChatRepositoryImpl implements ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Optional: the background sync builds one of these with no service —
  /// it only runs with a network, so every write there waits for its ack.
  final ConnectivityService? connectivity;

  ChatRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection(AppConstant.collectionChats);

  @override
  Stream<List<ChatMessageModel>> getMessagesStream() {
    return _chats
        .orderBy('createdAt', descending: true)
        .limit(100)
        // Metadata too: a message going from "on this device" to "on the
        // server" changes nothing in its data, and the clock on its bubble
        // has to clear all the same.
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessageModel.fromMap(
                doc.id,
                doc.data(),
                isPending: doc.metadata.hasPendingWrites,
              ))
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
      createdAt: DateTime
          .now(), // Local timestamp, will be overwritten by serverTimestamp in toMap
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
    await _commit(_chats.doc().set(message.toMap()));
  }

  @override
  Future<void> editMessage(String messageId, String text, String editorPhone) {
    return _commit(_chats.doc(messageId).update({
      'text': text,
      'edited_at': FieldValue.serverTimestamp(),
      'edited_by': editorPhone,
    }));
  }

  @override
  Future<void> deleteMessage(
    String messageId, {
    required bool byAdmin,
    required String actorPhone,
  }) {
    return _commit(_chats.doc(messageId).update({
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
    }));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChatUsers() async {
    final snapshot =
        await _firestore.collection(AppConstant.collectionUsers).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  @override
  Future<void> setReaction(String messageId, String userPhone, String? emoji) {
    // A dotted path touches one key inside the map and nothing else — which
    // is exactly what the security rules allow a reaction to do.
    return _commit(_chats.doc(messageId).update({
      'reactions.$userPhone': emoji ?? FieldValue.delete(),
    }));
  }

  @override
  Future<void> updateSeenStatus(
      String messageId, String userPhone, String userName, String? userImage) {
    return _commit(_firestore
        .collection(AppConstant.collectionSeenStatus)
        .doc(userPhone)
        .set({
      'lastSeenMessageId': messageId,
      'userPhone': userPhone,
      'userName': userName,
      'userImage': userImage,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Stream<List<Map<String, dynamic>>> getSeenStatusStream() {
    return _firestore
        .collection(AppConstant.collectionSeenStatus)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Waits for the server's acknowledgement while online — a rejected write
  /// (rules, a window that ran out) still surfaces as an error — and returns
  /// at once when offline, leaving the write in Firestore's queue.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      unawaited(write.catchError(
        (Object e) => debugPrint('Chat: queued write failed — $e'),
      ));
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      debugPrint('Chat: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
