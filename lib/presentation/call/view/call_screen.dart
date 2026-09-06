import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';

import '../../../common/widgets/profile_avatar.dart';
import '../../../services/call_service.dart';
import '../model/call_model.dart';

/// The call, whatever it is doing: ringing out, ringing in, connecting,
/// connected, or just over.
///
/// One screen for all of it rather than one per state, because that is what a
/// call is — the same two people, the same face, a line underneath that keeps
/// changing. Answering does not take anybody anywhere; it changes what the
/// buttons at the bottom are.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CallService>(
      builder: (service) {
        final CallSession? call = service.session;
        final bool ringingIn = service.phase == CallPhase.incoming;

        return PopScope(
          // A call has nowhere to be minimised to, so back would strand it
          // running with no way to reach it again. The red button is the way
          // out, and it is the largest thing on the screen.
          canPop: !service.isBusy,
          child: Scaffold(
            backgroundColor: const Color(0xFF101418),
            body: Stack(
              children: [
                // Web plays the far end's voice through an element rather
                // than by itself; this is that element, and it has nothing to
                // show.
                if (kIsWeb && service.remoteRenderer != null)
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: RTCVideoView(service.remoteRenderer!),
                  ),
                SafeArea(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      _Face(call: call, myPhone: service.myPhone),
                      const SizedBox(height: 24),
                      Text(
                        call?.peerNameFor(service.myPhone) ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Status(service: service),
                      const Spacer(flex: 3),
                      if (ringingIn)
                        _IncomingButtons(service: service)
                      else
                        _InCallButtons(service: service),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Face extends StatelessWidget {
  final CallSession? call;
  final String myPhone;

  const _Face({required this.call, required this.myPhone});

  @override
  Widget build(BuildContext context) {
    final CallSession? session = call;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ProfileAvatar(
        name: session?.peerNameFor(myPhone) ?? '',
        phone: session?.peerPhoneFor(myPhone),
        imageUrl: session?.peerImageFor(myPhone),
        size: 132,
        background: Colors.white24,
        foreground: Colors.white,
        fontSize: 44,
      ),
    );
  }
}

/// The one line that says what is happening. Everything else on the screen
/// stays put; this is what a caller is actually watching.
class _Status extends StatelessWidget {
  final CallService service;

  const _Status({required this.service});

  @override
  Widget build(BuildContext context) {
    final String label;
    switch (service.phase) {
      case CallPhase.dialling:
        label = 'calling'.tr;
        break;
      case CallPhase.incoming:
        label = 'incoming_audio_call'.tr;
        break;
      case CallPhase.connecting:
        label = 'call_connecting'.tr;
        break;
      case CallPhase.connected:
        label = _clock(service.talkTime);
        break;
      case CallPhase.ended:
      case CallPhase.idle:
        label = _endedLine(service.endedNote);
        break;
    }

    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontSize: 15,
        letterSpacing: 0.2,
      ),
    );
  }

  static String _endedLine(String note) {
    switch (note) {
      case 'declined':
        return 'call_was_declined'.tr;
      case 'unanswered':
        return 'call_unanswered'.tr;
      case 'failed':
        return 'call_failed'.tr;
      default:
        return 'call_ended'.tr;
    }
  }

  static String _clock(Duration d) {
    final int seconds = d.inSeconds;
    final String mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final String ss = (seconds % 60).toString().padLeft(2, '0');
    if (seconds >= 3600) {
      return '${seconds ~/ 3600}:$mm:$ss';
    }
    return '$mm:$ss';
  }
}

class _IncomingButtons extends StatelessWidget {
  final CallService service;

  const _IncomingButtons({required this.service});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: Icons.call_end_rounded,
          background: const Color(0xFFE53935),
          label: 'decline'.tr,
          size: 68,
          onTap: service.decline,
        ),
        _CallButton(
          icon: Icons.call_rounded,
          background: const Color(0xFF25D366),
          label: 'accept'.tr,
          size: 68,
          onTap: service.accept,
        ),
      ],
    );
  }
}

class _InCallButtons extends StatelessWidget {
  final CallService service;

  const _InCallButtons({required this.service});

  @override
  Widget build(BuildContext context) {
    final bool live = service.isBusy;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallButton(
          icon: service.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          background: service.muted ? Colors.white : Colors.white24,
          foreground: service.muted ? Colors.black87 : Colors.white,
          label: 'mute'.tr,
          onTap: live ? service.toggleMute : null,
        ),
        _CallButton(
          icon: service.speakerOn
              ? Icons.volume_up_rounded
              : Icons.volume_down_rounded,
          background: service.speakerOn ? Colors.white : Colors.white24,
          foreground: service.speakerOn ? Colors.black87 : Colors.white,
          label: 'speaker'.tr,
          onTap: live ? service.toggleSpeaker : null,
        ),
        _CallButton(
          icon: Icons.call_end_rounded,
          background: const Color(0xFFE53935),
          label: 'end_call'.tr,
          size: 68,
          onTap: live ? service.hangUp : null,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final String label;
  final double size;
  final VoidCallback? onTap;

  const _CallButton({
    required this.icon,
    required this.background,
    required this.label,
    this.foreground = Colors.white,
    this.size = 58,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: background, shape: BoxShape.circle),
              child: Icon(icon, color: foreground, size: size * 0.44),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
