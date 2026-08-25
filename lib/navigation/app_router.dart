import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/upcoming_meetings_screen.dart';
import '../screens/threads/threads_list_screen.dart';
import '../screens/groups/groups_screen.dart';
import '../screens/groups/group_detail_screen.dart';
import '../screens/groups/join_group_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/thread/context_thread_screen.dart';
import '../screens/session/active_recording_screen.dart';
import '../screens/session/live_meeting_screen.dart';
import '../screens/session/pre_join_screen.dart';
import '../screens/auth/login_screen.dart';
import '../widgets/bottom_nav_bar.dart';
import '../screens/onboarding/onboarding_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/data_providers.dart';
import '../providers/onboarding_provider.dart';
import '../services/push_notification_service.dart';
import '../models/user.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
  final Ref ref;
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) => RouterNotifier(ref));

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    // No `initialLocation` here on purpose: setting one forces GoRouter to
    // discard whatever URL the browser actually loaded (e.g. a shared
    // /pre-join/xyz or /join-group/abc link) and start from that fixed path
    // instead - which is exactly why those links silently dumped everyone on
    // the home screen instead of the intended meeting/group.
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);

      // Handle the loading state of the auth stream
      if (authState.isLoading) return null;

      final isAuth = authState.value != null;
      final isLoggingIn = state.uri.path == '/login';

      // Preserve where the user was actually headed (e.g. a shared group
      // invite link) through the login redirect, instead of always dropping
      // them on the home screen afterwards.
      if (!isAuth && !isLoggingIn) {
        final destination = Uri.encodeComponent(state.uri.toString());
        return '/login?redirect=$destination';
      }
      if (isAuth && isLoggingIn) {
        final redirectParam = state.uri.queryParameters['redirect'];
        if (redirectParam != null && redirectParam.isNotEmpty) {
          return Uri.decodeComponent(redirectParam);
        }
        return '/upcoming';
      }
      // Bare root (no path at all, e.g. someone typed just the domain) has
      // no matching route - default signed-in visitors to the home screen.
      if (isAuth && (state.uri.path == '/' || state.uri.path.isEmpty)) {
        return '/upcoming';
      }

      return null;
    },
    routes: [
      // Explicit root route so a fresh load at "/" (which no other route
      // matches) always resolves instead of throwing go_router's "no route"
      // error. The global redirect above already sends unauthenticated users
      // to /login before this runs; authenticated users land on /upcoming.
      GoRoute(
        path: '/',
        redirect: (context, state) => '/upcoming',
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
    // Shell route for bottom navigation
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/upcoming',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: UpcomingMeetingsScreen(),
          ),
        ),
        GoRoute(
          path: '/threads',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ThreadsListScreen(),
          ),
        ),
        GoRoute(
          path: '/groups',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: GroupsScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),

    // Full-screen routes (no bottom nav)
    GoRoute(
      path: '/thread/:threadId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final threadId = state.pathParameters['threadId']!;
        return ContextThreadScreen(threadId: threadId);
      },
    ),
    GoRoute(
      path: '/recording/:meetingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetingId = state.pathParameters['meetingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ActiveRecordingScreen(
          meetingId: meetingId,
          meetingTitle: extra['title'] as String? ?? 'Untitled Meeting',
          participants: (extra['participants'] as List?)?.cast<AppUser>() ?? <AppUser>[],
          groupId: extra['groupId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/group/:groupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final groupId = state.pathParameters['groupId']!;
        return GroupDetailScreen(groupId: groupId);
      },
    ),
    GoRoute(
      path: '/join-group/:inviteCode',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final inviteCode = state.pathParameters['inviteCode']!;
        return JoinGroupScreen(inviteCode: inviteCode);
      },
    ),
    GoRoute(
      path: '/pre-join/:meetingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetingId = state.pathParameters['meetingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return PreJoinScreen(
          meetingId: meetingId,
          groupId: extra['groupId'] as String? ?? '',
          title: extra['title'] as String? ?? 'Meeting',
        );
      },
    ),
    GoRoute(
      path: '/live/:meetingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final meetingId = state.pathParameters['meetingId']!;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return LiveMeetingScreen(
          meetingId: meetingId,
          groupId: extra['groupId'] as String? ?? '',
          isMicMuted: extra['isMicMuted'] as bool? ?? false,
          isCameraMuted: extra['isCameraMuted'] as bool? ?? false,
          displayName: extra['displayName'] as String? ?? '',
        );
      },
    ),
  ],
  // Any path that still matches no route (a stale link, a typo, an odd
  // fresh-load URL) auto-recovers to the home screen instead of stranding
  // the user on go_router's raw error page.
  errorBuilder: (context, state) => const _RouteErrorRedirect(),
  );
});

/// Shown only if go_router can't match a route. Bounces to /upcoming on the
/// next frame rather than leaving the user on a dead error page.
class _RouteErrorRedirect extends StatefulWidget {
  const _RouteErrorRedirect();

  @override
  State<_RouteErrorRedirect> createState() => _RouteErrorRedirectState();
}

class _RouteErrorRedirectState extends State<_RouteErrorRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/upcoming');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// The app shell that wraps tab screens with a bottom navigation bar.
/// Notification signal lives on the nav tabs themselves (badges in
/// ConveneBottomNavBar) rather than a floating bell, plus a chime the
/// moment a genuinely new notification arrives while the app is open.
class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register this device for push notifications once a user is signed in.
    // Safe to call on every rebuild - the service is idempotent (no-ops after
    // the first successful registration for the session).
    final currentUid = ref.watch(currentUserProvider)?.uid;
    if (currentUid != null) PushNotificationService.initForUser(currentUid);

    ref.listen(notificationsProvider, (previous, next) {
      final prevUnread = previous?.value?.where((n) => !n.isRead).length ?? -1;
      final nextUnread = next.value?.where((n) => !n.isRead).length ?? 0;
      // prevUnread < 0 means this is the first emission (app just opened) -
      // don't chime for a backlog of notifications that already existed.
      if (prevUnread >= 0 && nextUnread > prevUnread) {
        SystemSound.play(SystemSoundType.alert);
      }
    });

    // First-run tutorial overlays the whole shell until the user finishes or
    // skips it (persisted, so it only ever shows once). null = still loading
    // the flag, so we render nothing extra to avoid a flash.
    final onboardingSeen = ref.watch(onboardingSeenProvider);

    return Scaffold(
      body: Stack(
        children: [
          child,
          if (onboardingSeen == false)
            const Positioned.fill(child: OnboardingScreen()),
        ],
      ),
      bottomNavigationBar: ConveneBottomNavBar(
        currentIndex: _calculateSelectedIndex(context),
        onTap: (index) => _onItemTapped(index, context),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/upcoming')) return 0;
    if (location.startsWith('/threads')) return 1;
    if (location.startsWith('/groups')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/upcoming');
        break;
      case 1:
        context.go('/threads');
        break;
      case 2:
        context.go('/groups');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }
}
