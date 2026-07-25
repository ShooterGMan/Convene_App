import * as admin from "firebase-admin";

export type NotificationType =
  | "group_invite"
  | "group_invite_accepted"
  | "group_invite_declined"
  | "meeting_added";

/**
 * Writes an in-app notification to a user's `notifications` subcollection.
 * This is in-app only (visible next time they open the app / via the bell
 * icon) - there's no push/FCM wiring yet, so it won't alert someone whose
 * app isn't open.
 */
export async function notifyUser(
  userId: string,
  notification: {
    type: NotificationType;
    title: string;
    body: string;
    route?: string;
    relatedId?: string;
  }
) {
  await admin
    .firestore()
    .collection("users")
    .doc(userId)
    .collection("notifications")
    .add({
      ...notification,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
