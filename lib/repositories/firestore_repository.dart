import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../models/context_thread.dart';
import '../models/group.dart';
import '../models/group_invite.dart';
import '../models/meeting.dart';
import '../models/user.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository(ref.watch(firestoreProvider));
});

class FirestoreRepository {
  final FirebaseFirestore _firestore;

  FirestoreRepository(this._firestore);

  // Users
  Future<void> createUser(AppUser user) async {
    // merge so re-signing-in (which re-runs this) never wipes fields the user
    // has since changed elsewhere.
    await _firestore.collection('users').doc(user.id).set(user.toJson(), SetOptions(merge: true));
  }

  Future<AppUser?> getUser(String id) async {
    final doc = await _firestore.collection('users').doc(id).get();
    if (doc.exists && doc.data() != null) {
      return AppUser.fromJson(doc.data()!);
    }
    return null;
  }

  Future<void> deleteUser(String id) async {
    await _firestore.collection('users').doc(id).delete();
  }

  // Groups
  Future<void> createGroup(Group group) async {
    await _firestore.collection('groups').doc(group.id).set(group.toJson());
  }

  /// Firestore rejects unfiltered collection-wide queries when the security
  /// rules aren't a simple field match (ours also allows group members), so
  /// this must be filtered client-side to exactly the condition the rules
  /// check, rather than relying on rules to silently filter a broad query.
  Stream<List<Group>> streamGroups(String userId) {
    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Group.fromJson(doc.data())).toList();
    });
  }

  Future<void> updateGroupName(String groupId, String name) async {
    await _firestore.collection('groups').doc(groupId).update({'name': name});
  }

  Future<void> addThreadToGroup(String groupId, String threadId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'threadIds': FieldValue.arrayUnion([threadId]),
    });
  }

  /// Pending group invites addressed to this user, across every group at
  /// once (collection group query - see firestore.rules for the matching
  /// permission).
  Stream<List<GroupInvite>> streamPendingInvites(String userId) {
    return _firestore
        .collectionGroup('pendingInvites')
        .where('invitedUserId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => GroupInvite.fromJson(doc.data())).toList();
    });
  }

  // Meetings
  Future<void> createMeeting(Meeting meeting) async {
    await _firestore.collection('meetings').doc(meeting.id).set(meeting.toJson());
  }

  /// Meetings visible to this user: ones they're a participant in, plus ones
  /// belonging to any group they're a member of (so upcoming group meetings
  /// show up before anyone's actually joined) - matches firestore.rules.
  Stream<List<Meeting>> streamMeetings(String userId, List<String> groupIds) {
    final query = groupIds.isEmpty
        ? _firestore.collection('meetings').where('participantIds', arrayContains: userId)
        : _firestore.collection('meetings').where(
            Filter.or(
              Filter('participantIds', arrayContains: userId),
              Filter('groupId', whereIn: groupIds.take(30).toList()),
            ),
          );

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Meeting.fromJson(doc.data())).toList();
    });
  }

  Future<void> setMeetingImportant(String meetingId, bool isImportant) async {
    await _firestore.collection('meetings').doc(meetingId).update({'isImportant': isImportant});
  }

  Future<void> setMeetingRsvp(String meetingId, String userId, RsvpStatus status) async {
    await _firestore.collection('meetings').doc(meetingId).update({
      'rsvps.$userId': status.name,
    });
  }

  /// Watches a single meeting doc so callers can detect the moment the
  /// server-side egress pipeline attaches a `threadId` (i.e. the summary is ready).
  Stream<Meeting?> streamMeeting(String meetingId) {
    return _firestore.collection('meetings').doc(meetingId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Meeting.fromJson(doc.data()!);
    });
  }

  // Threads
  Future<void> createThread(ContextThread thread) async {
    await _firestore.collection('threads').doc(thread.id).set(thread.toJson());
  }

  /// Threads visible to this user: same rule as meetings (participant or
  /// group member). No server-side orderBy here - combined with the OR filter
  /// that would need a composite index, so callers sort client-side instead.
  Stream<List<ContextThread>> streamThreads(String userId, List<String> groupIds) {
    final query = groupIds.isEmpty
        ? _firestore.collection('threads').where('participantIds', arrayContains: userId)
        : _firestore.collection('threads').where(
            Filter.or(
              Filter('participantIds', arrayContains: userId),
              Filter('groupId', whereIn: groupIds.take(30).toList()),
            ),
          );

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ContextThread.fromJson(doc.data())).toList();
    });
  }

  /// Persists the full block list for a thread. Firestore rules only allow
  /// this write to touch the `blocks` field, so callers must pass the whole
  /// (updated) list rather than a partial patch.
  Future<void> updateThreadBlocks(String threadId, List<SmartBlock> blocks) async {
    await _firestore.collection('threads').doc(threadId).update({
      'blocks': blocks.map((b) => b.toJson()).toList(),
    });
  }

  // Notifications
  Stream<List<AppNotification>> streamNotifications(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => AppNotification.fromJson(doc.id, doc.data())).toList();
    });
  }

  Future<void> markNotificationRead(String userId, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // Comments (on threads)
  Future<void> addComment(String threadId, ThreadComment comment) async {
    await _firestore
        .collection('threads')
        .doc(threadId)
        .collection('comments')
        .doc(comment.id)
        .set(comment.toJson());
  }

  Stream<List<ThreadComment>> streamComments(String threadId) {
    return _firestore
        .collection('threads')
        .doc(threadId)
        .collection('comments')
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ThreadCommentJson.fromJson(doc.data())).toList();
    });
  }
}
