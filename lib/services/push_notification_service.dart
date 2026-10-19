import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Web Push (VAPID) public key. Generate it in Firebase Console →
/// Project Settings → Cloud Messaging → "Web Push certificates" → Key pair,
/// and paste the key string here. Until it's set, web push is skipped
/// (Android push still works without it). This value is public/not secret.
const String kWebPushVapidKey = 'BEgxSsLl7L6qryk3X7H7tPSIE5ipU294hPsvEf0xApJuwR4r5lFYabse3BzDhb-WfJpZnCDSKCJOTGJesmOd8Hg';

/// Registers this device for push notifications and keeps its FCM token stored
/// on the user's Firestore doc (in `fcmTokens`). The actual pushes are sent
/// server-side from Cloud Functions (see functions/src/notifications.ts).
///
/// Display is handled elsewhere: the web service worker / Android system show
/// pushes when the app is backgrounded or closed; when it's in the foreground
/// the in-app notification bell + chime already cover it, so we don't
/// double-notify here.
class PushNotificationService {
  static bool _initialized = false;

  /// Call once a user is signed in. Safe to call repeatedly - it no-ops after
  /// the first successful registration for the session.
  static Future<void> initForUser(String uid) async {
    if (_initialized || uid.isEmpty) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // User declined - nothing more to do, but don't retry endlessly.
        _initialized = true;
        return;
      }

      // Web requires the VAPID key; skip cleanly if it hasn't been set yet.
      final String? token = kIsWeb
          ? (kWebPushVapidKey.isEmpty ? null : await messaging.getToken(vapidKey: kWebPushVapidKey))
          : await messaging.getToken();

      if (token != null && token.isNotEmpty) {
        await _saveToken(uid, token);
      }

      // Keep the stored token current if FCM rotates it.
      messaging.onTokenRefresh.listen((t) {
        if (t.isNotEmpty) _saveToken(uid, t);
      });

      _initialized = true;
    } catch (e) {
      debugPrint('Push notification init failed (non-fatal): $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmTokens': FieldValue.arrayUnion([token])},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  /// Clear the current device's token on sign-out so a shared device doesn't
  /// keep pushing the previous user's notifications here.
  static Future<void> removeTokenOnSignOut(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmTokens': FieldValue.arrayRemove([token])},
          SetOptions(merge: true),
        );
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Failed to remove FCM token: $e');
    }
    _initialized = false;
  }
}
