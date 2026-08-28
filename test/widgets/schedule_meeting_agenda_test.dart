import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/group.dart';
import 'package:convene/models/user.dart';
import 'package:convene/providers/auth_provider.dart';
import 'package:convene/providers/data_providers.dart';
import 'package:convene/theme/app_theme.dart';
import 'package:convene/widgets/schedule_meeting_sheet.dart';

void main() {
  group('ScheduleMeetingSheet Agenda Tests', () {
    final testUser = const AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera');

    Widget buildTestScreen() {
      return ProviderScope(
        overrides: [
          appUserProvider.overrideWith((ref) => testUser),
          groupsProvider.overrideWith((ref) => Stream.value(<Group>[])),
          threadsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: ScheduleMeetingSheet(),
            ),
          ),
        ),
      );
    }

    testWidgets('renders AI Smart Agenda section and allows custom agenda addition', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      expect(find.text('Schedule Meeting'), findsOneWidget);
      expect(find.text('Meeting Agenda & Prep'), findsOneWidget);
      expect(find.text('✨ AI Agenda'), findsOneWidget);

      // Add a custom agenda item
      final addField = find.widgetWithText(TextField, 'Add agenda item...');
      expect(addField, findsOneWidget);
      await tester.enterText(addField, 'Review API Rate Limits');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Review API Rate Limits'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('generates AI agenda items upon clicking AI Agenda button', (tester) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Enter title first
      final titleField = find.widgetWithText(TextField, 'Meeting Title');
      await tester.enterText(titleField, 'Mobile Sprint Planning');
      await tester.pumpAndSettle();

      // Tap AI Agenda button
      await tester.tap(find.text('✨ AI Agenda'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Sprint goals & scope review'), findsOneWidget);
      expect(find.text('Capacity & team bandwidth alignment'), findsOneWidget);
    });
  });
}
