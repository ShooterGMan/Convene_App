import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/user.dart';
import 'package:convene/providers/auth_provider.dart';
import 'package:convene/theme/app_theme.dart';
import 'package:convene/widgets/profile_customizer_sheet.dart';

void main() {
  group('ProfileCustomizerSheet Widget Tests', () {
    final testUser = const AppUser(
      id: 'u1',
      email: 'alex@example.com',
      name: 'Alex Rivera',
      avatarUrl: null,
    );

    Widget buildTestWidget() {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: ProfileCustomizerSheet(user: testUser),
            ),
          ),
        ),
      );
    }

    testWidgets('renders display name input and preset avatars list', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Customize Profile & Avatar'), findsOneWidget);
      expect(find.text('DISPLAY NAME'), findsOneWidget);
      expect(find.text('CHOOSE PRESET AVATAR'), findsOneWidget);
      expect(find.text('OR CUSTOM IMAGE URL'), findsOneWidget);

      // Verify presets like Initials, Adventurer, Product Lead, etc.
      expect(find.text('Initials'), findsOneWidget);
      expect(find.text('Adventurer'), findsOneWidget);
      expect(find.text('Product Lead'), findsOneWidget);
      expect(find.text('AI Assistant / Bot'), findsOneWidget);
    });

    testWidgets('allows selecting a preset avatar and updates custom URL field', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      // Tap on Adventurer preset avatar
      await tester.tap(find.text('Adventurer'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));

      // URL field should now be filled with the preset URL
      final urlField = find.widgetWithText(TextField, 'https://example.com/my-photo.jpg');
      expect(urlField, findsOneWidget);

      // Tap initials to clear custom avatar
      await tester.tap(find.text('Initials'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
