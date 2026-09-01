import 'package:cloud_firestore/cloud_firestore.dart';

/// Somebody with the composer open in a thread.
///
/// One document per member, keyed by their phone, written by the device doing
/// the typing and read by everybody else in the thread. A document each
/// rather than one shared document because two people typing at once would
/// otherwise be writing to the same document several times a second.
class TypingStatus {
  final String phone;

  /// Whose name the header says. Carried on the flag itself so a reader does
  /// not have to look the member up to draw one line.
  final String name;

  final bool typing;

  /// When the flag was last re-stamped, by the server's clock. Null while the
  /// write is still on its way out of the device that made it.
  final DateTime? at;

  const TypingStatus({
    required this.phone,
    this.name = '',
    this.typing = false,
    this.at,
  });

  /// How long a raised flag stands on its own.
  ///
  /// The writer re-stamps it every few seconds and lowers it the moment it
  /// stops — an idle pause, a send, leaving the screen, the app going away.
  /// This only covers the case where none of that happened: the app was
  /// killed mid-word, the battery went, the connection dropped. Generous on
  /// purpose, because a server stamp is being read against this device's
  /// clock and a tight window would blink the indicator on and off between
  /// two phones that disagree by a few seconds.
  static const Duration window = Duration(seconds: 20);

  bool get isActive {
    if (!typing) return false;
    final DateTime? stamp = at;
    // No stamp yet means the write is still in flight — newer than any
    // window rather than older than one.
    if (stamp == null) return true;
    return DateTime.now().difference(stamp) < window;
  }

  factory TypingStatus.fromMap(String id, Map<String, dynamic> map) {
    return TypingStatus(
      // The document id is the phone; the field only stands in for it if a
      // document is ever written without one.
      phone: (map['phone'] ?? id).toString(),
      name: (map['name'] ?? '').toString(),
      typing: map['typing'] == true,
      at: (map['at'] as Timestamp?)?.toDate(),
    );
  }
}
