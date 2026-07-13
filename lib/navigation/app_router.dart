import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/upcoming_meetings_screen.dart';
import '../screens/threads/threads_list_screen.dart';
import '../screens/groups/groups_screen.dart';
import '../screens/groups/group_detail_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/thread/context_thread_screen.dart';
import '../screens/session/active_recording_screen.dart';
import '../screens/auth/login_screen.dart';
import '../widgets/bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref ref;
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) => RouterNotifier(ref));

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/upcoming',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      
      // Handle the loading state of the auth stream
      if (authState.isLoading) return null;

      final isAuth = authState.value != null;
      final isLoggingIn = state.uri.path == '/login';

      if (!isAuth && !isLoggingIn) return '/login';
      if (isAuth && isLoggingIn) return '/upcoming';
      
      return null;
    },
    routes: [
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
  ],
  );
});

/// The app shell that wraps tab screens with a bottom navigation bar
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
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
