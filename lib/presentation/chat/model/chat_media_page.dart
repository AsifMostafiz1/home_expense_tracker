import 'chat_message_model.dart';

/// One read of a conversation's pictures, and where the next read picks up.
///
/// The gallery walks a thread backwards in pages rather than asking Firestore
/// for "messages that carry a picture": that query needs an index on a field
/// most messages do not have, and the house's history is a few hundred
/// messages, not a few hundred thousand.
class ChatMediaPage {
  /// The pictures found in this pass, newest first.
  final List<ChatMessageModel> items;

  /// When the oldest message this pass looked at was sent — where the next
  /// page starts. Null when nothing was left to look at.
  final DateTime? cursor;

  /// True once the walk reached the beginning of the conversation. Anything
  /// else means there is more history behind [cursor], whether or not this
  /// page found pictures in it.
  final bool reachedEnd;

  const ChatMediaPage({
    required this.items,
    this.cursor,
    this.reachedEnd = false,
  });

  static const ChatMediaPage empty =
      ChatMediaPage(items: <ChatMessageModel>[], reachedEnd: true);
}
