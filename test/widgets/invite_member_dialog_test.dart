import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:convene/models/group.dart';
import 'package:convene/models/user.dart';
import 'package:convene/theme/app_theme.dart';
import 'package:convene/widgets/invite_member_dialog.dart';

void main() {
  group('InviteMemberDialog Tests', () {
    final testGroup = Group(
      id: 'grp_123',
      name: 'Mobile Core Team',
      inviteCode: 'TEST9999',
      members: const [
        AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
      ],
      createdBy: const AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
      createdAt: DateTime(2026, 1, 1),
    );

    Widget buildTestWidget() {
      return ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: InviteMemberDialog(group: testGroup),
            ),
          ),
        ),
      );
    }

    testWidgets('renders dialog with By Email and QR Code tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Invite to "Mobile Core Team"'), findsOneWidget);
      expect(find.text('By Email'), findsOneWidget);
      expect(find.text('QR Code & Link'), findsOneWidget);
      expect(find.text('Send In-App Invite'), findsOneWidget);
    });

    testWidgets('switches to QR Code tab and renders QrImageView with code', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap QR Code tab
      await tester.tap(find.text('QR Code & Link'));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('TEST9999'), findsOneWidget);
      expect(find.text('Copy Shareable Link'), findsOneWidget);
    });
  });
}
