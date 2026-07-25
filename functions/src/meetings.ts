import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { notifyUser } from "./notifications";

async function getUserByEmail(email: string) {
  const snap = await admin
    .firestore()
    .collection("users")
    .where("email", "==", email.trim())
    .limit(1)
    .get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  const d = doc.data();
  return {
    id: doc.id,
    name: (d.name as string) || "Unknown",
    email: (d.email as string) || email,
    avatarUrl: (d.avatarUrl as string) || null,
    isSelf: false,
  };
}

/**
 * When a meeting is created, resolve its `guestEmails` to real Convene
 * accounts SERVER-SIDE and add them as participants + notify them. Doing
 * this on the server (rather than in the client before create) makes meeting
 * invites reliable regardless of the client's build/version - the previous
 * client-side lookup silently did nothing on a stale build, so invited
 * people were never actually added. Anyone whose email has no account is
 * reported back to the organizer so they can share a join link instead.
 */
export const onMeetingCreated = functions.firestore
  .document("meetings/{meetingId}")
  .onCreate(async (snap, context) => {
    const meeting = snap.data();
    const meetingId = context.params.meetingId;
    const title = (meeting.title as string) || "a meeting";

    const existingParticipants = (meeting.participants || []) as Array<{
      id: string;
      name?: string;
    }>;
    const existingIds = new Set((meeting.participantIds || []) as string[]);
    const organizer = existingParticipants[0] || { id: (meeting.participantIds || [])[0], name: "Someone" };
    const organizerId = organizer?.id;
    const organizerName = organizer?.name || "Someone";

    const guestEmails = (meeting.guestEmails || []) as string[];

    const newParticipants: Array<Record<string, unknown>> = [];
    const newIds: string[] = [];
    const notFoundEmails: string[] = [];
    const seen = new Set<string>();

    for (const rawEmail of guestEmails) {
      const email = String(rawEmail || "").trim().toLowerCase();
      if (!email || seen.has(email)) continue;
      seen.add(email);

      const user = await getUserByEmail(rawEmail);
      if (!user) {
        notFoundEmails.push(rawEmail);
        continue;
      }
      // Skip anyone already on the meeting (incl. the organizer inviting
      // their own email) so nobody is double-added or self-notified.
      if (existingIds.has(user.id) || user.id === organizerId) continue;
      existingIds.add(user.id);
      newParticipants.push(user);
      newIds.push(user.id);
    }

    if (newParticipants.length > 0) {
      await snap.ref.update({
        participants: admin.firestore.FieldValue.arrayUnion(...newParticipants),
        participantIds: admin.firestore.FieldValue.arrayUnion(...newIds),
      });
    }

    // Notify newly-resolved guests, plus any extra participants a client may
    // have added directly (everyone except the organizer).
    const notifyIds = new Set<string>(newIds);
    for (const p of existingParticipants.slice(1)) {
      if (p.id && p.id !== organizerId) notifyIds.add(p.id);
    }

    await Promise.all(
      [...notifyIds].map((id) =>
        notifyUser(id, {
          type: "meeting_added",
          title: "Added to a meeting",
          body: `${organizerName} added you to "${title}"`,
          route: `/pre-join/${meetingId}`,
          relatedId: meetingId,
        })
      )
    );

    // Let the organizer know which invited emails don't have Convene yet, so
    // they can share a join link instead of assuming the person got it.
    if (notFoundEmails.length > 0 && organizerId) {
      await notifyUser(organizerId, {
        type: "meeting_added",
        title: "Some guests aren't on Convene yet",
        body: `${notFoundEmails.join(", ")} ${notFoundEmails.length === 1 ? "isn't" : "aren't"} on Convene yet - share the meeting link so they can join.`,
        route: `/pre-join/${meetingId}`,
        relatedId: meetingId,
      });
    }
  });
