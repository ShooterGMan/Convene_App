import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../models/context_thread.dart';
import '../models/group.dart';
import '../models/group_invite.dart';
import '../models/meeting.dart';
import '../repositories/firestore_repository.dart';
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
