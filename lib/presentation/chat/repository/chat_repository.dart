import '../model/chat_media_page.dart';
import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../model/pinned_message_model.dart';
import '../model/typing_status_model.dart';

/// Every method that touches a thread takes a [conversationId]: null means the
/// house group, anything else is the direct thread with that id. One
/// repository serves both because a direct message is the same message in a
/// different place — see `ChatThread`.
abstract class ChatRepository {
  /// The tail of a thread, live — newest [limit] messages.
  ///
  /// The window is a parameter rather than a constant because a reader who
  /// scrolls past the end of it asks for a bigger one: the thread widens what
  /// it listens to instead of stitching a separate, dead page of history onto
  /// the end, so an edit, a reaction or a delete on a message from months ago
  /// still arrives while it is on screen.
  Stream<List<ChatMessageModel>> getMessagesStream({
    String? conversationId,
    int limit,
  });

  /// The window a search reads, which is deeper than the thread keeps in
  /// memory — somebody looking for what was said about the gas bill is
  /// usually looking further back than the last hundred messages.
  ///
  /// One read, newest first; the matching is done on the device, because
  /// Firestore cannot look inside a string.
  Future<List<ChatMessageModel>> fetchMessagesForSearch({
    String? conversationId,
    int limit,
  });

  /// One page of the pictures shared in a thread, newest first — what the
  /// conversation's gallery is built from.
  ///
  /// Walks the history backwards from [before] in batches, keeping whatever
  /// carries a picture, until it has [want] of them or runs out of thread.
  /// Firestore cannot filter on a field most messages do not have without an
  /// index for it, and a page walk needs none.
  Future<ChatMediaPage> fetchMediaPage({
    String? conversationId,
    DateTime? before,
    int want,
  });

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

    /// The send this picture belongs to, when several went out together —
    /// see `ChatMessageModel.albumId`.
    String? albumId,
    int? albumCount,
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

  /// Deletes a direct thread for one member, and for nobody else.
  ///
  /// Nothing is removed: what was said stays where it is for the person at
  /// the other end — a member does not get to unsay it. What is written is a
  /// line under the thread, and from here on this member is shown nothing
  /// above it, on this device and on any other they sign in to.
  ///
  /// Direct threads only. The house group belongs to the house, not to any
  /// one member, and nobody gets to take their own copy of it away.
  Future<void> clearThreadHistory({
    required String conversationId,
    required String userPhone,
  });

  /// Where that line currently sits, live — null until the member has ever
  /// drawn one.
  Stream<DateTime?> getClearedAtStream({
    required String conversationId,
    required String userPhone,
  });

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

  /// Raises or lowers [userPhone]'s typing flag on a thread.
  ///
  /// Never awaited by anything that matters: a flag is worth nothing by the
  /// time a retry would land, and a keystroke must not wait on a round trip.
  Future<void> setTyping({
    required String userPhone,
    required String userName,
    required bool typing,
    String? conversationId,
  });

  /// Who has the composer open in this thread, live.
  ///
  /// Includes the reader's own flag; the caller drops it, because that is the
  /// one nobody ever has to be told about.
  Stream<List<TypingStatus>> getTypingStream({String? conversationId});
}
