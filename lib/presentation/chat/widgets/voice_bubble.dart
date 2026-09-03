import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/voice_player_service.dart';
import 'voice_wave.dart';

/// `m:ss` — how a voice message says its length everywhere it appears.
String formatClipTime(Duration d) {
  final int seconds = d.inSeconds;
  final String ss = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$ss';
}

/// A voice message in the thread: play, scrub, and see the shape of what was
/// said before playing it at all.
///
/// Draws its state from the one player the app has — see
/// [VoicePlayerService] — so starting this one stops whichever was going, and
/// a thread of fifty voice notes is fifty widgets and one player.
class VoiceBubble extends StatelessWidget {
  /// What identifies this clip to the player: the message's id, so the same
  /// bubble keeps its place in a playing clip across a rebuild.
  final String id;
  final String url;

  /// The length stamped on the message, shown until the file itself is
  /// loaded and can say better.
  final Duration stamped;

  final List<int> waveform;
  final bool isMe;

  const VoiceBubble({
    super.key,
    required this.id,
    required this.url,
    required this.stamped,
    required this.waveform,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = isMe ? Colors.white : theme.colorScheme.primary;
    final Color onAccent = isMe ? theme.colorScheme.primary : Colors.white;
    final Color quiet = isMe
        ? Colors.white.withOpacity(0.4)
        : theme.colorScheme.primary.withOpacity(0.28);
    final Color label = isMe
        ? Colors.white.withOpacity(0.85)
        : theme.textTheme.bodySmall?.color?.withOpacity(0.7) ?? Colors.grey;

    return GetBuilder<VoicePlayerService>(
      builder: (player) {
        final bool playing = player.isPlaying(id);
        final bool loading = player.isLoading(id);
        final bool failed = player.hasFailed(id);
        final double progress = player.progressOf(id, stamped: stamped);

        return ConstrainedBox(
          // A cap rather than a width: on a narrow phone the bubble gives way
          // the same as one holding a picture does.
          constraints: const BoxConstraints(maxWidth: 214),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PlayButton(
                playing: playing,
                loading: loading,
                failed: failed,
                background: accent,
                foreground: onAccent,
                onTap: () => player.toggle(id: id, url: url),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 28,
                      child: _Scrubber(
                        // Only the clip that is loaded can be scrubbed;
                        // dragging along one that has never been played would
                        // otherwise seek a player that is somewhere else
                        // entirely. Tapping one of those starts it, which is
                        // what aiming at a waveform means.
                        onSeek: player.isCurrent(id)
                            ? (double at) => player.seekFraction(id, at)
                            : null,
                        onStart: () => player.toggle(id: id, url: url),
                        child: VoiceWave(
                          levels: waveform,
                          progress: progress,
                          played: accent,
                          unplayed: quiet,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          failed
                              ? 'voice_play_failed'.tr
                              : formatClipTime(
                                  player.displayedTime(id, stamped: stamped)),
                          style: TextStyle(fontSize: 11, color: label),
                        ),
                        const Spacer(),
                        // Only on the clip being played: a speed control on
                        // every bubble in the thread is fifty ways to change
                        // one setting.
                        if (player.isCurrent(id) && !failed)
                          GestureDetector(
                            onTap: player.cycleSpeed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: quiet,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_trim(player.speed)}×',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// `1.5` and `2`, not `1.5` and `2.0`.
  static String _trim(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';
}

/// A voice message on its way out — recorded, queued, not yet in the thread.
///
/// The same shape the delivered bubble will have, down to the width, so
/// nothing moves when the upload lands and the real one takes its place.
/// There is nothing to play yet, so where the play button goes there is a
/// mark saying what is happening to it instead.
class PendingVoiceBubble extends StatelessWidget {
  final Duration duration;
  final List<int> waveform;
  final bool failed;
  final bool sending;

  const PendingVoiceBubble({
    super.key,
    required this.duration,
    required this.waveform,
    required this.failed,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = Colors.white;
    final Color quiet = Colors.white.withOpacity(0.4);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 214),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: quiet, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: failed
                ? const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 20)
                : sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.schedule_rounded,
                        color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: VoiceWave(
                    levels: waveform,
                    played: accent,
                    unplayed: quiet,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatClipTime(duration),
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final bool loading;
  final bool failed;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: foreground),
              )
            : Icon(
                failed
                    ? Icons.refresh_rounded
                    : playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                color: foreground,
                size: 22,
              ),
      ),
    );
  }
}

/// Turns a tap or a drag anywhere along the bars into a point in the clip.
class _Scrubber extends StatelessWidget {
  final Widget child;
  final void Function(double fraction)? onSeek;

  /// What a tap does on a clip that is not the one loaded: start it. There is
  /// nothing to scrub yet, and a waveform that ignores a tap reads as broken.
  final VoidCallback onStart;

  const _Scrubber({required this.child, required this.onStart, this.onSeek});

  @override
  Widget build(BuildContext context) {
    final void Function(double)? seek = onSeek;
    if (seek == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onStart,
        child: child,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        void at(Offset local) {
          final double width = constraints.maxWidth;
          if (width <= 0) return;
          seek(local.dx / width);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => at(details.localPosition),
          onHorizontalDragUpdate: (details) => at(details.localPosition),
          child: child,
        );
      },
    );
  }
}
