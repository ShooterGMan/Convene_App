import * as admin from "firebase-admin";

export type NotificationType =
  | "group_invite"
  | "group_invite_accepted"
  | "group_invite_declined"
  | "meeting_added"
  | "summary_ready"
  | "action_assigned";

/**
 * Writes an in-app notification to a user's `notifications` subcollection AND
 * sends a push (FCM) to their registered devices, so it reaches them even when
 * the app is closed. The in-app copy is the source of truth (bell/feed); the
 * push is best-effort and never blocks or fails the caller.
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

  try {
    await sendPush(userId, notification.title, notification.body, notification.route);
  } catch (e) {
    console.error(`Push send failed for ${userId} (non-fatal):`, e);
  }
}

/** Sends an FCM push to all of a user's registered devices, pruning any tokens
 * FCM reports as no longer valid. */
async function sendPush(userId: string, title: string, body: string, route?: string) {
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(userId).get();
  const tokens = (userDoc.data()?.fcmTokens || []) as string[];
  if (tokens.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { route: route || "/" },
    webpush: {
      notification: { title, body, icon: "/icons/Icon-192.png" },
      fcmOptions: { link: route || "/" },
    },
    // No explicit channelId - FCM uses its auto-created default channel, which
    // avoids "notification silently dropped because the channel doesn't exist"
    // (we don't create native channels).
    android: { priority: "high" },
  });

  // Remove tokens FCM says are dead so the list doesn't grow stale forever.
  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code || "";
      if (code.includes("registration-token-not-registered") || code.includes("invalid-argument")) {
        dead.push(tokens[i]);
      }
    }
  });
  if (dead.length > 0) {
    await db.collection("users").doc(userId).set(
      { fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead) },
      { merge: true }
    );
  }
}
