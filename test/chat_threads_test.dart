import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/chat/model/chat_thread_model.dart';
import 'package:demo_project/presentation/chat/model/chat_message_model.dart';
import 'package:demo_project/presentation/chat/model/pinned_message_model.dart';
import 'package:demo_project/presentation/chat/widgets/group_avatar.dart';

ChatUser _user(String phone, {DateTime? seen}) => ChatUser(
      name: 'Member $phone',
      phone: phone,
      lastActiveAt: seen,
    );

void main() {
  test('both ends of a pair build the same conversation id', () {
    const a = '01711111111';
    const b = '01822222222';

    expect(
      ChatThread.conversationIdFor(a, b),
      ChatThread.conversationIdFor(b, a),
    );
    // Sorted, so the id does not depend on who started the conversation.
    expect(ChatThread.conversationIdFor(b, a), '${a}__$b');
  });

  test('a thread knows which end of it is the other person', () {
    const me = '01711111111';
    const them = '01822222222';
    final String id = ChatThread.conversationIdFor(me, them);

    expect(ChatThread.peerOf(id, me), them);
    expect(ChatThread.peerOf(id, them), me);
    expect(ChatThread.peerOf('not-a-thread-id', me), isNull);
  });

  test('the group thread has no conversation to route to', () {
    const group = ChatThread.group();
    expect(group.isGroup, isTrue);
    expect(group.conversationId, isNull);
    expect(group.controllerTag, isNull);

    final direct = ChatThread.direct(
      peerPhone: '01822222222',
      peerName: 'Rakib',
      myPhone: '01711111111',
    );
    expect(direct.isDirect, isTrue);
    expect(direct.controllerTag, direct.conversationId);
  });

  test('unread is counted per participant', () {
    const thread = DirectThread(
      id: 'a__b',
      participants: ['a', 'b'],
      lastText: 'got the rice',
      lastSenderPhone: 'a',
      unread: {'b': 3},
    );

    expect(thread.unreadFor('b'), 3);
    // The sender has nothing waiting, and neither has somebody not in it.
    expect(thread.unreadFor('a'), 0);
    expect(thread.unreadFor('c'), 0);
  });

  test('a thread counts as started before its timestamp comes back', () {
    // What the sender's own device sees for the moment between the write and
    // the server's acknowledgement: no `last_at` yet.
    const pending = DirectThread(
      id: 'a__b',
      lastSenderPhone: 'a',
      lastHasImage: true,
    );
    expect(pending.hasMessage, isTrue);

    const untouched = DirectThread(id: 'a__b');
    expect(untouched.hasMessage, isFalse);
  });

  test('presence ages out rather than being switched off', () {
    final DateTime now = DateTime.now();

    expect(_user('a', seen: now).isOnline, isTrue);
    expect(
      _user('b', seen: now.subtract(const Duration(minutes: 3))).isOnline,
      isTrue,
    );
    expect(
      _user('c', seen: now.subtract(const Duration(minutes: 30))).isOnline,
      isFalse,
    );
    // Never heard from — someone who has not opened the app since presence
    // was introduced.
    expect(_user('d').isOnline, isFalse);
  });

  test('an unnamed group falls back rather than showing nothing', () {
    const bare = GroupInfo();
    expect(bare.hasName, isFalse);
    expect(bare.hasImage, isFalse);
    // Whatever the translation resolves to, the header is never empty.
    expect(bare.displayName, isNotEmpty);

    const named = GroupInfo(name: '  Bachelor Point  ');
    expect(named.hasName, isTrue);
    expect(named.displayName, 'Bachelor Point');
  });

  test('a group picture is only set when there is really one', () {
    expect(GroupInfo.fromMap(null).hasImage, isFalse);
    expect(GroupInfo.fromMap(const {'image': ''}).hasImage, isFalse);
    expect(
      GroupInfo.fromMap(const {'name': 'House', 'image': 'https://x/g.jpg'})
          .hasImage,
      isTrue,
    );
  });

  test('the merged group icon puts faces before initials', () {
    const withPhoto = ChatUser(name: 'Zahid', phone: '3', image: 'https://x/z.jpg');
    const noPhotoA = ChatUser(name: 'Arif', phone: '1');
    const noPhotoB = ChatUser(name: 'Bashir', phone: '2');
    const emptyPhoto = ChatUser(name: 'Chan', phone: '4', image: '');

    final ordered = GroupAvatar.orderForIcon(
        [noPhotoB, emptyPhoto, noPhotoA, withPhoto]);

    // The one face first, then the rest alphabetically — an empty string is
    // not a picture.
    expect(ordered.map((u) => u.name), ['Zahid', 'Arif', 'Bashir', 'Chan']);
  });

  test('a new pin goes above the ones already there', () {
    expect(PinnedMessage.nextOrderFor(const []), 0);

    const pins = [
      PinnedMessage(messageId: 'a', order: 0),
      PinnedMessage(messageId: 'b', order: 1),
    ];
    // Above the current top, so whoever just pinned it sees it in the banner.
    expect(PinnedMessage.nextOrderFor(pins), -1);
  });

  test('a pin carries what the message said at the time', () {
    final message = ChatMessageModel(
      id: 'm1',
      text: '  rent is due on the 5th  ',
      senderName: 'Rakib',
      senderPhone: '01711',
      senderImage: 'https://x/r.jpg',
      imageUrl: 'https://x/notice.jpg',
      createdAt: DateTime(2026, 8, 20, 19, 21),
    );

    final pin = PinnedMessage.fromMessage(
      message,
      pinnedBy: '01822',
      pinnedByName: 'Shetu',
      order: -1,
    );

    expect(pin.messageId, 'm1');
    expect(pin.senderName, 'Rakib');
    expect(pin.sentAt, DateTime(2026, 8, 20, 19, 21));
    expect(pin.pinnedByName, 'Shetu');
    expect(pin.hasImage, isTrue);
    // The preview is trimmed, and the words win over the picture.
    expect(pin.preview, 'rent is due on the 5th');
  });

  test('a pinned photo with no caption still says what it is', () {
    const captionless = PinnedMessage(
      messageId: 'm2',
      imageUrl: 'https://x/p.jpg',
    );
    expect(captionless.preview, isNotEmpty);
    expect(captionless.preview, isNot('m2'));

    // Neither words nor a picture — nothing to show, but never blank.
    const nothing = PinnedMessage(messageId: 'm3');
    expect(nothing.preview, isNotEmpty);
  });

  test('reordering a pin renumbers it without touching the message', () {
    const pin = PinnedMessage(
      messageId: 'm1',
      text: 'rent',
      senderPhone: '01711',
      order: 4,
    );

    final moved = pin.copyWith(order: 0);
    expect(moved.order, 0);
    // Everything the row draws comes along unchanged.
    expect(moved.messageId, 'm1');
    expect(moved.text, 'rent');
    expect(moved.senderPhone, '01711');
  });
}
