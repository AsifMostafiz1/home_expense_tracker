import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// What the device can reach right now.
enum ConnectionStatus {
  online,

  /// No network interface at all — airplane mode, Wi‑Fi and data both off.
  noNetwork,

  /// A network is up but nothing answers on it: a data plan that has run out,
  /// a captive portal, a router with no uplink. Looks "connected" to the OS.
  noInternet,
}

/// Whether the device can actually reach the internet — and, when it cannot,
/// why.
///
/// Two inputs, combined. `connectivity_plus` says whether a network interface
/// is up, and says so instantly; but a phone whose data has run out still has
/// its interface up, so that alone would call it online. A small HTTP probe
/// (Google's `generate_204`, the same check Android itself uses) settles
/// whether anything answers on that network. The probe runs the moment an
/// interface comes up, on a slow tick while the app is in front, faster while
/// unreachable so a recovery is noticed quickly, and never while the app is
/// in the background. A server that answers anywhere in the app is proof
/// enough on its own — see [reportReachable].
///
/// Still only a hint: it decides whether a save bothers waiting for the
/// server's acknowledgement, what the app bar shows, and when queued receipts
/// get another attempt. Nothing that talks to a server relies on it alone.
class ConnectivityService extends GetxController
    with WidgetsBindingObserver
    implements GetxService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Answers 204 with no body — cheap enough to ask every half minute.
  static final Uri _probeUri =
      Uri.parse('https://clients3.google.com/generate_204');
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _probeIntervalOnline = Duration(seconds: 30);
  static const Duration _probeIntervalOffline = Duration(seconds: 10);

  Timer? _probeTimer;
  bool _probing = false;
  bool _inForeground = true;

  // Optimistic until the first check lands: a wrong "offline" would make the
  // very first save skip its acknowledgement for no reason.
  bool _hasNetwork = true;
  bool _reachable = true;
  ConnectionStatus _published = ConnectionStatus.online;

  ConnectionStatus get status {
    if (!_hasNetwork) return ConnectionStatus.noNetwork;
    if (!_reachable) return ConnectionStatus.noInternet;
    return ConnectionStatus.online;
  }

  bool get isOnline => _hasNetwork && _reachable;
  bool get isOffline => !isOnline;

  /// Whether there is an interface up at all — Wi‑Fi or data, whether or not
  /// the probe found anything on the other end.
  ///
  /// The difference from [isOnline] matters to anything about to *send*
  /// something. [isOnline] carries the verdict of a probe against one host,
  /// which can be wrong in both directions: a slow or blocked
  /// `generate_204` reads as "no internet" on a connection that would have
  /// carried the write perfectly well. With no interface at all there is
  /// genuinely nothing to try; with one, the server being written to is a
  /// better authority than the probe, so try and let it answer.
  bool get hasNetwork => _hasNetwork;

  final StreamController<bool> _transitions =
      StreamController<bool>.broadcast();

  /// `true` when the internet becomes reachable, `false` when it stops being
  /// — one event per change, never the same state twice in a row. A switch
  /// between the two offline reasons is not a transition.
  Stream<bool> get onStatusChanged => _transitions.stream;

  /// Fires once each time the device comes back online.
  Stream<bool> get onOnline => onStatusChanged.where((online) => online);

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _applyNetwork(await _connectivity.checkConnectivity());
    } catch (e) {
      debugPrint('Connectivity: initial check failed — $e');
    }
    _subscription = _connectivity.onConnectivityChanged.listen(
      _applyNetwork,
      onError: (Object e) => debugPrint('Connectivity: stream error — $e'),
    );
    await probe();
  }

  void _applyNetwork(List<ConnectivityResult> results) {
    _hasNetwork = results.any((result) => result != ConnectivityResult.none);
    _publish();
    // An interface just came up (or changed — Wi‑Fi to data, say): whether
    // it goes anywhere is a separate question, asked right away.
    if (_hasNetwork) probe();
  }

  /// Asks the network whether anything answers. Safe to call any time; calls
  /// that arrive while one is in flight are dropped.
  Future<void> probe() async {
    if (!_hasNetwork || _probing) return;

    // In a browser the probe would be a cross-origin request that
    // `generate_204` does not answer with CORS headers, so it would read as
    // "no internet" on a connection that is fine. The browser's own signal
    // (what connectivity_plus reports here) is the best answer available.
    if (kIsWeb) {
      _reachable = true;
      _publish();
      return;
    }

    _probing = true;
    try {
      final http.Response response =
          await http.get(_probeUri).timeout(_probeTimeout);
      _reachable = response.statusCode == 204;
    } catch (e) {
      // Timeout, refused connection, DNS failure, a captive portal that
      // cannot complete the TLS handshake — all the same answer.
      _reachable = false;
    } finally {
      _probing = false;
    }
    _publish();
    _scheduleProbe();
  }

  /// A server somewhere in the app just answered — proof the internet is
  /// reachable, without waiting for the next probe to say so.
  void reportReachable() {
    if (_reachable) return;
    _reachable = true;
    _publish();
    _scheduleProbe();
  }

  void _scheduleProbe() {
    _probeTimer?.cancel();
    if (!_inForeground) return;
    _probeTimer = Timer(
      isOnline ? _probeIntervalOnline : _probeIntervalOffline,
      probe,
    );
  }

  /// Pushes the current [status] out if it differs from the last one shown.
  void _publish() {
    final ConnectionStatus next = status;
    if (next == _published) return;

    final bool wasOnline = _published == ConnectionStatus.online;
    _published = next;
    debugPrint('Connectivity: $next');
    update();
    if (wasOnline != isOnline) _transitions.add(isOnline);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground) {
      // Back from the background: things may well have changed meanwhile.
      probe();
    } else {
      // No point probing on the user's battery while nobody is looking.
      _probeTimer?.cancel();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _probeTimer?.cancel();
    _transitions.close();
    super.onClose();
  }
}
