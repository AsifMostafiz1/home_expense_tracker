import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/call/model/call_model.dart';
import 'package:demo_project/presentation/chat/model/chat_message_model.dart';
import 'package:demo_project/presentation/chat/model/chat_thread_model.dart';

const String _me = '01711111111';
const String _them = '01822222222';

CallSession _call({
  CallStatus status = CallStatus.ringing,
  String caller = _me,
  String callee = _them,
  DateTime? answeredAt,
  DateTime? endedAt,
}) =>
    CallSession(
      id: 'c1',
      callerPhone: caller,
      callerName: 'Caller',
      calleePhone: callee,
      calleeName: 'Callee',
      calleeImage: 'https://faces/callee.jpg',
      conversationId: '${_me}__$_them',
      status: status,
      answeredAt: answeredAt,
      endedAt: endedAt,
    );

void main() {
  group('a call, from each end', () {
    test('the peer is whoever is at the other end of it', () {
      final CallSession outgoing = _call();

      expect(outgoing.isCaller(_me), isTrue);
      expect(outgoing.peerPhoneFor(_me), _them);
      expect(outgoing.peerNameFor(_me), 'Callee');
      expect(outgoing.peerImageFor(_me), 'https://faces/callee.jpg');

      // The same document, read on the other phone.
      expect(outgoing.isCaller(_them), isFalse);
      expect(outgoing.peerPhoneFor(_them), _me);
      expect(outgoing.peerNameFor(_them), 'Caller');
    });

    test('only ringing and accepted are calls that are still happening', () {
      expect(_call(status: CallStatus.ringing).isOver, isFalse);
      expect(_call(status: CallStatus.accepted).isOver, isFalse);
      expect(_call(status: CallStatus.declined).isOver, isTrue);
      expect(_call(status: CallStatus.missed).isOver, isTrue);
      expect(_call(status: CallStatus.ended).isOver, isTrue);
    });

    test('how long they talked is measured from the answer', () {
      final DateTime rang = DateTime(2026, 5, 1, 9, 0, 0);
      final CallSession call = _call(
        status: CallStatus.ended,
        answeredAt: rang.add(const Duration(seconds: 12)),
        endedAt: rang.add(const Duration(seconds: 145)),
      );

      expect(call.talkedFor, const Duration(seconds: 133));
    });

    test('a call nobody answered was never a conversation', () {
      expect(_call(status: CallStatus.missed).talkedFor, isNull);
    });

    test('a status this build does not know is not a call still ringing', () {
      expect(CallSession.statusFrom('something_newer'), CallStatus.ended);
      expect(CallSession.statusFrom(null), CallStatus.ended);
      expect(CallSession.statusFrom('accepted'), CallStatus.accepted);
    });

    test('it survives the trip through Firestore', () {
      final CallSession sent = _call(status: CallStatus.ringing);
      final CallSession read = CallSession.fromMap('c1', <String, dynamic>{
        ...sent.toMap(),
        // The server stamps this one; toMap leaves a sentinel in its place.
        'created_at': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'offer': <String, dynamic>{'sdp': 'v=0', 'type': 'offer'},
      });

      expect(read.callerPhone, _me);
      expect(read.calleePhone, _them);
      expect(read.status, CallStatus.ringing);
      expect(read.offer?['type'], 'offer');
      expect(read.conversationId, '${_me}__$_them');
    });
  });

  group('what a call leaves in the thread', () {
    ChatMessageModel log(String outcome, {int seconds = 0}) => ChatMessageModel(
          id: 'm1',
          text: '',
          senderName: 'Caller',
          senderPhone: _me,
          createdAt: DateTime(2026, 5, 1),
          callOutcome: outcome,
          callSeconds: seconds,
        );

    test('a call log is not mistaken for a message somebody wrote', () {
      expect(log('answered', seconds: 30).isCallLog, isTrue);
      expect(log('answered', seconds: 30).hasAudio, isFalse);
      expect(log('answered', seconds: 30).hasImage, isFalse);

      final ChatMessageModel typed = ChatMessageModel(
        id: 'm2',
        text: 'call me back',
        senderName: 'Caller',
        senderPhone: _me,
        createdAt: DateTime(2026, 5, 1),
      );
      expect(typed.isCallLog, isFalse);
    });

    test('an answered call carries how long it ran', () {
      expect(log('answered', seconds: 133).callDuration,
          const Duration(seconds: 133));
      // Translations are not loaded in a unit test, so the key stands in for
      // the words — the clock next to it is the part worth checking.
      expect(log('answered', seconds: 133).callLine, contains('2:13'));
      expect(log('answered', seconds: 7).callLine, contains('0:07'));
    });

    test('a missed one says so instead of showing a clock', () {
      expect(log('missed').callLine, isNot(contains(':')));
      expect(log('declined').callLine, isNot(contains(':')));
    });

    test('it round-trips through Firestore', () {
      final ChatMessageModel read =
          ChatMessageModel.fromMap('m1', <String, dynamic>{
        ...log('missed').toMap(),
        'createdAt': null,
      });

      expect(read.isCallLog, isTrue);
      expect(read.callOutcome, 'missed');
      expect(read.preview, startsWith('📞 '));
    });

    test('the chat list says a call happened rather than showing nothing', () {
      const DirectThread missed = DirectThread(
        id: 'a__b',
        lastText: '',
        lastSenderPhone: 'a',
        lastCall: 'missed',
      );

      expect(missed.preview, startsWith('📞 '));
    });
  });
}
