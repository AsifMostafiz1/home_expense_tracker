import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/chat/model/chat_message_model.dart';
import 'package:demo_project/presentation/chat/model/chat_thread_model.dart';
import 'package:demo_project/presentation/chat/model/outgoing_image_model.dart';
import 'package:demo_project/presentation/chat/model/voice_note_model.dart';

ChatMessageModel _voice({
  String id = 'v1',
  int ms = 7400,
  List<int>? wave,
  bool deleted = false,
}) =>
    ChatMessageModel(
      id: id,
      text: '',
      senderName: 'Member',
      senderPhone: '01711111111',
      createdAt: DateTime(2026, 1, 1),
      audioUrl: deleted ? null : 'https://clips/$id.m4a',
      audioMs: deleted ? null : ms,
      audioWave: deleted ? null : (wave ?? const <int>[10, 80, 40]),
      deleted: deleted,
    );

void main() {
  group('the shape of a recording', () {
    test('a long recording is squeezed to a fixed number of bars', () {
      final List<int> levels = List<int>.generate(500, (i) => i % 100);
      final List<int> bars = RecordedVoice.resample(levels);

      expect(bars.length, RecordedVoice.bars);
      expect(bars.every((level) => level >= 0 && level <= 100), isTrue);
    });

    test('a short one is stretched to the same width', () {
      final List<int> bars = RecordedVoice.resample(<int>[20, 90]);

      expect(bars.length, RecordedVoice.bars);
      expect(bars.first, 20);
      expect(bars.last, 90);
    });

    test('averaging keeps the loud parts loud and the quiet parts quiet', () {
      // Ten readings per bar, all of the first half silent and all of the
      // second half loud.
      final List<int> levels = <int>[
        ...List<int>.filled(220, 8),
        ...List<int>.filled(220, 96),
      ];
      final List<int> bars = RecordedVoice.resample(levels);

      expect(bars.first, 8);
      expect(bars.last, 96);
      expect(bars.sublist(0, RecordedVoice.bars ~/ 2).every((b) => b < 20),
          isTrue);
      expect(bars.sublist(RecordedVoice.bars ~/ 2).every((b) => b > 80), isTrue);
    });

    test('a recording nothing could be measured from still draws bars', () {
      final List<int> bars = RecordedVoice.resample(const <int>[]);

      expect(bars.length, RecordedVoice.bars);
      expect(bars.every((level) => level > 0), isTrue);
    });
  });

  group('a voice message on a thread', () {
    test('carries its length and its shape through Firestore', () {
      final ChatMessageModel sent = _voice(ms: 12500, wave: const [5, 60, 99]);
      final ChatMessageModel read = ChatMessageModel.fromMap('v1', <String, dynamic>{
        ...sent.toMap(),
        'createdAt': null,
      });

      expect(read.hasAudio, isTrue);
      expect(read.audioMs, 12500);
      expect(read.audioDuration, const Duration(milliseconds: 12500));
      expect(read.audioWave, const <int>[5, 60, 99]);
    });

    test('says what it is where there are no words to quote', () {
      // Translations are not loaded in a unit test, so the key stands in for
      // the sentence — what matters is that a voice note is not quoted as an
      // empty message.
      expect(_voice().preview, startsWith('🎤 '));
      expect(_voice(deleted: true).preview, isNot(startsWith('🎤 ')));
    });

    test('a message that is not one has nothing to play', () {
      final ChatMessageModel text = ChatMessageModel(
        id: 't1',
        text: 'got the rice',
        senderName: 'Member',
        senderPhone: '01711111111',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(text.hasAudio, isFalse);
      expect(text.audioDuration, Duration.zero);
    });

    test('the chat list says a voice note arrived rather than nothing', () {
      const DirectThread spoken = DirectThread(
        id: 'a__b',
        lastText: '',
        lastSenderPhone: 'a',
        lastHasAudio: true,
      );
      const DirectThread silent = DirectThread(
        id: 'a__b',
        lastText: '',
        lastSenderPhone: 'a',
      );

      expect(spoken.preview, startsWith('🎤 '));
      expect(silent.preview, '');
    });
  });

  group('a voice message on its way out', () {
    OutgoingMessage queued() => OutgoingMessage(
          localId: 'q1',
          text: '',
          audioPath: '/tmp/voice/q1.m4a',
          audioExtension: '.m4a',
          audioMs: 4200,
          audioWave: const <int>[9, 70, 30],
          senderName: 'Member',
          senderPhone: '01711111111',
          pushTitle: 'Member',
          pushBody: 'voice',
          queuedAt: DateTime(2026, 1, 1),
        );

    test('survives the disk it waits on', () {
      final OutgoingMessage read =
          OutgoingMessage.fromJson(queued().toJson());

      expect(read.hasAudio, isTrue);
      expect(read.audioExtension, '.m4a');
      expect(read.audioDuration, const Duration(milliseconds: 4200));
      expect(read.audioWave, const <int>[9, 70, 30]);
    });

    test('is not mistaken for a picture', () {
      expect(queued().hasImage, isFalse);
      expect(queued().isInAlbum, isFalse);
    });
  });
}
