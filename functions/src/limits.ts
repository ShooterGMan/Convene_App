import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Cost/abuse guardrails (roadmap Phase 1.5). Every meeting costs real money
 * (LiveKit egress + Gemini + storage), so before minting a join token we:
 *   1. honor a global kill-switch so runaway spend or an incident can be
 *      stopped instantly without a code deploy, and
 *   2. cap how many distinct meetings a single user can spin up per day, so
 *      one malicious or buggy client can't exhaust capacity/budget for everyone.
 */

// Per-user distinct-meetings-per-day cap. Generous enough for real use, low
// enough to bound a scripted-abuse blast radius. Override via env for beta.
const DAILY_MEETING_LIMIT = Number(process.env.DAILY_MEETING_LIMIT || "25");

function todayKey(): string {
  return new Date().toISOString().slice(0, 10); // yyyy-mm-dd (UTC)
}

/**
 * Global kill-switch. Reads config/system.pauseNewMeetings; when true, no new
 * join tokens are issued (existing calls in progress are unaffected). Set the
 * flag from the Firebase console or a trusted admin path - never from the app.
 */
export async function assertSystemNotPaused() {
  const doc = await admin.firestore().collection("config").doc("system").get();
  const data = doc.data();
  if (data?.pauseNewMeetings === true) {
    throw new functions.https.HttpsError(
      "unavailable",
      typeof data.pauseMessage === "string" && data.pauseMessage.trim()
        ? data.pauseMessage
        : "Convene is temporarily paused. Please try again later."
    );
  }
}

/**
 * Records that `userId` engaged with `meetingId` today and enforces the daily
 * distinct-meeting cap. Idempotent per (user, meeting, day) so re-joining the
 * same meeting doesn't consume additional quota. Runs in a transaction so
 * concurrent joins can't race past the limit.
 */
export async function assertWithinDailyQuota(userId: string, meetingId: string) {
  const ref = admin.firestore().collection("users").doc(userId).collection("usage").doc("daily");
  const key = todayKey();

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const sameDay = data?.date === key;
    const meetings: string[] = sameDay && Array.isArray(data?.meetings) ? data.meetings : [];

    // Already counted this meeting today - allow (re-join) without charging quota.
    if (meetings.includes(meetingId)) return;

    if (meetings.length >= DAILY_MEETING_LIMIT) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `Daily meeting limit reached (${DAILY_MEETING_LIMIT}). This resets tomorrow.`
      );
    }

    tx.set(ref, { date: key, meetings: [...meetings, meetingId] }, { merge: true });
  });
}
