import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart' as g_sign_in;
import '../providers/auth_provider.dart';
import '../services/push_notification_service.dart';
import 'firestore_repository.dart';
import '../models/user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(firestoreRepositoryProvider));
});

class AuthRepository {
  final FirebaseAuth _auth;
  final FirestoreRepository _firestoreRepo;
  bool _isGoogleSignInInitialized = false;
  g_sign_in.GoogleSignInAccount? _googleUser;
  String? _webAccessToken;

  AuthRepository(this._auth, this._firestoreRepo);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      throw Exception('Failed to sign in anonymously: $e');
    }
  }

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      final creds = await _auth.signInWithEmailAndPassword(email: email, password: password);
      // Ensure a Firestore user doc exists even for accounts created before
      // we started writing one (or via a path that skipped it).
      if (creds.user != null) {
        await _saveUserToFirestore(creds.user!);
      }
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  Future<void> createUserWithEmailAndPassword(String email, String password, {String? displayName}) async {
    try {
      final creds = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = creds.user;
      if (user != null) {
        final name = displayName?.trim();
        if (name != null && name.isNotEmpty) {
          await user.updateDisplayName(name);
          await user.reload();
        }
        await _saveUserToFirestore(_auth.currentUser ?? user, fallbackName: name);
      }
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('https://www.googleapis.com/auth/calendar.events');
        final creds = await _auth.signInWithPopup(googleProvider);
        
        final oauthCred = creds.credential as OAuthCredential?;
        if (oauthCred != null && oauthCred.accessToken != null) {
          _webAccessToken = oauthCred.accessToken;
        }

        if (creds.user != null) {
          await _saveUserToFirestore(creds.user!);
        }
        return;
      }

      if (!_isGoogleSignInInitialized) {
        await g_sign_in.GoogleSignIn.instance.initialize(
          clientId: '348324056471-jhe60lt0lp0p28ikj212j6e106bvjl4n.apps.googleusercontent.com',
        );
        _isGoogleSignInInitialized = true;
      }
      
      _googleUser = await g_sign_in.GoogleSignIn.instance.authenticate(
        scopeHint: [
          'email',
          'https://www.googleapis.com/auth/calendar.events',
        ],
      );
      
      if (_googleUser == null) return; // User canceled sign-in

      final g_sign_in.GoogleSignInAuthentication googleAuth = _googleUser!.authentication;
      
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      
      final creds = await _auth.signInWithCredential(credential);
      if (creds.user != null) {
        await _saveUserToFirestore(creds.user!);
      }
    } catch (e) {
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  Future<void> _saveUserToFirestore(User firebaseUser, {String? fallbackName}) async {
    // Prefer the auth display name; fall back to a name passed at signup, then
    // to the email's local part, so a user is never stored as "Unknown" (which
    // also fed the "Speaker 1/2" attribution problem in summaries).
    final emailLocalPart = (firebaseUser.email ?? '').split('@').first;
    final name = (firebaseUser.displayName?.trim().isNotEmpty ?? false)
        ? firebaseUser.displayName!.trim()
        : (fallbackName != null && fallbackName.trim().isNotEmpty)
            ? fallbackName.trim()
            : (emailLocalPart.isNotEmpty ? emailLocalPart : 'User');
    final appUser = AppUser(
      id: firebaseUser.uid,
      name: name,
      email: firebaseUser.email ?? '',
      avatarUrl: firebaseUser.photoURL,
    );
    await _firestoreRepo.createUser(appUser);
  }

  Future<String?> getGoogleAccessToken() async {
    if (kIsWeb) {
      if (_webAccessToken != null) return _webAccessToken;
      
      // If token is missing (e.g., after page reload), we can attempt to get it via a popup
      // This will usually auto-close if the user is already authorized
      try {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('https://www.googleapis.com/auth/calendar.events');
        final creds = await _auth.signInWithPopup(googleProvider);
        final oauthCred = creds.credential as OAuthCredential?;
        if (oauthCred != null && oauthCred.accessToken != null) {
          _webAccessToken = oauthCred.accessToken;
          return _webAccessToken;
        }
      } catch (e) {
        debugPrint('Could not refresh web access token: $e');
      }
      return null;
    }

    if (_googleUser != null) {
      final client = _googleUser!.authorizationClient;
      final authz = await client.authorizationForScopes([
        'https://www.googleapis.com/auth/calendar.events'
      ]) ?? await client.authorizeScopes([
        'https://www.googleapis.com/auth/calendar.events'
      ]);
      return authz.accessToken;
    }
    return null;
  }

  Future<void> signOut() async {
    // Detach this device's push token first (while we still know the uid) so a
    // shared device doesn't keep receiving the previous user's notifications.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await PushNotificationService.removeTokenOnSignOut(uid);
    }
    await _auth.signOut();
  }

  /// Deletes the signed-in Firebase Auth user. Throws a FirebaseAuthException
  /// with code `requires-recent-login` if the session is too old - Firebase
  /// requires a fresh sign-in before allowing account deletion.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }
}
