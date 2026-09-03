import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the chat's voice messages — one at a time, for the whole app.
///
/// One player rather than one per bubble, because that is what a thread of
/// voice notes needs: starting the next one stops the last, the way it does
/// in every chat app, and a hundred bubbles scrolled past cost a hundred
/// widgets rather than a hundred platform players.
///
/// The player itself is built on first use. Nothing is opened by having the
/// service registered, so a house that never sends a voice message never
/// makes one.
class VoicePlayerService extends GetxController implements GetxService {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  /// Which clip is loaded — a message id, or an outgoing message's local id.
  /// Null when nothing has been played yet.
  String? _clipId;

  /// The URL that id was loaded from, so tapping the same bubble again
  /// resumes rather than re-fetching.
  String? _clipUrl;

  Duration position = Duration.zero;

  /// What the file turned out to be, once it is loaded. Zero until then — a
  /// bubble shows the length stamped on the message in the meantime.
  Duration duration = Duration.zero;

  bool _playing = false;
  bool _loading = false;
  bool _failed = false;

  /// Playback speed, shared by every clip: somebody who wants to get through
  /// a long message quickly wants the same of the next one.
  double speed = 1;

  static const List<double> _speeds = <double>[1, 1.5, 2];

  bool isCurrent(String id) => _clipId == id;

  bool isPlaying(String id) => _clipId == id && _playing;

  bool isLoading(String id) => _clipId == id && _loading;

  bool hasFailed(String id) => _clipId == id && _failed;

  /// Where this clip is up to, 0–1. Zero for one that is not loaded, so every
  /// other bubble in the thread sits at its start.
  double progressOf(String id, {Duration? stamped}) {
    if (_clipId != id) return 0;
    final Duration total =
        duration > Duration.zero ? duration : (stamped ?? Duration.zero);
    if (total <= Duration.zero) return 0;
    final double at = position.inMilliseconds / total.inMilliseconds;
    return at.clamp(0, 1).toDouble();
  }

  /// What the bubble's clock shows: how far in, once this clip is the one
  /// playing, and how long it runs otherwise.
  Duration displayedTime(String id, {Duration? stamped}) {
    if (_clipId != id || (position == Duration.zero && !_playing)) {
      return stamped ?? duration;
    }
    return position;
  }

  /// Plays [url], pauses it if it is already playing, resumes it if it was
  /// paused part-way through.
  Future<void> toggle({required String id, required String url}) async {
    final AudioPlayer player = _ensurePlayer();

    if (_clipId == id && _clipUrl == url) {
      if (_playing) {
        await player.pause();
      } else {
        // A clip that ran to the end starts again rather than sitting at its
        // own end doing nothing.
        if (duration > Duration.zero && position >= duration) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
      return;
    }

    // A different clip: whatever was playing stops here.
    _clipId = id;
    _clipUrl = url;
    position = Duration.zero;
    duration = Duration.zero;
    _playing = false;
    _failed = false;
    _loading = true;
    update();

    try {
      await player.stop();
      final Duration? loaded = await player.setUrl(url);
      // Another bubble was tapped while this one was loading; that one owns
      // the player now and this reply is stale.
      if (_clipId != id) return;
      duration = loaded ?? Duration.zero;
      _loading = false;
      await player.setSpeed(speed);
      await player.play();
    } catch (e) {
      if (_clipId != id) return;
      debugPrint('VoicePlayer: could not play $url — $e');
      _loading = false;
      _failed = true;
    }
    update();
  }

  /// Jumps to a point in the clip, 0–1. Only the one that is loaded can be
  /// scrubbed — dragging along a bubble that has never been played starts it
  /// from the beginning instead.
  Future<void> seekFraction(String id, double fraction) async {
    if (_clipId != id || duration <= Duration.zero) return;
    final Duration to = Duration(
      milliseconds: (duration.inMilliseconds * fraction.clamp(0, 1)).round(),
    );
    position = to;
    update();
    await _player?.seek(to);
  }

  /// 1× → 1.5× → 2× → 1×, the way a voice note is usually hurried along.
  Future<void> cycleSpeed() async {
    speed = _speeds[(_speeds.indexOf(speed) + 1) % _speeds.length];
    update();
    await _player?.setSpeed(speed);
  }

  /// Stops whatever is playing and lets go of the clip — what leaving the
  /// thread does, so a voice note does not keep talking over another screen.
  Future<void> stop() async {
    if (_player == null) return;
    await _player!.stop();
    _playing = false;
    position = Duration.zero;
    _clipId = null;
    _clipUrl = null;
    update();
  }

  AudioPlayer _ensurePlayer() {
    final AudioPlayer? existing = _player;
    if (existing != null) return existing;

    final AudioPlayer player = AudioPlayer();
    _player = player;

    _positionSubscription = player.positionStream.listen((Duration at) {
      position = at;
      update();
    });
    _durationSubscription = player.durationStream.listen((Duration? total) {
      if (total == null) return;
      duration = total;
      update();
    });
    _stateSubscription = player.playerStateStream.listen((PlayerState state) {
      _playing = state.playing &&
          state.processingState != ProcessingState.completed;
      // A clip that has finished goes back to its start, so the next tap
      // plays it rather than doing nothing.
      if (state.processingState == ProcessingState.completed) {
        position = duration;
        player.pause();
        player.seek(Duration.zero);
      }
      update();
    });

    return player;
  }

  @override
  void onClose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _player?.dispose();
    super.onClose();
  }
}
