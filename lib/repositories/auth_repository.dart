import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart' as g_sign_in;
import '../providers/auth_provider.dart';
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
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  Future<void> createUserWithEmailAndPassword(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('https://www.googleapis.com/auth/calendar.events');
        final creds = await _auth.signInWithPopup(googleProvider);
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

  Future<void> _saveUserToFirestore(User firebaseUser) async {
    final appUser = AppUser(
      id: firebaseUser.uid,
      name: firebaseUser.displayName ?? 'Unknown',
      email: firebaseUser.email ?? '',
      avatarUrl: firebaseUser.photoURL,
    );
    await _firestoreRepo.createUser(appUser);
  }

  Future<String?> getGoogleAccessToken() async {
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
    await _auth.signOut();
  }
}
