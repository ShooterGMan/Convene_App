import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/app_notification.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';
import 'package:convene/providers/auth_provider.dart';
import 'package:convene/providers/data_providers.dart';
import 'package:convene/theme/app_theme.dart';
import 'package:convene/widgets/notification_bell.dart';

void main() {
  group('NotificationBell & Panel Widget Tests', () {
    final upcomingMeeting = Meeting(
      id: 'meet_upcoming',
      title: 'Mobile Architecture Sync',
      startTime: DateTime.now().add(const Duration(hours: 2)),
      endTime: DateTime.now().add(const Duration(hours: 3)),
      type: MeetingType.meet,
      participants: const [
        AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
      ],
    );

    final pastMeeting = Meeting(
      id: 'meet_past',
      title: 'Past Retrospective',
      startTime: DateTime.now().subtract(const Duration(hours: 4)),
      endTime: DateTime.now().subtract(const Duration(hours: 3)),
      type: MeetingType.meet,
      threadId: 'thread_retro_1',
      participants: const [
        AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
      ],
    );

    final testNotifications = [
      AppNotification(
        id: 'notif_1',
        type: 'meeting_invite',
        title: 'Meeting invite',
        body: 'Alex invited you to "Mobile Architecture Sync"',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        isRead: false,
        route: '/pre-join/meet_upcoming',
        relatedId: 'meet_upcoming',
      ),
      AppNotification(
        id: 'notif_2',
        type: 'meeting_invite',
        title: 'Meeting invite',
        body: 'Sarah invited you to "Past Retrospective"',
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        isRead: false,
        route: '/pre-join/meet_past',
        relatedId: 'meet_past',
      ),
      AppNotification(
        id: 'notif_3',
        type: 'topic_summary',
        title: 'Summary ready',
        body: 'Summary generated for "Sprint Planning"',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        isRead: true,
        route: '/thread/thread_1',
        relatedId: 'thread_1',
      ),
    ];

    Widget buildTestWidget() {
      return ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref) => Stream.value(testNotifications)),
          meetingsProvider.overrideWith((ref) => Stream.value([upcomingMeeting, pastMeeting])),
          currentUserProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: NotificationBell(),
            ),
          ),
        ),
      );
    }

    testWidgets('renders bell with unread badge count', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 2 unread notifications
    });

    testWidgets('distinguishes active meeting invites from expired/missed meeting invites', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the bell to open the panel
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Invites'), findsOneWidget);

      // Active upcoming meeting invite has Quick RSVP
      expect(find.text('Quick RSVP: '), findsOneWidget);
      expect(find.text('Going'), findsOneWidget);

      // Past meeting invite shows Missed / Ended badge and View Summary button
      expect(find.text('MISSED / ENDED'), findsOneWidget);
      expect(find.text('Invite expired · Meeting ended'), findsOneWidget);
      expect(find.text('View Summary'), findsOneWidget);
    });

    testWidgets('filters notifications when Unread or Invites chip is selected', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open panel
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      // Tap "Unread" chip
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();

      expect(find.text('Summary ready'), findsNothing);
    });
  });
}
