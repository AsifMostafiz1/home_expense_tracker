import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/voice_recorder_controller.dart';
import 'voice_bubble.dart' show formatClipTime;
import 'voice_wave.dart';

/// What the composer becomes while the microphone is open.
///
/// Two states, and they say different things because the sender needs
/// different things from them. Held: how long it has run, and what letting go
/// will do — send it, or, once the finger has slid far enough left, throw it
/// away. Locked: the same clock, the sound going in, and a bin.
class VoiceRecorderBar extends StatelessWidget {
  final VoiceRecorderController recorder;

  /// Drops the recording. The bin in the locked bar; the slide-left gesture
  /// answers to the composer instead, on the finger coming up.
  final VoidCallback onCancel;

  const VoiceRecorderBar({
    super.key,
    required this.recorder,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color danger = theme.colorScheme.error;
    final bool cancelling = recorder.willCancel;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: cancelling ? danger : theme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          if (recorder.isLocked)
            GestureDetector(
              onTap: onCancel,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.delete_outline_rounded,
                    color: danger, size: 22),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Blink(child: _Dot(color: danger)),
            ),
          Text(
            formatClipTime(recorder.elapsed),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: cancelling
                  ? danger
                  : theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: recorder.isLocked
                ? _LiveWave(recorder: recorder, color: theme.colorScheme.primary)
                : _CancelHint(cancelling: cancelling),
          ),
          if (!recorder.isLocked)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_up_rounded,
                      size: 16,
                      color: theme.textTheme.bodySmall?.color
                          ?.withOpacity(0.6)),
                  Icon(Icons.lock_outline_rounded,
                      size: 14,
                      color: theme.textTheme.bodySmall?.color
                          ?.withOpacity(0.6)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The last couple of seconds of sound, scrolling past — what a recording
/// that nobody is holding looks like while it runs.
class _LiveWave extends StatelessWidget {
  final VoiceRecorderController recorder;
  final Color color;

  const _LiveWave({required this.recorder, required this.color});

  /// How much of the tail is shown. A window rather than the whole recording:
  /// squeezing four minutes into a strip that narrow would draw a grey block.
  static const int _window = 36;

  @override
  Widget build(BuildContext context) {
    final List<int> all = recorder.levels;
    final List<int> tail =
        all.length <= _window ? all : all.sublist(all.length - _window);

    return SizedBox(
      height: 26,
      child: VoiceWave(
        levels: tail,
        played: color,
        unplayed: color,
        progress: 1,
      ),
    );
  }
}

class _CancelHint extends StatelessWidget {
  final bool cancelling;

  const _CancelHint({required this.cancelling});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = cancelling
        ? theme.colorScheme.error
        : theme.textTheme.bodySmall?.color?.withOpacity(0.7) ?? Colors.grey;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!cancelling)
          Icon(Icons.chevron_left_rounded, size: 18, color: color),
        Flexible(
          child: Text(
            cancelling ? 'release_to_cancel'.tr : 'slide_to_cancel'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: cancelling ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The recording light. Blinking rather than steady because that is what a
/// microphone that is live looks like everywhere else.
class _Blink extends StatefulWidget {
  final Widget child;

  const _Blink({required this.child});

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_controller),
        child: widget.child,
      );
}
