import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/context_thread.dart';
import 'package:convene/models/group.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';
import 'package:convene/providers/auth_provider.dart';
import 'package:convene/providers/data_providers.dart';
import 'package:convene/screens/tasks/personal_tasks_insights_screen.dart';
import 'package:convene/theme/app_theme.dart';

void main() {
  group('PersonalTasksInsightsScreen Widget Tests', () {
    final testUser = const AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera');

    final testThreads = [
      ContextThread(
        id: 'thread_1',
        meetingId: 'meet_1',
        meetingTitle: 'Design System Sprint Review',
        createdAt: DateTime(2026, 8, 27, 10, 0),
        participants: const [
          AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
        ],
        blocks: [
          SmartBlock(
            id: 'b1',
            type: SmartBlockType.actionItem,
            content: 'Export Flutter icons to font file',
            assignee: 'Alex',
            priority: SmartBlockPriority.high,
            isCompleted: false,
          ),
          SmartBlock(
            id: 'b2',
            type: SmartBlockType.actionItem,
            content: 'Verify color tokens in dark mode',
            assignee: 'Sarah',
            priority: SmartBlockPriority.low,
            isCompleted: true,
          ),
        ],
      ),
    ];

    final testMeetings = [
      Meeting(
        id: 'meet_1',
        title: 'Design System Sprint Review',
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1)),
        type: MeetingType.meet,
        participants: const [
          AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
        ],
      ),
    ];

    final testGroups = [
      Group(
        id: 'group_1',
        name: 'Design Engineering',
        members: const [
          AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
        ],
        threadIds: const ['thread_1'],
        createdBy: const AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    Widget buildTestScreen() {
      return ProviderScope(
        overrides: [
          appUserProvider.overrideWith((ref) => testUser),
          threadsProvider.overrideWith((ref) => Stream.value(testThreads)),
          meetingsProvider.overrideWith((ref) => Stream.value(testMeetings)),
          groupsProvider.overrideWith((ref) => Stream.value(testGroups)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PersonalTasksInsightsScreen(),
        ),
      );
    }

    testWidgets('renders action items with priority badge and filters', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      expect(find.text('Tasks & Productivity'), findsOneWidget);
      expect(find.text('Export Flutter icons to font file'), findsOneWidget);
      expect(find.text('Verify color tokens in dark mode'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);

      // Filter by "To Do"
      await tester.tap(find.text('To Do'));
      await tester.pumpAndSettle();

      expect(find.text('Export Flutter icons to font file'), findsOneWidget);
      expect(find.text('Verify color tokens in dark mode'), findsNothing);
    });

    testWidgets('switches to Productivity Insights tab and renders velocity metrics', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Switch to Productivity tab
      await tester.tap(find.text('Productivity Insights'));
      await tester.pumpAndSettle();

      expect(find.text('Personal Velocity & Impact'), findsOneWidget);
      expect(find.text('Meeting Hours'), findsOneWidget);
      expect(find.text('Task Velocity'), findsOneWidget);
      expect(find.text('TASKS ACROSS GROUPS'), findsOneWidget);
    });
  });
}
