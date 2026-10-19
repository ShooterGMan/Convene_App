import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

/**
 * Detects meetings that never got a summary and flags them so the app can
 * tell users to plan something else - covers the specific failure mode that
 * can't be caught by error handling: LiveKit simply never sending a webhook
 * at all, so nothing ever happens. This function never calls LiveKit or
 * touches egress - it only reads Firestore and flags staleness, so it can't
 * cause the kind of chaos the old room-restarting poller did.
 *
 * A meeting is "stuck" if someone joined (participantIds non-empty) but
 * there's been no activity for 10+ minutes and still no thread/error.
 */
export const flagStuckMeetings = functions.region("asia-south1").pubsub.schedule("every 5 minutes").onRun(async () => {
  const db = admin.firestore();
  const now = Date.now();
  const staleThreshold = admin.firestore.Timestamp.fromMillis(now - 10 * 60 * 1000);
  const abandonedThreshold = admin.firestore.Timestamp.fromMillis(now - 30 * 60 * 1000);
  // Bound the scan window so this doesn't grow unbounded over time.
  const lookbackLimit = admin.firestore.Timestamp.fromMillis(now - 24 * 60 * 60 * 1000);

  const snapshot = await db
    .collection("meetings")
    .where("lastActivityAt", ">", lookbackLimit)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.threadId || data.summaryError) continue;
    
    const noParticipants = !Array.isArray(data.participantIds) || data.participantIds.length === 0;

    // Handle meetings that never had anyone join
    if (noParticipants) {
      if (data.isInstant && data.startTime && data.startTime.toMillis() < abandonedThreshold.toMillis()) {
        await doc.ref.set(
          {
            summaryError: "abandoned",
            summaryStatus: "failed",
            summaryErrorAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        console.log(`Flagged instant meeting ${doc.id} as abandoned - no one joined after 30 minutes.`);
      }
      continue;
    }

    // Handle meetings where people did join, but it's been idle for 10+ minutes (staleThreshold)
    if (data.lastActivityAt && data.lastActivityAt.toMillis() < staleThreshold.toMillis()) {
      await doc.ref.set(
        {
          summaryError: "timeout",
          summaryStatus: "failed",
          summaryErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log(`Flagged meeting ${doc.id} as stuck - no summary after 10+ minutes of inactivity.`);
    }
  }

  return null;
});
