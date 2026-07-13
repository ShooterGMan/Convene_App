import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/context_thread.dart';
import '../models/group.dart';
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
    await _firestore.collection('users').doc(user.id).set(user.toJson());
  }

  Future<AppUser?> getUser(String id) async {
    final doc = await _firestore.collection('users').doc(id).get();
    if (doc.exists && doc.data() != null) {
      return AppUser.fromJson(doc.data()!);
    }
    return null;
  }

  // Groups
  Future<void> createGroup(Group group) async {
    await _firestore.collection('groups').doc(group.id).set(group.toJson());
  }

  Stream<List<Group>> streamGroups() {
    return _firestore.collection('groups').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Group.fromJson(doc.data())).toList();
    });
  }

  // Meetings
  Future<void> createMeeting(Meeting meeting) async {
    await _firestore.collection('meetings').doc(meeting.id).set(meeting.toJson());
  }

  Stream<List<Meeting>> streamMeetings() {
    return _firestore.collection('meetings').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Meeting.fromJson(doc.data())).toList();
    });
  }

  // Threads
  Future<void> createThread(ContextThread thread) async {
    await _firestore.collection('threads').doc(thread.id).set(thread.toJson());
  }

  Stream<List<ContextThread>> streamThreads() {
    return _firestore.collection('threads').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ContextThread.fromJson(doc.data())).toList();
    });
  }
}
