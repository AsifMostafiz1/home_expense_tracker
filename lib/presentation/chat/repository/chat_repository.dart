import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../model/pinned_message_model.dart';

/// Every method that touches a thread takes a [conversationId]: null means the
/// house group, anything else is the direct thread with that id. One
/// repository serves both because a direct message is the same message in a
/// different place — see `ChatThread`.
abstract class ChatRepository {
  Stream<List<ChatMessageModel>> getMessagesStream({String? conversationId});

  /// [peerPhone] is only read for a direct send, where the thread's summary
  /// document has to know who the unread count belongs to.
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

    /// What tapping the message opens — see `ChatMessageModel.action`.
    String? action,
  });

  /// Rewrites the text of an existing message, stamping who changed it.
  Future<void> editMessage(
    String messageId,
    String text,
    String editorPhone, {
    String? conversationId,
  });

  /// Empties a message in place, leaving a tombstone the thread can still
  /// quote and scroll to.
  Future<void> deleteMessage(
    String messageId, {
    required bool byAdmin,
    required String actorPhone,
    String? conversationId,
  });

  Future<List<Map<String, dynamic>>> fetchChatUsers();

  /// Everyone in the house, live — the chat list is a list of people first and
  /// a list of conversations second, and it also carries who is online.
  Stream<List<ChatUser>> getChatUsersStream();

  /// The messages pinned to the top of the group thread, in the order the
  /// house arranged them.
  Stream<List<PinnedMessage>> getPinnedMessagesStream();

  Future<void> pinMessage(PinnedMessage pin);

  Future<void> unpinMessage(String messageId);

  /// Renumbers every pin from zero after a drag.
  Future<void> savePinnedOrder(List<PinnedMessage> pins);

  /// Keeps a pinned message's copy of the words in step with an edit to the
  /// message itself.
  Future<void> updatePinnedText(String messageId, String text);

  /// The group chat's name and picture, live — an admin renaming it should
  /// reach every other phone without a relaunch.
  Stream<GroupInfo> getGroupInfoStream();

  /// Saves both. [imageUrl] null clears the picture and puts the merged
  /// members' icon back.
  Future<void> saveGroupInfo({
    required String name,
    required String? imageUrl,
    required String actorPhone,
  });

  /// The direct threads [myPhone] is part of, newest first.
  Stream<List<DirectThread>> getDirectThreadsStream(String myPhone);

  /// Zeroes this member's unread count on a direct thread. Called when the
  /// thread is opened and again whenever a message arrives while it is open.
  Future<void> markThreadRead(String conversationId, String myPhone);

  /// Sets — or, with a null [emoji], removes — [userPhone]'s reaction. The
  /// caller decides the toggle from the message it is holding, so this is a
  /// plain field write that works offline; a transaction would not.
  Future<void> setReaction(
    String messageId,
    String userPhone,
    String? emoji, {
    String? conversationId,
  });

  Future<void> updateSeenStatus(
    String messageId,
    String userPhone,
    String userName,
    String? userImage, {
    String? conversationId,
  });

  Stream<List<Map<String, dynamic>>> getSeenStatusStream({
    String? conversationId,
  });
}
