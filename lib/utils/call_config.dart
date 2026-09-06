/// How two phones find each other for a call.
///
/// A call's audio never touches this app's servers: once the two ends have
/// swapped notes through Firestore, the sound goes directly between them.
/// What that swap needs is a list of servers that can tell a phone how it
/// looks from the outside, and — when the two cannot reach each other at all
/// — one willing to sit in the middle and pass the audio along.
class CallConfig {
  /// STUN tells a phone its own public address; TURN relays the call when the
  /// two ends cannot open a path to each other.
  ///
  /// The public STUN servers below are enough on most home and office
  /// networks. They are **not** enough on every mobile network: a carrier
  /// behind a symmetric NAT gives a phone a different public port for every
  /// destination, which is the one case STUN cannot solve, and those calls
  /// connect only through a TURN relay.
  ///
  /// So: add one. A TURN server is the difference between "works on wifi" and
  /// "works", and there is nowhere else in the app to put it — this list is
  /// the whole configuration. Any provider will do (Metered, Twilio, Xirsys,
  /// or coturn on a VPS); paste the entry they give you next to the STUN ones:
  ///
  /// ```dart
  /// {
  ///   'urls': 'turn:your-host:3478',
  ///   'username': '…',
  ///   'credential': '…',
  /// },
  /// ```
  static const List<Map<String, dynamic>> iceServers = <Map<String, dynamic>>[
    {
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  /// Whether anything here can relay a call that cannot go direct. Read only
  /// to warn, once, in the debug log — a call that fails for want of a relay
  /// otherwise looks like a bug in the app.
  static bool get hasRelay => iceServers.any((Map<String, dynamic> server) {
        final Object? urls = server['urls'];
        final List<String> list = urls is String
            ? <String>[urls]
            : (urls as List<dynamic>? ?? const <dynamic>[]).cast<String>();
        return list.any((String url) => url.startsWith('turn'));
      });

  /// How long a phone rings before the call is written off as missed. Long
  /// enough to get a phone out of a pocket, short enough that a call nobody
  /// is near does not ring out for a minute.
  static const Duration ringFor = Duration(seconds: 45);

  /// The peer connection's own configuration. Unified plan is the only
  /// semantics current browsers accept, and the bundle policy keeps one
  /// transport for the call rather than one per track.
  static Map<String, dynamic> get peerConfig => <String, dynamic>{
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      };
}
