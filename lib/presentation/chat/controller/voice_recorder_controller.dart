import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../model/voice_note_model.dart';

/// Where a recording is in its life.
enum VoicePhase {
  /// Nothing is being recorded — the composer is a composer.
  idle,

  /// The finger is on the microphone. Letting go sends; sliding left drops
  /// it; sliding up hands it over to [locked].
  holding,

  /// Hands-free. The recording carries on with nothing held down, and the bar
  /// grows a stop and a send of its own.
  locked,
}

/// The composer's microphone.
///
/// Holds everything a recording in progress knows — how long it has run, how
/// loud it has been, whether the finger has slid far enough to mean "drop
/// this" — and hands back a [RecordedVoice] when it is let go of. What
/// happens to that clip afterwards is the chat controller's business; this
/// one only records.
class VoiceRecorderController extends GetxController {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _amplitudes;
  Timer? _ticker;
  final Stopwatch _watch = Stopwatch();

  VoicePhase phase = VoicePhase.idle;

  bool get isRecording => phase != VoicePhase.idle;

  bool get isLocked => phase == VoicePhase.locked;

  /// True once the finger has slid far enough left that letting go drops the
  /// recording. The bar says so before it happens — a gesture that throws
  /// away what somebody just said must never be a surprise.
  bool willCancel = false;

  Duration elapsed = Duration.zero;

  /// Loudness over time, 0–100, one reading per [_sampleEvery]. The bar draws
  /// the tail of this; the send stores a squeezed copy — see
  /// `RecordedVoice.resample`.
  final List<int> levels = <int>[];

  /// Where this recording is being written, and what it will be called. Null
  /// on web, where the browser hands back a blob when it is stopped.
  String? _path;
  String _extension = '.m4a';

  /// Shorter than this and it was a mis-tap, not a message. WhatsApp draws
  /// the same line and for the same reason: a quarter-second of somebody's
  /// pocket is not worth a bubble.
  static const Duration minimum = Duration(seconds: 1);

  /// The ceiling. Reached, the recording stops and is sent as it stands
  /// rather than being thrown away — five minutes of talking is not something
  /// to lose to a rule.
  static const Duration maximum = Duration(minutes: 5);

  static const Duration _sampleEvery = Duration(milliseconds: 100);

  /// Fired when [maximum] is reached, so the composer can send what there is
  /// without waiting for a finger that may never lift.
  VoidCallback? onMaximumReached;

  /// So the ceiling is announced once, however many ticks pass before the
  /// recording actually stops.
  bool _maximumFired = false;

  /// Starts recording, asking for the microphone the first time.
  ///
  /// Returns false when there is nothing to record with — permission refused,
  /// or a platform that cannot — having already said so.
  Future<bool> start() async {
    if (isRecording) return true;

    try {
      if (!await _recorder.hasPermission()) {
        CustomSnackbar.show(
          type: SnackbarType.warning,
          message: 'mic_permission_needed'.tr,
        );
        return false;
      }

      _extension = await _pickExtension();
      _path = await _newClipPath(_extension);

      await _recorder.start(
        RecordConfig(
          encoder: _encoderFor(_extension),
          // Speech, mono, at a bitrate that keeps a minute under half a
          // megabyte: this is a voice message, not a recording session.
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        // Web ignores it and answers with a blob URL when it is stopped.
        path: _path ?? 'voice',
      );
    } catch (e) {
      debugPrint('VoiceRecorder: could not start — $e');
      CustomSnackbar.show(
        type: SnackbarType.error,
        message: 'failed_record_voice'.tr,
      );
      return false;
    }

    phase = VoicePhase.holding;
    willCancel = false;
    _maximumFired = false;
    elapsed = Duration.zero;
    levels.clear();
    _watch
      ..reset()
      ..start();

    _amplitudes = _recorder
        .onAmplitudeChanged(_sampleEvery)
        .listen(_onAmplitude, onError: (Object e) {
      debugPrint('VoiceRecorder: amplitude stream failed — $e');
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed = _watch.elapsed;
      if (elapsed >= maximum && !_maximumFired) {
        _maximumFired = true;
        onMaximumReached?.call();
        return;
      }
      update();
    });

    update();
    return true;
  }

  /// Stops, and hands back what was recorded — or null when it was too short
  /// to be a message, in which case it has already been dropped.
  Future<RecordedVoice?> stop() async {
    if (!isRecording) return null;

    final Duration ran = _watch.elapsed;
    final List<int> shape = List<int>.from(levels);
    final String? path = await _finish();
    if (path == null) return null;

    if (ran < minimum) {
      await _deleteClip(path);
      CustomSnackbar.show(
        type: SnackbarType.info,
        message: 'hold_to_record'.tr,
      );
      return null;
    }

    return RecordedVoice(
      path: path,
      extension: _extension,
      // The stopwatch, not the file: a clip is timed from the moment the
      // microphone opened, and asking the file would mean decoding it.
      duration: ran,
      waveform: RecordedVoice.resample(shape),
    );
  }

  /// Drops the recording — the slide-left gesture, and the bin in the locked
  /// bar. Nothing is kept and nothing is sent.
  Future<void> cancel() async {
    if (!isRecording) return;
    _teardown();
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('VoiceRecorder: could not cancel — $e');
    }
    await _deleteClip(_path);
    _path = null;
    update();
  }

  /// Hands the recording over to the bar, so it carries on with nothing held
  /// down. One way only: there is no unlocking, only stopping.
  void lock() {
    if (phase != VoicePhase.holding) return;
    phase = VoicePhase.locked;
    willCancel = false;
    update();
  }

  /// Where the finger has got to, relative to where it went down. Called as
  /// it moves, so the bar can promise what letting go will do.
  void trackDrag(Offset offset) {
    if (phase != VoicePhase.holding) return;

    if (offset.dy <= -_lockAt) {
      lock();
      return;
    }

    final bool cancelling = offset.dx <= -_cancelAt;
    if (cancelling != willCancel) {
      willCancel = cancelling;
      update();
    }
  }

  /// How far left the finger travels before letting go means "drop it", and
  /// how far up before the recording carries on without it. Generous enough
  /// that neither happens by accident while holding still.
  static const double _cancelAt = 80;
  static const double _lockAt = 60;

  @override
  void onClose() {
    // A recording nobody is going to send: the microphone must not be left
    // open behind a screen that has gone.
    if (isRecording) cancel();
    _teardown();
    _recorder.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------------ inside

  void _onAmplitude(Amplitude amplitude) {
    levels.add(_levelOf(amplitude.current));
    update();
  }

  /// dBFS — roughly -45 for a quiet room, 0 for as loud as the microphone
  /// goes — mapped onto the 0–100 a bar is drawn from.
  ///
  /// Curved rather than straight: speech sits in the top of that range, and a
  /// straight mapping draws every ordinary sentence as the same short stub.
  static int _levelOf(double dbfs) {
    if (!dbfs.isFinite) return 6;
    final double normalized = ((dbfs + 45) / 45).clamp(0, 1).toDouble();
    return (math.pow(normalized, 0.6) * 100).round().clamp(6, 100);
  }

  /// Stops the recorder and the clocks, and answers where the clip ended up.
  Future<String?> _finish() async {
    _teardown();
    try {
      final String? path = await _recorder.stop();
      // On web the recorder answers with a blob URL of its own; everywhere
      // else it is the path it was handed.
      return path ?? _path;
    } catch (e) {
      debugPrint('VoiceRecorder: could not stop — $e');
      return null;
    }
  }

  void _teardown() {
    _amplitudes?.cancel();
    _amplitudes = null;
    _ticker?.cancel();
    _ticker = null;
    _watch.stop();
    phase = VoicePhase.idle;
    willCancel = false;
    elapsed = Duration.zero;
    levels.clear();
  }

  Future<String?> _newClipPath(String extension) async {
    if (kIsWeb) return null;
    final Directory dir = Directory(
      '${(await getTemporaryDirectory()).path}/voice_notes',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/${DateTime.now().microsecondsSinceEpoch}$extension';
  }

  Future<void> _deleteClip(String? path) async {
    if (kIsWeb || path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('VoiceRecorder: could not delete $path — $e');
    }
  }

  /// What this platform can actually encode, in the order worth having.
  ///
  /// AAC in an MP4 container everywhere it is offered — every phone browser
  /// and both app platforms play it. Opus in WebM is what Chrome records
  /// when it will not; WAV is the last resort, and is large enough that it is
  /// only ever a last resort.
  Future<String> _pickExtension() async {
    for (final MapEntry<String, AudioEncoder> option in const {
      '.m4a': AudioEncoder.aacLc,
      '.webm': AudioEncoder.opus,
      '.wav': AudioEncoder.wav,
    }.entries) {
      try {
        if (await _recorder.isEncoderSupported(option.value)) return option.key;
      } catch (_) {
        // A platform that cannot answer is one to stop asking.
        break;
      }
    }
    return '.m4a';
  }

  static AudioEncoder _encoderFor(String extension) {
    switch (extension) {
      case '.webm':
        return AudioEncoder.opus;
      case '.wav':
        return AudioEncoder.wav;
      default:
        return AudioEncoder.aacLc;
    }
  }
}
