import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../utils/app_constant.dart';
import '../model/call_model.dart';
import 'call_repository.dart';

class CallRepositoryImpl implements CallRepository {
  final FirebaseFirestore _firestore;

  CallRepositoryImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection(AppConstant.collectionCalls);

  CollectionReference<Map<String, dynamic>> _candidates(
    String callId, {
    required bool fromCaller,
  }) =>
      _calls.doc(callId).collection(fromCaller
          ? AppConstant.subcollectionCallerCandidates
          : AppConstant.subcollectionCalleeCandidates);

  @override
  Future<String> create(CallSession call) async {
    final DocumentReference<Map<String, dynamic>> doc = _calls.doc();
    // Not queued behind Firestore's offline cache: a call written on a device
    // with no connection is a phone that never rings, and the caller has to
    // be told that now rather than sit watching it ring for nobody.
    await doc.set(call.toMap());
    return doc.id;
  }

  @override
  Stream<CallSession?> watch(String callId) {
    return _calls.doc(callId).snapshots().map(
          (DocumentSnapshot<Map<String, dynamic>> doc) => doc.exists
              ? CallSession.fromMap(doc.id, doc.data() ?? const {})
              : null,
        );
  }

  @override
  Stream<CallSession?> watchIncoming(String myPhone) {
    return _calls
        .where('callee_phone', isEqualTo: myPhone)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (snapshot.docs.isEmpty) return null;

      // More than one only if somebody was called twice while their phone was
      // off; the newest is the one actually ringing.
      final List<CallSession> ringing = snapshot.docs
          .map((doc) => CallSession.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((CallSession a, CallSession b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

      // A call whose caller gave up while this device was offline is not
      // worth ringing for — the server stamp says how old it is, and anything
      // past the ring window has been over for a while.
      final CallSession newest = ringing.first;
      final DateTime? at = newest.createdAt;
      if (at != null &&
          DateTime.now().difference(at) > const Duration(minutes: 2)) {
        return null;
      }
      return newest;
    });
  }

  @override
  Future<void> answerCall(String callId, Map<String, dynamic> answer) {
    return _calls.doc(callId).update(<String, dynamic>{
      'answer': answer,
      'status': CallStatus.accepted.name,
      'answered_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> finish(String callId, CallStatus status, String by) async {
    try {
      await _calls.doc(callId).update(<String, dynamic>{
        'status': status.name,
        'ended_at': FieldValue.serverTimestamp(),
        'ended_by': by,
      });
    } catch (e) {
      // The call may already be gone — the other end discarded it. Hanging up
      // must not fail over that.
      debugPrint('Call: could not mark $callId as ${status.name} — $e');
    }
  }

  @override
  Future<void> addCandidate(
    String callId, {
    required bool fromCaller,
    required Map<String, dynamic> candidate,
  }) {
    return _candidates(callId, fromCaller: fromCaller).add(candidate);
  }

  @override
  Stream<List<Map<String, dynamic>>> candidates(
    String callId, {
    required bool fromCaller,
  }) {
    return _candidates(callId, fromCaller: fromCaller).snapshots().map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot
              .docChanges
              // Only the new ones: a candidate handed to the connection twice
              // is an error it logs and nothing more, but the list grows on
              // every snapshot and re-adding all of it every time is waste.
              .where((change) => change.type == DocumentChangeType.added)
              .map((change) => change.doc.data() ?? const <String, dynamic>{})
              .toList(),
        );
  }

  @override
  Future<void> discard(String callId) async {
    try {
      final DocumentReference<Map<String, dynamic>> doc = _calls.doc(callId);
      for (final bool fromCaller in const <bool>[true, false]) {
        final QuerySnapshot<Map<String, dynamic>> found =
            await _candidates(callId, fromCaller: fromCaller).get();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> candidate
            in found.docs) {
          await candidate.reference.delete();
        }
      }
      await doc.delete();
    } catch (e) {
      debugPrint('Call: could not clear $callId — $e');
    }
  }
}
