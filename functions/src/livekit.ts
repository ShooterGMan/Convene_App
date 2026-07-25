import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { AccessToken } from "livekit-server-sdk";

// Ensure LIVEKIT_API_KEY and LIVEKIT_API_SECRET are set in Firebase env or .env
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || "devkey";
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || "secret";

export const getLivekitToken = functions.https.onCall(async (data, context) => {
  // 1. Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be logged in to join a meeting.");
  }

  const { meetingId, groupId, displayName } = data;
  if (!meetingId) {
    throw new functions.https.HttpsError("invalid-argument", "meetingId is required.");
  }

  const userId = context.auth.uid;
  // Prefer a name the client passed (e.g. typed on the pre-join screen), then
  // the auth token's name, then a readable fallback. This name becomes the
  // LiveKit participant name, which is what the per-speaker recording is
  // labeled with and what Gemini uses to attribute the summary - so a real
  // name here is what turns "Speaker 1/2" into actual people.
  const passedName = typeof displayName === "string" ? displayName.trim() : "";
  const userName = passedName || context.auth.token.name || `User ${userId.substring(0, 5)}`;

  // Record that this user is part of this meeting, so Firestore security
  // rules can later allow them (and only them / their group) to read the
  // resulting thread. Covers ad-hoc meetings that never got a client-created
  // `meetings` doc, and keeps scheduled ones current as people actually join.
  await admin
    .firestore()
    .collection("meetings")
    .doc(meetingId)
    .set(
      {
        participantIds: admin.firestore.FieldValue.arrayUnion(userId),
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(groupId ? { groupId } : {}),
      },
      { merge: true }
    );

  // 3. Generate LiveKit token
  const roomName = meetingId;
  const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
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
