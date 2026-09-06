import '../model/call_model.dart';

/// The signalling between two phones setting up a call.
///
/// Everything here is small and short-lived: an offer, an answer, and the
/// network routes each end can be reached on. Once the two are connected the
/// audio goes directly between them and none of this is read again.
abstract class CallRepository {
  /// Writes a new call and answers its id. The offer is already on it — see
  /// `CallSession.offer` — so the phone at the other end never rings for a
  /// call it cannot yet answer.
  Future<String> create(CallSession call);

  /// One call, live. Both ends watch this: it carries the answer, and it
  /// carries the moment either of them hangs up.
  Stream<CallSession?> watch(String callId);

  /// A call ringing for [myPhone] right now, live — how a phone learns
  /// somebody is calling it while the app is open.
  ///
  /// Null whenever there is none. Equality filters only, so it needs no
  /// index of its own.
  Stream<CallSession?> watchIncoming(String myPhone);

  /// The callee's reply. Written with the status in one go: an answer that
  /// lands without the status, or the other way round, is a call one end
  /// thinks is connected and the other thinks is still ringing.
  Future<void> answerCall(String callId, Map<String, dynamic> answer);

  /// Ends a call, whatever it was doing. [by] is the phone that did it, so
  /// the other end can tell "they hung up" from "you did".
  Future<void> finish(String callId, CallStatus status, String by);

  /// One network route this end can be reached on.
  ///
  /// Posted as they are found rather than all at once: a call connects on the
  /// first pair that works, and waiting for the full list would add seconds
  /// to every one of them.
  Future<void> addCandidate(
    String callId, {
    required bool fromCaller,
    required Map<String, dynamic> candidate,
  });

  /// The other end's routes, as they arrive.
  Stream<List<Map<String, dynamic>>> candidates(
    String callId, {
    required bool fromCaller,
  });

  /// Clears the call and the routes under it once it is over.
  ///
  /// Best effort: nothing depends on it. What is left of the call is the line
  /// written into the thread, not this.
  Future<void> discard(String callId);
}
