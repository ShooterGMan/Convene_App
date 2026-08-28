import 'package:flutter_test/flutter_test.dart';

/// Pure representation of the app's routing redirect algorithm
/// (as implemented in lib/navigation/app_router.dart).
String? calculateAuthRedirect({
  required bool isLoading,
  required bool isAuthenticated,
  required Uri currentUri,
}) {
  if (isLoading) return null;

  final isLoggingIn = currentUri.path == '/login';

  if (!isAuthenticated && !isLoggingIn) {
    final destination = Uri.encodeComponent(currentUri.toString());
    return '/login?redirect=$destination';
  }

  if (isAuthenticated && isLoggingIn) {
    final redirectParam = currentUri.queryParameters['redirect'];
    if (redirectParam != null && redirectParam.isNotEmpty) {
      return Uri.decodeComponent(redirectParam);
    }
    return '/upcoming';
  }

  if (isAuthenticated && (currentUri.path == '/' || currentUri.path.isEmpty)) {
    return '/upcoming';
  }

  return null;
}

void main() {
  group('Auth Redirect Routing Tests', () {
    test('returns null when auth state is loading', () {
      final redirect = calculateAuthRedirect(
        isLoading: true,
        isAuthenticated: false,
        currentUri: Uri.parse('/upcoming'),
      );
      expect(redirect, isNull);
    });

    group('Unauthenticated User', () {
      test('redirects from protected /upcoming to /login with encoded redirect param', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: false,
          currentUri: Uri.parse('/upcoming'),
        );
        expect(redirect, '/login?redirect=%2Fupcoming');
      });

      test('redirects from shared meeting link /pre-join/meet_99 to /login preserving target', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: false,
          currentUri: Uri.parse('/pre-join/meet_99'),
        );
        expect(redirect, '/login?redirect=%2Fpre-join%2Fmeet_99');
      });

      test('redirects from shared group invite link /join-group/CODE123 to /login preserving target', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: false,
          currentUri: Uri.parse('/join-group/CODE123'),
        );
        expect(redirect, '/login?redirect=%2Fjoin-group%2FCODE123');
      });

      test('allows /login without redirect loop', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: false,
          currentUri: Uri.parse('/login'),
        );
        expect(redirect, isNull);
      });
    });

    group('Authenticated User', () {
      test('redirects from /login to /upcoming by default', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/login'),
        );
        expect(redirect, '/upcoming');
      });

      test('redirects from /login to preserved target URL after successful login', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/login?redirect=%2Fgroup%2Fgrp_tech'),
        );
        expect(redirect, '/group/grp_tech');
      });

      test('redirects from root "/" to /upcoming', () {
        final redirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/'),
        );
        expect(redirect, '/upcoming');
      });

      test('allows navigation to protected screens without redirection', () {
        final upcomingRedirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/upcoming'),
        );
        expect(upcomingRedirect, isNull);

        final threadRedirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/thread/th_456'),
        );
        expect(threadRedirect, isNull);

        final settingsRedirect = calculateAuthRedirect(
          isLoading: false,
          isAuthenticated: true,
          currentUri: Uri.parse('/settings'),
        );
        expect(settingsRedirect, isNull);
      });
    });
  });
}
