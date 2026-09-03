import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:demo_project/presentation/chat/widgets/voice_bubble.dart';
import 'package:demo_project/presentation/chat/widgets/voice_wave.dart';
import 'package:demo_project/services/voice_player_service.dart';

/// The bubble inside a box of [width], which is what a narrow phone gives it.
Widget _framed(Widget child, {double width = 260}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  setUp(() {
    // Registered, not started: the player itself is only built when something
    // is actually played, so nothing here touches a platform channel.
    Get.put(VoicePlayerService());
  });

  tearDown(Get.reset);

  testWidgets('a voice message shows its length before anything is played',
      (tester) async {
    await tester.pumpWidget(_framed(
      const VoiceBubble(
        id: 'v1',
        url: 'https://clips/v1.m4a',
        stamped: Duration(seconds: 67),
        waveform: <int>[10, 40, 90, 30],
        isMe: false,
      ),
    ));

    expect(find.text('1:07'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // The speed control belongs to the clip being played, and none is.
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('it gives way rather than overflowing a narrow bubble',
      (tester) async {
    await tester.pumpWidget(_framed(
      const VoiceBubble(
        id: 'v1',
        url: 'https://clips/v1.m4a',
        stamped: Duration(seconds: 9),
        waveform: <int>[80, 20],
        isMe: true,
      ),
      // Narrower than the 214 the bubble would like.
      width: 150,
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('0:09'), findsOneWidget);
  });

  testWidgets('a message sent before waveforms were recorded still draws',
      (tester) async {
    await tester.pumpWidget(_framed(
      const VoiceBubble(
        id: 'old',
        url: 'https://clips/old.m4a',
        stamped: Duration(seconds: 4),
        waveform: <int>[],
        isMe: false,
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(VoiceWave), findsOneWidget);
  });

  testWidgets('one on its way out is the same shape, with no play button',
      (tester) async {
    await tester.pumpWidget(_framed(
      const PendingVoiceBubble(
        duration: Duration(seconds: 12),
        waveform: <int>[30, 70],
        failed: false,
        sending: true,
      ),
    ));

    expect(find.text('0:12'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('one that could not be sent says so where the button was',
      (tester) async {
    await tester.pumpWidget(_framed(
      const PendingVoiceBubble(
        duration: Duration(seconds: 3),
        waveform: <int>[30, 70],
        failed: true,
        sending: false,
      ),
    ));

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });
}
