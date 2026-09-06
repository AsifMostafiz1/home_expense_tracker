import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// GetX defines a `navigator` of its own, so the WebRTC one is named.
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc show navigator;
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/widgets/custom_snackbar.dart';
import '../presentation/call/model/call_model.dart';
import '../presentation/call/repository/call_repository.dart';
import '../presentation/call/view/call_screen.dart';
import '../utils/app_constant.dart';
import '../utils/app_enums.dart';
import '../utils/call_config.dart';
import 'push_notification_service.dart';

/// Where this device is in a call.
enum CallPhase {
  /// No call. Everything below is off.
  idle,

  /// This phone is calling somebody, and their phone is ringing.
  dialling,

  /// Somebody is calling this phone.
  incoming,

  /// Answered, and the two ends are finding each other.
  connecting,

  /// Talking.
  connected,

  /// Over. Held for a moment so the screen can say how it ended.
  ended,
}

/// Voice calls between two members.
///
/// The audio never passes through this app's servers. Firestore is used only
/// to introduce the two phones — an offer, an answer, and the network routes
/// each of them can be reached on — after which the sound goes directly
/// between the devices. See `CallRepository` for the introduction and
/// `CallConfig` for what makes it possible on a mobile network.
///
/// One call at a time, app-wide, which is why this is a service rather than a
/// controller: a call has to outlive the screen it was started from, survive
/// the thread being closed, and ring on whatever the member happens to be
/// looking at.
class CallService extends GetxController implements GetxService {
  final CallRepository _repository;

  CallService({required CallRepository repository}) : _repository = repository;

  // ------------------------------------------------------------ what is on

  CallPhase phase = CallPhase.idle;
  CallSession? session;

  bool get isBusy => phase != CallPhase.idle && phase != CallPhase.ended;

  /// How the last call finished, for the line the screen shows on the way
  /// out — `declined`, `missed`, `ended`, `failed`, `unanswered`.
  String endedNote = '';

  bool muted = false;
  bool speakerOn = false;

  /// How long the two have been talking. From the answer, not from the ring.
  Duration talkTime = Duration.zero;

  String get myPhone => _myPhone;

  // ------------------------------------------------------------- internals

  String _myPhone = '';
  String _myName = '';
  String? _myImage;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;

  /// Only on web, and only so the browser has something to play the incoming
  /// audio through — a phone plays a remote track without being asked.
  RTCVideoRenderer? _remoteRenderer;

  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;

  StreamSubscription<CallSession?>? _incomingWatch;
  StreamSubscription<CallSession?>? _callWatch;
  StreamSubscription<List<Map<String, dynamic>>>? _candidateWatch;

  Timer? _ringTimeout;
  Timer? _talkTicker;

  /// Started when the connection drops, cancelled if it comes back. WebRTC
  /// recovers from a short break — a lift, a handover between towers — on its
  /// own, so a call is only written off once it has stayed down.
  Timer? _dropTimeout;
  Timer? _ringHaptics;
  DateTime? _talkingSince;

  /// Routes found before the call document existed to write them to. Only the
  /// caller ever has any: it starts gathering the moment the offer is made,
  /// which is a round trip before Firestore has an id for them.
  final List<Map<String, dynamic>> _pendingCandidates = <Map<String, dynamic>>[];

  /// Whether the call screen is on top. So a rebuild, a second ring or a
  /// notification tap cannot stack two of them.
  bool _screenOpen = false;

  bool get _amCaller => session?.isCaller(_myPhone) ?? false;

  // ------------------------------------------------------------------ life

  /// Starts listening for calls to this member. Safe to call again — signing
  /// in re-runs the initial binding on a service that is already registered.
  Future<void> init() async {
    await _loadMe();
    if (_myPhone.isEmpty) return;

    if (!CallConfig.hasRelay) {
      debugPrint(
        'Call: no TURN server configured. Calls will connect on most wifi '
        'but can fail on mobile networks — see CallConfig.iceServers.',
      );
    }

    _incomingWatch?.cancel();
    _incomingWatch = _repository.watchIncoming(_myPhone).listen(
      _onIncoming,
      onError: (Object e) => debugPrint('Call: incoming watch failed — $e'),
    );
  }

  Future<void> _loadMe() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _myPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    _myName = prefs.getString(AppConstant.keyUserName) ?? '';
    _myImage = prefs.getString(AppConstant.keyUserProfileImage);
  }

  // -------------------------------------------------------------- outgoing

  /// Calls [peerPhone]. Returns false when the call could not be started,
  /// having already said why.
  Future<bool> call({
    required String peerPhone,
    required String peerName,
    String? peerImage,
    required String conversationId,
  }) async {
    if (isBusy) return false;
    if (_myPhone.isEmpty) await _loadMe();
    if (_myPhone.isEmpty || peerPhone.isEmpty || peerPhone == _myPhone) {
      return false;
    }
    if (!await _askForMicrophone()) return false;

    phase = CallPhase.dialling;
    endedNote = '';
    muted = false;
    speakerOn = false;
    talkTime = Duration.zero;
    // Something to show while the offer is being made: the screen is up
    // before Firestore has an id, and it needs a name and a face.
    session = CallSession(
      id: '',
      callerPhone: _myPhone,
      callerName: _myName,
      callerImage: _myImage,
      calleePhone: peerPhone,
      calleeName: peerName,
      calleeImage: peerImage,
      conversationId: conversationId,
    );
    update();
    _openScreen();

    try {
      await _openPeer(asCaller: true);

      final RTCSessionDescription offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);

      final CallSession outgoing = CallSession(
        id: '',
        callerPhone: _myPhone,
        callerName: _myName,
        callerImage: _myImage,
        calleePhone: peerPhone,
        calleeName: peerName,
        calleeImage: peerImage,
        conversationId: conversationId,
        offer: <String, dynamic>{'sdp': offer.sdp, 'type': offer.type},
      );
      final String id = await _repository.create(outgoing);

      // Cancelled while the offer was being written.
      if (phase != CallPhase.dialling) {
        await _repository.finish(id, CallStatus.ended, _myPhone);
        return false;
      }

      session = CallSession(
        id: id,
        callerPhone: outgoing.callerPhone,
        callerName: outgoing.callerName,
        callerImage: outgoing.callerImage,
        calleePhone: outgoing.calleePhone,
        calleeName: outgoing.calleeName,
        calleeImage: outgoing.calleeImage,
        conversationId: conversationId,
        offer: outgoing.offer,
      );
      update();

      await _flushCandidates();
      _watchCall(id);
      _listenForCandidates(id, fromCaller: false);
      _notifyPeer(outgoing);

      _ringTimeout = Timer(CallConfig.ringFor, () {
        if (phase == CallPhase.dialling) {
          _finish(CallStatus.missed, note: 'unanswered');
        }
      });
      return true;
    } catch (e) {
      debugPrint('Call: could not place the call — $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'call_failed'.tr);
      await _finish(CallStatus.ended, note: 'failed');
      return false;
    }
  }

  // -------------------------------------------------------------- incoming

  void _onIncoming(CallSession? incoming) {
    if (incoming == null) return;
    // Already in one. The caller is told the same way a declined call is —
    // there is nothing useful in ringing over a conversation in progress.
    if (isBusy) {
      if (session?.id != incoming.id) {
        _repository.finish(incoming.id, CallStatus.declined, _myPhone);
      }
      return;
    }
    if (incoming.offer == null) return;

    session = incoming;
    phase = CallPhase.incoming;
    endedNote = '';
    muted = false;
    speakerOn = false;
    talkTime = Duration.zero;
    update();

    _watchCall(incoming.id);
    _startRingHaptics();
    _openScreen();
  }

  /// Picks up.
  Future<void> accept() async {
    final CallSession? incoming = session;
    if (incoming == null || phase != CallPhase.incoming) return;
    _stopRingHaptics();

    if (!await _askForMicrophone()) {
      await _finish(CallStatus.declined, note: 'declined');
      return;
    }

    phase = CallPhase.connecting;
    update();

    try {
      await _openPeer(asCaller: false);

      final Map<String, dynamic> offer = incoming.offer!;
      await _peer!.setRemoteDescription(
        RTCSessionDescription(
            offer['sdp'] as String?, offer['type'] as String?),
      );

      final RTCSessionDescription answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);

      await _repository.answerCall(
        incoming.id,
        <String, dynamic>{'sdp': answer.sdp, 'type': answer.type},
      );

      await _flushCandidates();
      _listenForCandidates(incoming.id, fromCaller: true);
    } catch (e) {
      debugPrint('Call: could not answer — $e');
      await _finish(CallStatus.ended, note: 'failed');
    }
  }

  /// Says no to a call that is ringing.
  Future<void> decline() async {
    _stopRingHaptics();
    await _finish(CallStatus.declined, note: 'declined');
  }

  /// Ends a call — dialling, connecting or connected.
  Future<void> hangUp() async {
    await _finish(CallStatus.ended, note: 'ended');
  }

  // ------------------------------------------------------------- in a call

  void toggleMute() {
    final MediaStream? local = _localStream;
    if (local == null) return;
    muted = !muted;
    for (final MediaStreamTrack track in local.getAudioTracks()) {
      track.enabled = !muted;
    }
    update();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    update();
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (e) {
      debugPrint('Call: could not switch the speaker — $e');
    }
  }

  // ------------------------------------------------------------ the plumbing

  Future<bool> _askForMicrophone() async {
    try {
      // Asked for here rather than left to the media call, so a refusal is a
      // sentence the member can act on instead of a call that fails.
      final PermissionStatus status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) return true;
      CustomSnackbar.show(
        type: SnackbarType.warning,
        message: 'mic_permission_needed'.tr,
      );
      return false;
    } catch (e) {
      debugPrint('Call: could not ask for the microphone — $e');
      // A platform that cannot be asked is one where the media call will ask
      // for itself; do not block the call over it.
      return true;
    }
  }

  Future<void> _openPeer({required bool asCaller}) async {
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia(
      <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      },
    );

    final RTCPeerConnection peer =
        await createPeerConnection(CallConfig.peerConfig);
    _peer = peer;

    for (final MediaStreamTrack track in _localStream!.getTracks()) {
      await peer.addTrack(track, _localStream!);
    }

    // Attached before anything can produce one: the first routes are found
    // the moment the local description is set, and a handler added after that
    // misses them.
    peer.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      _postCandidate(<String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    peer.onTrack = (RTCTrackEvent event) async {
      if (event.streams.isEmpty) return;
      // A phone plays a remote audio track on its own. A browser needs an
      // element to play it through, which is what the renderer is.
      if (kIsWeb) {
        final RTCVideoRenderer renderer = _remoteRenderer ?? RTCVideoRenderer();
        if (_remoteRenderer == null) {
          await renderer.initialize();
          _remoteRenderer = renderer;
        }
        renderer.srcObject = event.streams.first;
        update();
      }
    };

    peer.onConnectionState = (RTCPeerConnectionState state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _dropTimeout?.cancel();
          _dropTimeout = null;
          _onConnected();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // The other phone went quiet — a tunnel, or an app that was killed
          // mid-call. Give it a moment to come back before ending a call that
          // may simply be walking through a lift.
          _dropTimeout?.cancel();
          _dropTimeout = Timer(const Duration(seconds: 20), () {
            if (isBusy) _finish(CallStatus.ended, note: 'ended');
          });
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // Nearly always the same thing: the two ends could not open a path
          // and there is no relay to fall back on. See `CallConfig`.
          debugPrint('Call: the connection could not be established');
          _finish(CallStatus.ended, note: 'failed');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          break;
        default:
          break;
      }
    };

    // The earpiece, the way a voice call starts everywhere else. The speaker
    // is a button away.
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _postCandidate(Map<String, dynamic> candidate) {
    final String? id = session?.id;
    if (id == null || id.isEmpty) {
      _pendingCandidates.add(candidate);
      return;
    }
    _repository
        .addCandidate(id, fromCaller: _amCaller, candidate: candidate)
        .catchError((Object e) => debugPrint('Call: route not posted — $e'));
  }

  Future<void> _flushCandidates() async {
    final String? id = session?.id;
    if (id == null || id.isEmpty || _pendingCandidates.isEmpty) return;

    final List<Map<String, dynamic>> waiting =
        List<Map<String, dynamic>>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final Map<String, dynamic> candidate in waiting) {
      try {
        await _repository.addCandidate(id,
            fromCaller: _amCaller, candidate: candidate);
      } catch (e) {
        debugPrint('Call: route not posted — $e');
      }
    }
  }

  void _watchCall(String callId) {
    _callWatch?.cancel();
    _callWatch = _repository.watch(callId).listen(
      _onCallChanged,
      onError: (Object e) => debugPrint('Call: watch failed — $e'),
    );
  }

  Future<void> _onCallChanged(CallSession? live) async {
    if (live == null) {
      // The document is gone — the other end cleared it. Belt and braces: the
      // status change that preceded it is what normally ends a call here, and
      // this catches the one that did not arrive.
      if (isBusy) await _tearDown(note: 'ended');
      return;
    }
    if (live.id != session?.id) return;

    final CallStatus was = session?.status ?? CallStatus.ringing;
    session = live;

    if (live.isOver) {
      // The other end rang off. Which of the three it was decides the line
      // the screen shows on the way out.
      if (phase != CallPhase.ended) {
        final String note = live.status == CallStatus.declined
            ? 'declined'
            : live.status == CallStatus.missed
                ? 'unanswered'
                : 'ended';
        await _tearDown(note: note);
      }
      return;
    }

    // Somebody picked up, and it was not this phone. The same account signed
    // in on a second device: it rang there too, and there is nothing for this
    // one to do but stop ringing.
    if (phase == CallPhase.incoming && live.status == CallStatus.accepted) {
      await _tearDown(note: 'ended');
      return;
    }

    // The answer landed. Only the caller has anything to do with it.
    if (_amCaller &&
        was != CallStatus.accepted &&
        live.status == CallStatus.accepted &&
        live.answer != null) {
      _ringTimeout?.cancel();
      phase = CallPhase.connecting;
      update();
      try {
        await _peer?.setRemoteDescription(
          RTCSessionDescription(
            live.answer!['sdp'] as String?,
            live.answer!['type'] as String?,
          ),
        );
      } catch (e) {
        debugPrint('Call: could not take the answer — $e');
        await _finish(CallStatus.ended, note: 'failed');
      }
      return;
    }

    update();
  }

  void _listenForCandidates(String callId, {required bool fromCaller}) {
    _candidateWatch?.cancel();
    _candidateWatch = _repository
        .candidates(callId, fromCaller: fromCaller)
        .listen((List<Map<String, dynamic>> found) async {
      for (final Map<String, dynamic> candidate in found) {
        try {
          await _peer?.addCandidate(RTCIceCandidate(
            candidate['candidate'] as String?,
            candidate['sdpMid'] as String?,
            (candidate['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (e) {
          debugPrint('Call: route rejected — $e');
        }
      }
    }, onError: (Object e) => debugPrint('Call: route watch failed — $e'));
  }

  void _onConnected() {
    if (phase == CallPhase.connected || phase == CallPhase.ended) return;
    _ringTimeout?.cancel();
    _stopRingHaptics();
    phase = CallPhase.connected;
    _talkingSince = DateTime.now();
    _talkTicker?.cancel();
    _talkTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? since = _talkingSince;
      if (since == null) return;
      talkTime = DateTime.now().difference(since);
      update();
    });
    update();
  }

  /// Ends the call from this side: tells the other end, then tears down.
  Future<void> _finish(CallStatus status, {required String note}) async {
    final String? id = session?.id;
    if (id != null && id.isNotEmpty) {
      await _repository.finish(id, status, _myPhone);
    }
    await _tearDown(note: note, outcome: status);
  }

  /// Puts everything down. By this point the call document has been dealt
  /// with — either by this device hanging up, or by the other one.
  Future<void> _tearDown({
    required String note,
    CallStatus? outcome,
  }) async {
    if (phase == CallPhase.idle) return;

    final CallSession? finished = session;
    final Duration talked = talkTime;
    final bool wasConnected = phase == CallPhase.connected;

    _ringTimeout?.cancel();
    _ringTimeout = null;
    _dropTimeout?.cancel();
    _dropTimeout = null;
    _talkTicker?.cancel();
    _talkTicker = null;
    _talkingSince = null;
    _stopRingHaptics();
    _candidateWatch?.cancel();
    _candidateWatch = null;
    _callWatch?.cancel();
    _callWatch = null;

    endedNote = note;
    phase = CallPhase.ended;
    update();

    try {
      // Stopped before it is let go of: a track that is only disposed can
      // leave the microphone light on until the OS gets round to it, and a
      // phone that looks like it is still listening after a call is over is
      // the worst thing this could do.
      for (final MediaStreamTrack track in _localStream?.getTracks() ?? const []) {
        await track.stop();
      }
      await _localStream?.dispose();
    } catch (e) {
      debugPrint('Call: microphone not released cleanly — $e');
    }
    _localStream = null;
    try {
      await _peer?.close();
    } catch (_) {}
    _peer = null;
    if (_remoteRenderer != null) {
      _remoteRenderer!.srcObject = null;
      await _remoteRenderer!.dispose();
      _remoteRenderer = null;
    }
    _pendingCandidates.clear();

    // Whatever is left of the call goes in the thread. Written by the caller
    // alone, so one call is one line however both ends ended it.
    if (finished != null && finished.callerPhone == _myPhone) {
      await _logCall(finished,
          outcome: outcome, talked: wasConnected ? talked : null);
      await _repository.discard(finished.id);
    }

    // Held for a moment so the screen can say how it ended, then gone.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (phase != CallPhase.ended) return;
      phase = CallPhase.idle;
      session = null;
      talkTime = Duration.zero;
      update();
      _closeScreen();
    });
  }

  /// Puts the call into the conversation: how long it ran, or that nobody
  /// picked up. See `ChatMessageModel.callOutcome`.
  Future<void> _logCall(
    CallSession call, {
    CallStatus? outcome,
    Duration? talked,
  }) async {
    final String result = talked != null
        ? 'answered'
        : (outcome ?? call.status) == CallStatus.declined
            ? 'declined'
            : 'missed';

    try {
      await Get.find<ChatCallLogger>().log(
        conversationId: call.conversationId,
        peerPhone: call.calleePhone,
        callerPhone: call.callerPhone,
        callerName: call.callerName,
        callerImage: call.callerImage,
        outcome: result,
        seconds: talked?.inSeconds ?? 0,
      );
    } catch (e) {
      debugPrint('Call: no line written to the thread — $e');
    }
  }

  void _notifyPeer(CallSession call) {
    PushNotificationService()
        .sendPushNotification(
          title: call.callerName,
          body: '📞 ${'incoming_audio_call'.tr}',
          targetPhones: <String>[call.calleePhone],
          data: <String, String>{
            'type': 'incoming_call',
            'senderName': call.callerName,
            'senderPhone': call.callerPhone,
            'senderImage': call.callerImage ?? '',
            'conversationId': call.conversationId,
            'callId': call.id,
            'replyToSenderName': '',
            'mentions': '',
            'isEveryone': 'false',
          },
        )
        .timeout(const Duration(seconds: 15))
        .catchError((Object e) {
      debugPrint('Call: the other phone was not notified — $e');
      return false;
    });
  }

  // ------------------------------------------------------------------ ring

  /// A phone with no ringtone still has to be noticeable. Foreground only —
  /// away from the app it is the notification that does the ringing.
  void _startRingHaptics() {
    _ringHaptics?.cancel();
    HapticFeedback.heavyImpact();
    _ringHaptics = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (phase != CallPhase.incoming) return;
      HapticFeedback.heavyImpact();
    });
  }

  void _stopRingHaptics() {
    _ringHaptics?.cancel();
    _ringHaptics = null;
  }

  // ---------------------------------------------------------------- screen

  void _openScreen() {
    if (_screenOpen) return;
    // A call that arrives before there is anything on screen — during the
    // splash, say — has nowhere to be shown. It still rings, and the screen
    // comes up on the next one if it is still ringing by then.
    if (Get.context == null) return;

    _screenOpen = true;
    Get.to(
      () => const CallScreen(),
      fullscreenDialog: true,
      opaque: true,
      preventDuplicates: false,
    )?.whenComplete(() => _screenOpen = false);
  }

  void _closeScreen() {
    if (!_screenOpen) return;
    _screenOpen = false;
    // Only if it is still the thing on top: a notification tap, or the member
    // themselves, may have put something over it.
    if (Get.currentRoute.contains('CallScreen')) Get.back();
  }

  @override
  void onClose() {
    _incomingWatch?.cancel();
    _callWatch?.cancel();
    _candidateWatch?.cancel();
    _ringTimeout?.cancel();
    _dropTimeout?.cancel();
    _talkTicker?.cancel();
    _ringHaptics?.cancel();
    super.onClose();
  }
}

/// How a finished call gets into the conversation.
///
/// An interface rather than a direct call into the chat, so the call service
/// does not have to know how a message is written — and so the thing that
/// writes it can be swapped in a test.
abstract class ChatCallLogger {
  Future<void> log({
    required String conversationId,
    required String peerPhone,
    required String callerPhone,
    required String callerName,
    String? callerImage,
    required String outcome,
    required int seconds,
  });
}
