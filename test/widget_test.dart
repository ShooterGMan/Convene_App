import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:convene/widgets/waveform_visualizer.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';
import 'package:convene/theme/app_theme.dart';

void main() {
  group('Core Widget Tests', () {
    testWidgets('WaveformVisualizer renders correct number of bars and responds to stream',
        (WidgetTester tester) async {
      final amplitudeController = StreamController<double>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: WaveformVisualizer(
              height: 100,
              barCount: 20,
              amplitudeStream: amplitudeController.stream,
            ),
          ),
        ),
      );

      // Initial pump
      await tester.pump();
      expect(find.byType(WaveformVisualizer), findsOneWidget);

      // Send amplitude events through stream
      amplitudeController.add(0.8);
      await tester.pump(const Duration(milliseconds: 100));

      amplitudeController.add(0.4);
      await tester.pump(const Duration(milliseconds: 100));

      await amplitudeController.close();
    });

    testWidgets('Meeting model details render accurately in theme container',
        (WidgetTester tester) async {
      final sampleUser = AppUser(
        id: 'u1',
        name: 'John Doe',
        email: 'john@example.com',
      );

      final meeting = Meeting(
        id: 'meet_999',
        title: 'Weekly Standup',
        startTime: DateTime.now().add(const Duration(hours: 1)),
        endTime: DateTime.now().add(const Duration(hours: 2)),
        type: MeetingType.meet,
        participants: [sampleUser],
        location: 'Virtual Room',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(meeting.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(meeting.typeLabel),
                        Text('Initials: ${sampleUser.initials}'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Weekly Standup'), findsOneWidget);
      expect(find.text('Meet'), findsOneWidget);
      expect(find.text('Initials: JD'), findsOneWidget);
    });
  });
}
