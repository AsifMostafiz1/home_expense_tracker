import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a call has got to. The one field both phones watch, and the only
/// thing either of them needs to agree on.
enum CallStatus {
  /// Written by the caller. The callee's phone is ringing.
  ringing,

  /// The callee picked up. From here the two are talking directly and
  /// Firestore has nothing left to do.
  accepted,

  /// The callee said no.
  declined,

  /// Somebody hung up. [CallSession.endedBy] says who.
  ended,

  /// Nobody picked up before the ring ran out — see `CallConfig.ringFor`.
  missed,
}

/// One call, as the two ends see it.
///
/// A document rather than a message: a call is not part of the conversation,
/// it is a thing happening right now that both phones have to agree about
/// within a second or two. What is left of it afterwards — "missed", "2:14" —
/// *is* written into the thread, once, when it ends.
class CallSession {
  final String id;

  final String callerPhone;
  final String callerName;
  final String? callerImage;

  final String calleePhone;
  final String calleeName;
  final String? calleeImage;

  /// The direct thread these two share, so the call log knows where to go.
  final String conversationId;

  final CallStatus status;

  /// The caller's opening description of what it can send and receive. Set
  /// when the document is created, so the callee never has to wait for it.
  final Map<String, dynamic>? offer;

  /// The callee's reply to it, written on answering.
  final Map<String, dynamic>? answer;

  final DateTime? createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// Whose phone ended it. Read to tell "they hung up" from "you did".
  final String? endedBy;

  const CallSession({
    required this.id,
    required this.callerPhone,
    required this.callerName,
    this.callerImage,
    required this.calleePhone,
    required this.calleeName,
    this.calleeImage,
    required this.conversationId,
    this.status = CallStatus.ringing,
    this.offer,
    this.answer,
    this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.endedBy,
  });

  bool get isOver =>
      status == CallStatus.ended ||
      status == CallStatus.declined ||
      status == CallStatus.missed;

  bool isCaller(String phone) => callerPhone == phone;

  /// The other person, from [phone]'s side of it.
  String peerPhoneFor(String phone) =>
      isCaller(phone) ? calleePhone : callerPhone;

  String peerNameFor(String phone) => isCaller(phone) ? calleeName : callerName;

  String? peerImageFor(String phone) =>
      isCaller(phone) ? calleeImage : callerImage;

  /// How long the two were actually connected, or null for a call that never
  /// was. Measured from the answer, not from the ring.
  Duration? get talkedFor {
    final DateTime? from = answeredAt;
    final DateTime? to = endedAt;
    if (from == null || to == null) return null;
    final Duration ran = to.difference(from);
    return ran.isNegative ? Duration.zero : ran;
  }

  CallSession copyWith({CallStatus? status}) => CallSession(
        id: id,
        callerPhone: callerPhone,
        callerName: callerName,
        callerImage: callerImage,
        calleePhone: calleePhone,
        calleeName: calleeName,
        calleeImage: calleeImage,
        conversationId: conversationId,
        status: status ?? this.status,
        offer: offer,
        answer: answer,
        createdAt: createdAt,
        answeredAt: answeredAt,
        endedAt: endedAt,
        endedBy: endedBy,
      );

  factory CallSession.fromMap(String id, Map<String, dynamic> map) {
    return CallSession(
      id: id,
      callerPhone: (map['caller_phone'] ?? '').toString(),
      callerName: (map['caller_name'] ?? '').toString(),
      callerImage: _orNull(map['caller_image']),
      calleePhone: (map['callee_phone'] ?? '').toString(),
      calleeName: (map['callee_name'] ?? '').toString(),
      calleeImage: _orNull(map['callee_image']),
      conversationId: (map['conversation_id'] ?? '').toString(),
      status: statusFrom(map['status']),
      offer: map['offer'] == null
          ? null
          : Map<String, dynamic>.from(map['offer'] as Map),
      answer: map['answer'] == null
          ? null
          : Map<String, dynamic>.from(map['answer'] as Map),
      createdAt: (map['created_at'] as Timestamp?)?.toDate(),
      answeredAt: (map['answered_at'] as Timestamp?)?.toDate(),
      endedAt: (map['ended_at'] as Timestamp?)?.toDate(),
      endedBy: _orNull(map['ended_by']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'caller_phone': callerPhone,
        'caller_name': callerName,
        if (callerImage != null) 'caller_image': callerImage,
        'callee_phone': calleePhone,
        'callee_name': calleeName,
        if (calleeImage != null) 'callee_image': calleeImage,
        'conversation_id': conversationId,
        'participants': <String>[callerPhone, calleePhone]..sort(),
        'status': status.name,
        if (offer != null) 'offer': offer,
        'created_at': FieldValue.serverTimestamp(),
      };

  /// An unknown status — a build that knows something this one does not —
  /// reads as ended rather than as a call still ringing.
  static CallStatus statusFrom(Object? raw) {
    final String name = (raw ?? '').toString();
    for (final CallStatus status in CallStatus.values) {
      if (status.name == name) return status;
    }
    return CallStatus.ended;
  }

  static String? _orNull(Object? value) {
    final String text = (value ?? '').toString();
    return text.isEmpty ? null : text;
  }
}
