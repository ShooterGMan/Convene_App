import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';

// Provides the FirebaseAuth instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// StreamProvider that listens to auth state changes (logged in / logged out),
// as well as profile updates (display name, photo) via userChanges() so
// edits made in Settings propagate immediately without a full re-login.
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.userChanges();
});

// Provides the current user directly (null if not logged in)
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value;
});

// Provides the AppUser for the authenticated user. Callers must only read this
// once `authStateProvider` has resolved (see the loading gate in main.dart) -
// it has no real identity to fall back to when nobody is signed in.
final appUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const AppUser(
      id: '',
      name: 'Guest',
      email: '',
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

