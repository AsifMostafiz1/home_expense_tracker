import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

/// Which conversation a controller, a screen or a queued message belongs to.
///
/// The house has exactly one group thread and one direct thread per pair of
/// members. Everything downstream — the repository, the outbox, the push
/// notification — asks this object where a message is going rather than
/// carrying a pile of nullable phone numbers around.
class ChatThread {
  /// The other person in a direct chat. Null means the house group.
  final String? peerPhone;

  /// Their name and picture as of the moment the thread was opened — enough
  /// to draw the header before anything loads.
  final String peerName;
  final String? peerImage;

  /// The signed-in member. Only needed to work out [conversationId].
  final String myPhone;

  const ChatThread._({
    this.peerPhone,
    this.peerName = '',
    this.peerImage,
    this.myPhone = '',
  });

  /// The one thread everybody in the house shares.
  const ChatThread.group() : this._();

  ChatThread.direct({
    required String peerPhone,
    required String peerName,
    required String myPhone,
    String? peerImage,
  }) : this._(
          peerPhone: peerPhone,
          peerName: peerName,
          peerImage: peerImage,
          myPhone: myPhone,
        );

  bool get isGroup => peerPhone == null;

  bool get isDirect => peerPhone != null;

  /// The document id of a direct thread — null for the group, which lives in
  /// its own top-level collection and needs no id.
  String? get conversationId =>
      isGroup ? null : conversationIdFor(myPhone, peerPhone!);

  /// Identity for `Get.put`/`Get.find`, so every direct chat gets its own
  /// controller while the group keeps the untagged one the dashboard holds.
  String? get controllerTag => conversationId;

  /// The same id whichever end builds it: both phones, sorted, joined. A pair
  /// of members can only ever have one thread between them.
  static String conversationIdFor(String a, String b) {
    final List<String> pair = [a, b]..sort();
    return '${pair[0]}__${pair[1]}';
  }

  /// The other participant of [conversationId], seen from [myPhone].
  static String? peerOf(String conversationId, String myPhone) {
    final List<String> parts = conversationId.split('__');
    if (parts.length != 2) return null;
    return parts[0] == myPhone ? parts[1] : parts[0];
  }
}

/// The summary document of a direct thread: who is in it, what was said last,
/// and how much of it each side has not read.
///
/// Denormalised on purpose. The chat list shows a row per member and would
/// otherwise need one query per conversation just to render a preview.
class DirectThread {
  final String id;
  final List<String> participants;
  final String lastText;
  final String lastSenderPhone;
  final DateTime? lastAt;
  final bool lastHasImage;

  /// Unread count per phone number. Bumped for the recipient on every send,
  /// zeroed when they open the thread.
  final Map<String, int> unread;

  /// When each participant last deleted the thread for themselves — see
  /// `ChatRepository.clearThreadHistory`. Nothing is removed by that; this is
  /// the line under which a member is simply shown nothing any more, and the
  /// other end's copy is untouched.
  final Map<String, DateTime> cleared;

  const DirectThread({
    required this.id,
    this.participants = const [],
    this.lastText = '',
    this.lastSenderPhone = '',
    this.lastAt,
    this.lastHasImage = false,
    this.unread = const {},
    this.cleared = const {},
  });

  int unreadFor(String phone) => unread[phone] ?? 0;

  DateTime? clearedFor(String phone) => cleared[phone];

  /// Whether anything in this thread is still [phone]'s to see.
  ///
  /// What the chat list draws its row from: a thread somebody has deleted for
  /// themselves goes back to being an invitation rather than a conversation,
  /// until the next message arrives.
  bool hasHistoryFor(String phone) {
    if (!hasMessage) return false;

    final DateTime? cut = cleared[phone];
    if (cut == null) return true;

    // `last_at` is a server stamp and is briefly null on the sender's own
    // device — a message that new is certainly newer than the cut.
    final DateTime? at = lastAt;
    return at == null || at.isAfter(cut);
  }

  /// Whether anything has been said. `last_sender_phone` is written on every
  /// send, while `last_at` is a server timestamp that is still null on the
  /// sender's own device until the write lands — so the row must not fall
  /// back out of the recent list for the second it takes to sync.
  bool get hasMessage =>
      lastSenderPhone.isNotEmpty || lastAt != null || lastText.isNotEmpty;

  /// What the row under the name shows. A picture with no caption still needs
  /// something to say for itself.
  String get preview {
    if (lastText.trim().isNotEmpty) return lastText.trim();
    if (lastHasImage) return '📷 ${'photo'.tr}';
    return '';
  }

  factory DirectThread.fromMap(String id, Map<String, dynamic> map) {
    final Map<String, dynamic> raw =
        Map<String, dynamic>.from(map['unread'] ?? const <String, dynamic>{});
    return DirectThread(
      id: id,
      participants: List<String>.from(map['participants'] ?? const <String>[]),
      lastText: (map['last_text'] ?? '').toString(),
      lastSenderPhone: (map['last_sender_phone'] ?? '').toString(),
      lastAt: (map['last_at'] as Timestamp?)?.toDate(),
      lastHasImage: map['last_has_image'] == true,
      unread: raw.map((key, value) =>
          MapEntry(key, (value as num?)?.toInt() ?? 0)),
      cleared: <String, DateTime>{
        for (final MapEntry<String, dynamic> entry
            in Map<String, dynamic>.from(
                    map['cleared'] ?? const <String, dynamic>{})
                .entries)
          if (entry.value is Timestamp)
            entry.key: (entry.value as Timestamp).toDate(),
      },
    );
  }
}

/// The group chat's own identity: what it is called and what it looks like.
///
/// One document for the whole house. Both fields are optional — a house that
/// never opens the settings sheet gets the translated default name and an
/// icon built from its members' faces, which is most of them.
class GroupInfo {
  /// Empty means nobody has named it; [displayName] falls back.
  final String name;

  /// The picture an admin uploaded, if any. Without one the icon is built
  /// from the members — see `GroupAvatar`.
  final String? imageUrl;

  /// Who last changed it, and when. Kept so a rename has an author on the
  /// record the way every other house-wide change does.
  final String? updatedBy;
  final DateTime? updatedAt;

  const GroupInfo({
    this.name = '',
    this.imageUrl,
    this.updatedBy,
    this.updatedAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get hasName => name.trim().isNotEmpty;

  /// What the header and the list row show.
  String get displayName => hasName ? name.trim() : 'group_chat'.tr;

  factory GroupInfo.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GroupInfo();
    final String image = (map['image'] ?? '').toString();
    return GroupInfo(
      name: (map['name'] ?? '').toString(),
      imageUrl: image.isEmpty ? null : image,
      updatedBy: (map['updated_by'] ?? '').toString().isEmpty
          ? null
          : map['updated_by'].toString(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// A member of the house, as the chat list needs them: someone to talk to.
///
/// Deliberately not `MemberModel` — that one is about roles and removal, this
/// one is about whether the person is around right now.
class ChatUser {
  final String name;
  final String phone;
  final String? image;
  final bool isAdmin;
  final bool isRemoved;

  /// Last heartbeat from their device — see `PresenceService`. Null for
  /// anyone who has not opened the app since presence was introduced.
  final DateTime? lastActiveAt;

  const ChatUser({
    required this.name,
    required this.phone,
    this.image,
    this.isAdmin = false,
    this.isRemoved = false,
    this.lastActiveAt,
  });

  /// How long a heartbeat counts for. Twice the beat interval, so one missed
  /// write — a moment of no signal — does not blink somebody offline.
  static const Duration onlineWindow = Duration(minutes: 4);

  bool get isOnline {
    final DateTime? seen = lastActiveAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen) < onlineWindow;
  }

  factory ChatUser.fromMap(String id, Map<String, dynamic> map) {
    return ChatUser(
      name: (map['name'] ?? 'unknown'.tr).toString(),
      // The document id is the phone; the field only stands in for it on
      // older records that were written without one.
      phone: (map['phone'] ?? id).toString(),
      image: (map['profileImage'] ?? '').toString().isEmpty
          ? null
          : map['profileImage'].toString(),
      isAdmin: map['isAdmin'] == '1',
      isRemoved: map['removed'] == true,
      lastActiveAt: (map['last_active'] as Timestamp?)?.toDate(),
    );
  }
}
