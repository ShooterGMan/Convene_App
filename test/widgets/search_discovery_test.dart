import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/context_thread.dart';
import 'package:convene/models/group.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';
import 'package:convene/providers/data_providers.dart';
import 'package:convene/screens/search/search_discovery_screen.dart';
import 'package:convene/theme/app_theme.dart';

void main() {
  group('SearchDiscoveryScreen Widget Tests', () {
    final testMeetings = [
      Meeting(
        id: 'meet_1',
        title: 'Mobile Architecture Sync',
        startTime: DateTime(2026, 8, 28, 14, 0),
        endTime: DateTime(2026, 8, 28, 15, 0),
        type: MeetingType.meet,
        participants: const [
          AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
          AppUser(id: 'u2', email: 'sarah@example.com', name: 'Sarah Chen'),
        ],
        isImportant: true,
      ),
    ];

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
            type: SmartBlockType.summary,
            content: 'Reviewed typography scale and glassmorphism cards.',
          ),
          SmartBlock(
            id: 'b2',
            type: SmartBlockType.actionItem,
            content: 'Export Flutter icons to font file',
            assignee: 'Sarah',
            priority: SmartBlockPriority.high,
          ),
          SmartBlock(
            id: 'b3',
            type: SmartBlockType.decision,
            content: 'Adopt Google Fonts Plus Jakarta Sans as primary font.',
          ),
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
          meetingsProvider.overrideWith((ref) => Stream.value(testMeetings)),
          threadsProvider.overrideWith((ref) => Stream.value(testThreads)),
          groupsProvider.overrideWith((ref) => Stream.value(testGroups)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SearchDiscoveryScreen(),
        ),
      );
    }

    testWidgets('renders search input and category filter chips', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      expect(find.text('Search & Discovery'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('Topics'), findsOneWidget);
      expect(find.text('Action Items'), findsOneWidget);
      expect(find.text('Decisions'), findsOneWidget);
    });

    testWidgets('searches and finds matching topic by query', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Architecture');
      await tester.pumpAndSettle();

      expect(find.text('Mobile Architecture Sync'), findsOneWidget);
      expect(find.text('MEETING'), findsOneWidget);
    });

    testWidgets('filters action items and decisions when respective chips are selected', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'font');
      await tester.pumpAndSettle();

      expect(find.text('Export Flutter icons to font file'), findsOneWidget);
      expect(find.text('ACTION ITEM'), findsOneWidget);
      expect(find.text('Adopt Google Fonts Plus Jakarta Sans as primary font.'), findsOneWidget);
      expect(find.text('DECISION'), findsOneWidget);

      // Tap "Decisions" filter chip
      await tester.tap(find.text('Decisions'));
      await tester.pumpAndSettle();

      expect(find.text('ACTION ITEM'), findsNothing);
      expect(find.text('Adopt Google Fonts Plus Jakarta Sans as primary font.'), findsOneWidget);
    });
  });
}
