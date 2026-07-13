import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';

// Provides the FirebaseAuth instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// StreamProvider that listens to auth state changes (logged in / logged out)
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

// Provides the current user directly (null if not logged in)
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value;
});

// Provides the AppUser for the authenticated user, falling back to an empty user
final appUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const AppUser(
      id: 'mock-sarah',
      name: 'Sarah Connor',
      email: 'sarah@convene.app',
      avatarUrl: 'https://i.pravatar.cc/150?u=sarah',
      isSelf: true,
    );
  }
  return AppUser(
    id: user.uid,
    name: user.displayName ?? 'User',
    email: user.email ?? 'no-email@convene.app',
    avatarUrl: user.photoURL,
    isSelf: true,
  );
});

