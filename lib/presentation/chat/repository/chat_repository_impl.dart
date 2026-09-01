import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/chat_media_page.dart';
import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../model/pinned_message_model.dart';
import '../model/typing_status_model.dart';
import 'chat_repository.dart';

/// Firestore-backed, and offline-first — the same shape as the expense
/// repository. Every write lands in Firestore's local store at once and is
/// queued for the server; the futures below only wait for the server's
/// acknowledgement while there is a connection to wait on, and even then not
/// for long. See `ExpenseRepositoryImpl` for the reasoning in full.
///
/// The group thread lives in `chats`, a direct thread in
/// `direct_chats/{conversationId}/messages`. Everything below routes on the
/// `conversationId` argument and is otherwise identical for both — a direct
/// message is the same message in a different place.
class ChatRepositoryImpl implements ChatRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Optional: the background sync builds one of these with no service —
  /// it only runs with a network, so every write there waits for its ack.
  final ConnectivityService? connectivity;

  ChatRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection(AppConstant.collectionChats);

  CollectionReference<Map<String, dynamic>> get _directChats =>
      _firestore.collection(AppConstant.collectionDirectChats);

  DocumentReference<Map<String, dynamic>> _thread(String conversationId) =>
      _directChats.doc(conversationId);

  /// Where a thread's messages live. Null takes the group's collection.
  CollectionReference<Map<String, dynamic>> _messages(String? conversationId) {
    if (conversationId == null) return _chats;
    return _thread(conversationId)
        .collection(AppConstant.subcollectionMessages);
  }

  /// Where a thread's read receipts live. The group keeps one document per
  /// member in a top-level collection — it predates direct chats and other
  /// code reads it — while a direct thread keeps its own alongside its
  /// messages.
  CollectionReference<Map<String, dynamic>> _seen(String? conversationId) {
    if (conversationId == null) {
      return _firestore.collection(AppConstant.collectionSeenStatus);
    }
    return _thread(conversationId).collection(AppConstant.subcollectionSeen);
  }

  /// Where a thread's typing flags live. Laid out exactly like [_seen] and
  /// for the same reason: the group's predate direct chats and sit in their
  /// own top-level collection, a direct thread keeps its own beside its
  /// messages.
  CollectionReference<Map<String, dynamic>> _typing(String? conversationId) {
    if (conversationId == null) {
      return _firestore.collection(AppConstant.collectionTypingStatus);
    }
    return _thread(conversationId).collection(AppConstant.subcollectionTyping);
  }

  @override
  Stream<List<ChatMessageModel>> getMessagesStream({String? conversationId}) {
    return _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        // Metadata too: a message going from "on this device" to "on the
        // server" changes nothing in its data, and the clock on its bubble
        // has to clear all the same.
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      // A snapshot that did not come from the cache is the server answering
      // — proof the connection works, whatever the reachability probe last
      // concluded. This stream runs from launch, so it is the app's most
      // frequent evidence.
      if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

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
    String? conversationId,
    String? peerPhone,
    String? action,
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
      action: action,
    );

    if (conversationId == null) {
      await _commit(_chats.doc().set(message.toMap()));
      return;
    }

    // A direct message is two writes that have to travel together: the
    // message itself, and the thread summary the chat list reads. A batch
    // keeps them one unit — both queue offline, both land together.
    final DocumentReference<Map<String, dynamic>> threadRef =
        _thread(conversationId);
    final WriteBatch batch = _firestore.batch();

    batch.set(
      threadRef.collection(AppConstant.subcollectionMessages).doc(),
      message.toMap(),
    );
    batch.set(
      threadRef,
      {
        'participants': [senderPhone, if (peerPhone != null) peerPhone]..sort(),
        'last_text': text,
        'last_sender_phone': senderPhone,
        'last_at': FieldValue.serverTimestamp(),
        'last_has_image': imageUrl != null,
        'updated_at': FieldValue.serverTimestamp(),
        // Merged into the map rather than written as a dotted key: `set`
        // treats a dot in a key as part of the name, `update` would fail on a
        // thread that does not exist yet.
        if (peerPhone != null)
          'unread': {peerPhone: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    await _commit(batch.commit());
  }

  @override
  Future<void> editMessage(
    String messageId,
    String text,
    String editorPhone, {
    String? conversationId,
  }) {
    return _commit(_messages(conversationId).doc(messageId).update({
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
    String? conversationId,
  }) {
    return _commit(_messages(conversationId).doc(messageId).update({
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
    return snapshot.docs
        .map((doc) => doc.data())
        // Removed accounts stay in Firestore as tombstones — the same reason
        // [getChatUsersStream] drops them. This one feeds the mention box,
        // where offering somebody who is no longer in the house is worse
        // than useless: the notification goes to a topic nobody listens to.
        .where((data) => data['removed'] != true)
        .toList();
  }

  @override
  Stream<List<ChatUser>> getChatUsersStream() {
    return _firestore
        .collection(AppConstant.collectionUsers)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatUser.fromMap(doc.id, doc.data()))
            // Removed accounts stay in Firestore as tombstones; there is
            // nobody there to write to any more.
            .where((user) => !user.isRemoved)
            .toList());
  }

  @override
  Future<List<ChatMessageModel>> fetchMessagesForSearch({
    String? conversationId,
    int limit = 500,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _messages(conversationId)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();

    return snapshot.docs
        .map((doc) => ChatMessageModel.fromMap(
              doc.id,
              doc.data(),
              isPending: doc.metadata.hasPendingWrites,
            ))
        .toList();
  }

  /// How many messages one trip to Firestore looks through. Big enough that a
  /// quiet week of talking does not cost several round trips, small enough
  /// that a thread nobody has posted a picture in is not read in full.
  static const int _mediaScanBatch = 150;

  /// How many of those trips one page may make. A ceiling rather than a
  /// budget: without it, a gallery opened on a thread of text alone would
  /// read the entire history before answering anything.
  static const int _mediaScanTrips = 5;

  @override
  Future<ChatMediaPage> fetchMediaPage({
    String? conversationId,
    DateTime? before,
    int want = 30,
  }) async {
    final List<ChatMessageModel> found = <ChatMessageModel>[];
    DateTime? cursor = before;
    bool reachedEnd = false;

    for (int trip = 0; trip < _mediaScanTrips; trip++) {
      Query<Map<String, dynamic>> query =
          _messages(conversationId).orderBy('createdAt', descending: true);
      if (cursor != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(cursor)]);
      }

      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await query.limit(_mediaScanBatch).get();

      if (snapshot.docs.isEmpty) {
        reachedEnd = true;
        break;
      }

      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final ChatMessageModel message = ChatMessageModel.fromMap(
          doc.id,
          doc.data(),
          isPending: doc.metadata.hasPendingWrites,
        );
        if (message.hasImage && !message.deleted) found.add(message);
      }

      // Where the next trip starts. A message still waiting for its server
      // timestamp has no `createdAt` to page from — it also sorts to the end
      // of a descending read, so the newest one that does have a time is the
      // right place to carry on from.
      final Timestamp? oldest = _lastStamp(snapshot.docs);
      if (oldest == null) {
        reachedEnd = true;
        break;
      }
      cursor = oldest.toDate();

      // A short read is Firestore saying there is nothing behind it.
      if (snapshot.docs.length < _mediaScanBatch) {
        reachedEnd = true;
        break;
      }

      if (found.length >= want) break;
    }

    return ChatMediaPage(
      items: found,
      cursor: cursor,
      reachedEnd: reachedEnd,
    );
  }

  /// The oldest real timestamp in a descending read, ignoring any trailing
  /// documents whose server timestamp has not landed yet.
  Timestamp? _lastStamp(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    for (int i = docs.length - 1; i >= 0; i--) {
      final Object? stamp = docs[i].data()['createdAt'];
      if (stamp is Timestamp) return stamp;
    }
    return null;
  }

  CollectionReference<Map<String, dynamic>> get _pinned =>
      _firestore.collection(AppConstant.collectionPinnedMessages);

  @override
  Stream<List<PinnedMessage>> getPinnedMessagesStream() {
    return _pinned
        .orderBy('order')
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final List<PinnedMessage> pins = snapshot.docs
          .map((doc) => PinnedMessage.fromMap(doc.id, doc.data()))
          .toList();
      // Sorted again here because `orderBy` cannot separate two pins that
      // share a position — which is what a reorder made offline looks like
      // until it lands. The message id breaks the tie the same way on every
      // device, so no two phones show a different list.
      pins.sort((a, b) {
        final int byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.messageId.compareTo(b.messageId);
      });
      return pins;
    });
  }

  @override
  Future<void> pinMessage(PinnedMessage pin) =>
      _commit(_pinned.doc(pin.messageId).set(pin.toMap()));

  @override
  Future<void> unpinMessage(String messageId) =>
      _commit(_pinned.doc(messageId).delete());

  @override
  Future<void> savePinnedOrder(List<PinnedMessage> pins) {
    final WriteBatch batch = _firestore.batch();
    for (int i = 0; i < pins.length; i++) {
      batch.set(
        _pinned.doc(pins[i].messageId),
        {'order': i},
        SetOptions(merge: true),
      );
    }
    return _commit(batch.commit());
  }

  @override
  Future<void> updatePinnedText(String messageId, String text) =>
      // An update, not a merged set: the caller only reaches this for a
      // message it can see is pinned, and a set would quietly conjure a pin
      // document with nothing in it but the words if that had just changed.
      // A pin taken down in between throws, which the caller swallows.
      _commit(_pinned.doc(messageId).update({'text': text}));

  @override
  Stream<GroupInfo> getGroupInfoStream() {
    return _firestore
        .collection(AppConstant.collectionConfig)
        .doc(AppConstant.docGroupChat)
        .snapshots()
        .map((doc) => GroupInfo.fromMap(doc.data()));
  }

  @override
  Future<void> saveGroupInfo({
    required String name,
    required String? imageUrl,
    required String actorPhone,
  }) {
    return _commit(_firestore
        .collection(AppConstant.collectionConfig)
        .doc(AppConstant.docGroupChat)
        .set({
      'name': name,
      // Removed rather than emptied, so `fromMap` reads one thing for "never
      // set" and "taken away".
      'image': imageUrl ?? FieldValue.delete(),
      'updated_by': actorPhone,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Stream<List<DirectThread>> getDirectThreadsStream(String myPhone) {
    if (myPhone.isEmpty) return Stream.value(const <DirectThread>[]);

    return _directChats
        .where('participants', arrayContains: myPhone)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final List<DirectThread> threads = snapshot.docs
          .map((doc) => DirectThread.fromMap(doc.id, doc.data()))
          .toList();
      // Sorted here rather than in the query: `orderBy` alongside
      // `arrayContains` needs a composite index, and a house has a handful of
      // threads. A message queued offline has no server timestamp yet, so it
      // sorts to the top where the sender expects it.
      threads.sort((a, b) {
        final DateTime aAt = a.lastAt ?? DateTime.now();
        final DateTime bAt = b.lastAt ?? DateTime.now();
        return bAt.compareTo(aAt);
      });
      return threads;
    });
  }

  @override
  Future<void> markThreadRead(String conversationId, String myPhone) {
    if (myPhone.isEmpty) return Future.value();
    return _commit(_thread(conversationId).set(
      {
        'unread': {myPhone: 0}
      },
      SetOptions(merge: true),
    ));
  }

  @override
  Future<void> setReaction(
    String messageId,
    String userPhone,
    String? emoji, {
    String? conversationId,
  }) {
    // A dotted path touches one key inside the map and nothing else — which
    // is exactly what the security rules allow a reaction to do.
    return _commit(_messages(conversationId).doc(messageId).update({
      'reactions.$userPhone': emoji ?? FieldValue.delete(),
    }));
  }

  @override
  Future<void> updateSeenStatus(
    String messageId,
    String userPhone,
    String userName,
    String? userImage, {
    String? conversationId,
  }) {
    return _commit(_seen(conversationId).doc(userPhone).set({
      'lastSeenMessageId': messageId,
      'userPhone': userPhone,
      'userName': userName,
      'userImage': userImage,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Stream<List<Map<String, dynamic>>> getSeenStatusStream({
    String? conversationId,
  }) {
    return _seen(conversationId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  @override
  Future<void> clearThreadHistory({
    required String conversationId,
    required String userPhone,
  }) {
    // Written twice on purpose, because two screens need it and each already
    // listens to one of the two places: the thread reads its own line from
    // the per-member document beside its read receipts, and the chat list
    // reads it from the thread summary it draws every row from. Neither has
    // to open a listener it does not already have.
    final WriteBatch batch = _firestore.batch();

    batch.set(
      _seen(conversationId).doc(userPhone),
      {
        'userPhone': userPhone,
        'clearedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      _thread(conversationId),
      {
        'cleared': {userPhone: FieldValue.serverTimestamp()},
        // Nothing left to have not read.
        'unread': {userPhone: 0},
      },
      SetOptions(merge: true),
    );

    return _commit(batch.commit());
  }

  @override
  Stream<DateTime?> getClearedAtStream({
    required String conversationId,
    required String userPhone,
  }) {
    return _seen(conversationId)
        .doc(userPhone)
        .snapshots()
        .map((doc) => (doc.data()?['clearedAt'] as Timestamp?)?.toDate());
  }

  @override
  Future<void> setTyping({
    required String userPhone,
    required String userName,
    required bool typing,
    String? conversationId,
  }) async {
    // Deliberately not through [_commit], and deliberately not awaited: a
    // typing flag is worth nothing by the time a retry would land, and every
    // keystroke would otherwise be waiting on a round trip. Offline the write
    // sits in Firestore's queue and goes out late, which the reader's own
    // staleness window takes care of — see [TypingStatus.isActive].
    unawaited(
      _typing(conversationId).doc(userPhone).set({
        'phone': userPhone,
        'name': userName,
        'typing': typing,
        'at': FieldValue.serverTimestamp(),
      }).catchError(
        (Object e) => debugPrint('Chat: typing flag not written — $e'),
      ),
    );
  }

  @override
  Stream<List<TypingStatus>> getTypingStream({String? conversationId}) {
    return _typing(conversationId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => TypingStatus.fromMap(doc.id, doc.data()))
              .toList(),
        );
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
      // The server acknowledged it. Same evidence as a live snapshot, and it
      // clears a probe that had wrongly given up on the connection.
      connectivity?.reportReachable();
    } on TimeoutException {
      debugPrint('Chat: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
