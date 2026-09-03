import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/chat/controller/chat_controller.dart';
import 'package:demo_project/presentation/chat/model/chat_message_model.dart';

/// A message in a thread, newest first — [at] is seconds from an arbitrary
/// start, so a test can say which came first without spelling out a date.
ChatMessageModel _message({
  required String id,
  String text = '',
  String sender = '01711111111',
  String? image,
  String? albumId,
  int? albumCount,
  bool deleted = false,
  int at = 0,
}) =>
    ChatMessageModel(
      id: id,
      text: text,
      senderName: 'Member',
      senderPhone: sender,
      createdAt: DateTime(2026, 1, 1).add(Duration(seconds: at)),
      imageUrl: image,
      albumId: albumId,
      albumCount: albumCount,
      deleted: deleted,
    );

/// The pictures of one send, in the order the thread holds them — newest
/// first, the way the stream hands them over.
List<ChatMessageModel> _album(String batch, int count, {String caption = ''}) {
  return <ChatMessageModel>[
    for (int i = count - 1; i >= 0; i--)
      _message(
        id: '${batch}_$i',
        text: i == 0 ? caption : '',
        image: 'https://pics/$batch/$i.jpg',
        albumId: batch,
        albumCount: count,
        at: i,
      ),
  ];
}

void main() {
  test('pictures sent together are drawn as one bubble', () {
    final rows = ChatController.groupRows(_album('b1', 4, caption: 'the bills'));

    expect(rows.length, 1);
    expect(rows.first.length, 4);
    // The bubble hangs on the first of the send — the one with the caption.
    expect(ChatController.anchorOf(rows.first).text, 'the bills');
  });

  test('a picture sent on its own keeps its own bubble', () {
    final rows = ChatController.groupRows(<ChatMessageModel>[
      _message(id: 'b', image: 'https://pics/b.jpg', at: 2),
      _message(id: 'a', image: 'https://pics/a.jpg', at: 1),
    ]);

    expect(rows.length, 2);
    expect(rows.every((row) => row.length == 1), isTrue);
  });

  test('two sends in a row stay two bubbles', () {
    final rows = ChatController.groupRows(<ChatMessageModel>[
      ..._album('b2', 2),
      ..._album('b1', 3),
    ]);

    expect(rows.map((row) => row.length).toList(), [2, 3]);
    expect(rows.first.first.albumId, 'b2');
    expect(rows.last.first.albumId, 'b1');
  });

  test('a message landing mid-batch splits it, because that is what happened',
      () {
    final batch = _album('b1', 3);
    final rows = ChatController.groupRows(<ChatMessageModel>[
      batch[0],
      _message(id: 'x', text: 'nice', sender: '01822222222'),
      batch[1],
      batch[2],
    ]);

    expect(rows.map((row) => row.length).toList(), [1, 1, 2]);
  });

  test('a deleted picture leaves the album and becomes its own tombstone', () {
    final batch = _album('b1', 3);
    final rows = ChatController.groupRows(<ChatMessageModel>[
      batch[0],
      _message(id: batch[1].id, albumId: 'b1', albumCount: 3, deleted: true),
      batch[2],
    ]);

    expect(rows.map((row) => row.length).toList(), [1, 1, 1]);
  });

  test('a batch of pictures from two people is never one bubble', () {
    final rows = ChatController.groupRows(<ChatMessageModel>[
      _message(
          id: '2',
          sender: '01822222222',
          image: 'https://pics/2.jpg',
          albumId: 'b1',
          albumCount: 2),
      _message(
          id: '1', image: 'https://pics/1.jpg', albumId: 'b1', albumCount: 2),
    ]);

    expect(rows.length, 2);
  });

  test('a quoted batch says how many pictures it was', () {
    final one = _message(id: '1', image: 'https://pics/1.jpg');
    final many = _album('b1', 5).last;

    expect(one.isInAlbum, isFalse);
    expect(many.isInAlbum, isTrue);
    // Translations are not loaded in a unit test, so the key stands in for
    // the sentence — what matters is that the two are not the same line.
    expect(one.preview, isNot(many.preview));
  });

  test('the send a picture belongs to survives a round trip through Firestore',
      () {
    final sent = _album('b1', 3).last;
    final read = ChatMessageModel.fromMap('id', <String, dynamic>{
      ...sent.toMap(),
      // The server stamps this one; toMap leaves a sentinel in its place.
      'createdAt': null,
    });

    expect(read.albumId, 'b1');
    expect(read.albumCount, 3);
    expect(read.isInAlbum, isTrue);
  });

  test('a message sent before albums existed reads back as one picture', () {
    final read = ChatMessageModel.fromMap('id', <String, dynamic>{
      'text': '',
      'image_url': 'https://pics/old.jpg',
    });

    expect(read.albumId, isNull);
    expect(read.isInAlbum, isFalse);
  });
}
