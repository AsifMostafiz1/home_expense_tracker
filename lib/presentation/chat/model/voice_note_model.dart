import 'dart:math' as math;

/// A voice message the composer has finished recording but not yet sent.
///
/// Everything the send needs is worked out here, while the microphone is
/// still the thing that knows: how long it ran, and the shape of it. Neither
/// can be recovered later without decoding the whole file, which is not
/// something a chat bubble is ever going to do.
class RecordedVoice {
  /// Where the clip sits on this device — a real file on a phone, a blob URL
  /// in a browser, the same split the composer's pictures live with.
  final String path;

  /// What to call the object once it is uploaded. Carried rather than read
  /// off [path] because a browser's blob URL has no name, and a voice note
  /// stored under the wrong extension is served as the wrong type and will
  /// not play.
  final String extension;

  final Duration duration;

  /// The bars a bubble draws, 0–100, sampled while it was being spoken.
  final List<int> waveform;

  const RecordedVoice({
    required this.path,
    required this.extension,
    required this.duration,
    required this.waveform,
  });

  /// How many bars a stored waveform holds. Enough that a minute of talking
  /// still has shape, few enough that it costs nothing to keep on the
  /// message — see `ChatMessageModel.audioWave`.
  static const int bars = 44;

  /// Squeezes however many levels the microphone produced into [bars] of
  /// them, averaging each bucket.
  ///
  /// A short clip has fewer readings than there are bars; it is stretched, so
  /// the bubble is always the same width whatever was said. Nothing is
  /// invented either way — a bar is the loudness of the slice of time under
  /// it.
  static List<int> resample(List<int> levels, {int bars = RecordedVoice.bars}) {
    if (levels.isEmpty) return List<int>.filled(bars, 6);
    if (levels.length <= bars) {
      return <int>[
        for (int i = 0; i < bars; i++)
          levels[(i * levels.length ~/ bars).clamp(0, levels.length - 1)],
      ];
    }

    final List<int> out = <int>[];
    for (int i = 0; i < bars; i++) {
      final int from = i * levels.length ~/ bars;
      final int to = math.max(from + 1, (i + 1) * levels.length ~/ bars);
      int sum = 0;
      for (int j = from; j < to; j++) {
        sum += levels[j];
      }
      out.add(sum ~/ (to - from));
    }
    return out;
  }
}
