import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { AccessToken } from "livekit-server-sdk";
import { requiredEnv } from "./config";
import { canJoinMeeting } from "./meeting_access";
import { assertSystemNotPaused, assertWithinDailyQuota } from "./limits";

// Secrets are read lazily inside the handler, never at module top level:
// runWith({ secrets }) only injects them at runtime, so a top-level read would
// throw during the deploy-time source analysis and break `firebase deploy`.
const LIVEKIT_SECRETS = ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"];

/**
 * Validates access from Firestore rather than trusting the group ID sent by a
 * client. Group meetings are private to group members and explicitly-added
 * participants. Direct meetings remain shareable for signed-in users who have
 * the unguessable meeting link, but the meeting document must already exist.
 */
export async function assertCanJoinMeeting(meetingId: string, userId: string) {
  const db = admin.firestore();
  const meetingRef = db.collection("meetings").doc(meetingId);
  const meetingSnap = await meetingRef.get();

  if (!meetingSnap.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Meeting not found. Ask the organizer for a fresh meeting link."
    );
  }

  const meeting = meetingSnap.data()!;
  const participantIds = (meeting.participantIds || []) as string[];
  const groupId = meeting.groupId as string | undefined;

  let memberIds: string[] = [];
  if (groupId) {
    const groupSnap = await db.collection("groups").doc(groupId).get();
    memberIds = (groupSnap.data()?.memberIds || []) as string[];
  }

  if (!canJoinMeeting({ groupId, participantIds }, userId, memberIds)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "You are not a participant or member of this meeting's group."
    );
  }

  return meetingRef;
}

export const getLivekitToken = functions.region("asia-south1").runWith({ secrets: LIVEKIT_SECRETS }).https.onCall(async (data, context) => {
  // 1. Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be logged in to join a meeting.");
  }

  const { meetingId, displayName } = data;
  if (!meetingId) {
    throw new functions.https.HttpsError("invalid-argument", "meetingId is required.");
  }

  const userId = context.auth.uid;

  // Cost/abuse guardrails (Phase 1.5): global kill-switch, then per-user daily
  // meeting cap - checked before authorization so a paused system or an
  // over-quota user is turned away cheaply.
  await assertSystemNotPaused();
  await assertWithinDailyQuota(userId, meetingId);

  const meetingRef = await assertCanJoinMeeting(meetingId, userId);
  // Prefer a name the client passed (e.g. typed on the pre-join screen), then
  // the auth token's name, then a readable fallback. This name becomes the
  // LiveKit participant name, which is what the per-speaker recording is
  // labeled with and what Gemini uses to attribute the summary - so a real
  // name here is what turns "Speaker 1/2" into actual people.
  const passedName = typeof displayName === "string" ? displayName.trim() : "";
  const userName = passedName || context.auth.token.name || `User ${userId.substring(0, 5)}`;

  // Record authorized attendees so direct-meeting summaries and threads stay
  // private to people who actually joined. Group membership is still checked
  // dynamically by Firestore rules, so it does not need to be copied here.
  await meetingRef.update({
    participantIds: admin.firestore.FieldValue.arrayUnion(userId),
    lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 3. Generate LiveKit token
  const roomName = meetingId;
  const at = new AccessToken(requiredEnv("LIVEKIT_API_KEY"), requiredEnv("LIVEKIT_API_SECRET"), {
    identity: userId,
    name: userName,
  });

  at.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canSubscribe: true,
  });

  const token = await at.toJwt();

  return { token, roomName };
});
