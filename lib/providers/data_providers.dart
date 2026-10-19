import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';
import '../models/context_thread.dart';
import '../models/group.dart';
import '../models/group_invite.dart';
import '../models/external_calendar_event.dart';
import '../models/meeting.dart';
import '../repositories/firestore_repository.dart';
import '../services/calendar_service.dart';
import 'auth_provider.dart';

/// Groups the current user is a member of. Firestore rules require the query
/// itself to be filtered to what's allowed (an unfiltered collection query
/// gets rejected outright), so this always scopes to the signed-in user.
final groupsProvider = StreamProvider<List<Group>>((ref) async* {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }
  yield* ref.watch(firestoreRepositoryProvider).streamGroups(uid);
});

/// Meetings visible to the current user (their own + their groups'). Depends
/// on groupsProvider resolving first so it knows which group IDs to include.
final meetingsProvider = StreamProvider<List<Meeting>>((ref) async* {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }
  final groups = await ref.watch(groupsProvider.future);
  final groupIds = groups.map((g) => g.id).toList();
  yield* ref.watch(firestoreRepositoryProvider).streamMeetings(uid, groupIds);
});

/// Threads (AI summaries) visible to the current user (their own + their
/// groups'). Depends on groupsProvider resolving first, same as meetings.
final threadsProvider = StreamProvider<List<ContextThread>>((ref) async* {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }
  final groups = await ref.watch(groupsProvider.future);
  final groupIds = groups.map((g) => g.id).toList();
  yield* ref.watch(firestoreRepositoryProvider).streamThreads(uid, groupIds);
});

/// Pending group invites addressed to the current user, across every group.
final pendingInvitesProvider = StreamProvider<List<GroupInvite>>((ref) async* {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }
  yield* ref.watch(firestoreRepositoryProvider).streamPendingInvites(uid);
});

/// In-app notifications for the current user, newest first.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) async* {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }
  yield* ref.watch(firestoreRepositoryProvider).streamNotifications(uid);
});

class CalendarAutoSyncNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('google_calendar_autosync') ?? true;
  }

  Future<void> toggle(bool val) async {
    state = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('google_calendar_autosync', val);
  }
}

final calendarAutoSyncProvider = NotifierProvider<CalendarAutoSyncNotifier, bool>(CalendarAutoSyncNotifier.new);

/// Fetches external Google Calendar events for a rolling 4-month window (-1 to +3 months)
final externalCalendarEventsProvider = FutureProvider<List<ExternalCalendarEvent>>((ref) async {
  final autoSync = ref.watch(calendarAutoSyncProvider);
  if (!autoSync) return [];

  final svc = ref.watch(calendarServiceProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 1, 1);
  final end = DateTime(now.year, now.month + 3, 0);
  return svc.fetchExternalEvents(start, end);
});
