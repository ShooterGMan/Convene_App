import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { WebhookReceiver, EgressClient, EncodedFileType, EncodedFileOutput, GCPUpload, TrackType } from "livekit-server-sdk";
import { GoogleGenAI, createPartFromUri } from "@google/genai";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

// Keep this secret, it's used to validate that the webhook actually came from LiveKit
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || "devkey";
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || "secret";
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "gemini_secret";
// Host of your LiveKit Cloud project, e.g. https://convene-app-a9liwgoq.livekit.cloud
const LIVEKIT_HOST = process.env.LIVEKIT_HOST || "";
// GCS bucket egress recordings are temporarily uploaded to before being sent to Gemini.
// Defaults to the project's default Firebase Storage bucket.
const EGRESS_BUCKET = process.env.EGRESS_BUCKET || `${process.env.GCLOUD_PROJECT}.appspot.com`;
// LiveKit Cloud's egress workers run outside this GCP project, so they need an explicit
// service-account key (JSON, as a single-line string) with Storage Object Admin on
// EGRESS_BUCKET in order to upload recordings there.
const GCP_EGRESS_CREDENTIALS = process.env.GCP_EGRESS_CREDENTIALS || "";

const receiver = new WebhookReceiver(LIVEKIT_API_KEY, LIVEKIT_API_SECRET);
const egressClient = new EgressClient(LIVEKIT_HOST, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);

/**
 * Single entrypoint for all LiveKit server webhooks. Configure this function's URL
 * as the "Webhook URL" in the LiveKit Cloud project dashboard so both events below fire.
 *
 * - room_started: a room bot pattern - automatically starts a server-side, audio-only
 *   Room Composite Egress the moment the first participant joins. This runs regardless
 *   of which client app/device joins, so summaries don't depend on any participant
 *   opting in to anything.
 * - egress_ended: fired when that recording finishes (i.e. the room emptied out and
 *   egress auto-stopped). Downloads the single mixed-audio file, sends it to Gemini for
 *   transcription + summarization in one call, writes ONE thread per meeting to
 *   Firestore, and deletes the temporary recording.
 */
// NOTE: this must be reached via the Firebase Hosting rewrite (/livekitWebhook, see
// firebase.json), not the raw Cloud Run URL. Cloud Functions v2/Cloud Run auto-validates
// any incoming "Authorization" header as a Google OIDC Bearer token and rejects it
// before this code runs if it isn't one - which breaks LiveKit's own webhook signature
// header (not an OIDC token). Hosting authenticates to the backend with its own
// credentials instead of forwarding the raw invocation auth, which avoids that check.
export const livekitWebhook = functions.https.onRequest(async (req, res) => {
  try {
    const event = await receiver.receive(req.body, req.headers.authorization);

    if (event.event === "room_started") {
      await handleRoomStarted(event.room?.name);
      res.status(200).send("Egress started");
      return;
    }

    if (event.event === "track_published") {
      await handleTrackPublished(event.room?.name, event.participant, event.track);
      res.status(200).send("Speaker track handled");
      return;
    }

    if (event.event === "egress_ended") {
      await handleEgressEnded(event.egressInfo);
      res.status(200).send("Success");
      return;
    }

    res.status(200).send("Ignored event");
  } catch (error) {
    console.error("Webhook error:", error);
    res.status(500).send("Internal Server Error");
  }
});

/**
 * Lets a client proactively finalize a meeting's recording instead of waiting on
 * LiveKit's default empty-room timeout. Callers must only invoke this once the room
 * is actually empty (e.g. the last participant leaving) - it stops the egress
 * unconditionally. If no egress is running, it's a no-op.
 */
export const stopMeetingEgress = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }

  const { meetingId } = data;
  if (!meetingId) {
    throw new functions.https.HttpsError("invalid-argument", "meetingId required.");
  }

  await admin.firestore().collection("meetings").doc(meetingId).set(
    { lastActivityAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  // Egress starts asynchronously off the room_started webhook, so it may not have
  // started yet if the caller ends the session within a second or two of joining.
  // Give it a couple of short retries before giving up.
  let active = await egressClient.listEgress({ roomName: meetingId, active: true });
  for (let attempt = 0; active.length === 0 && attempt < 3; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    active = await egressClient.listEgress({ roomName: meetingId, active: true });
  }

  await Promise.all(active.map((e) => egressClient.stopEgress(e.egressId)));
  return { stopped: active.length };
});

export async function handleRoomStarted(roomName?: string) {
  if (!roomName) return;

  // Avoid double-starting egress if room_started fires more than once for the same room.
  const active = await egressClient.listEgress({ roomName, active: true });
  if (active.length > 0) {
    console.log(`Egress already running for room ${roomName}`);
    return;
  }

  const objectKey = `egress-tmp/${roomName}-${Date.now()}.ogg`;
  console.log(`Starting audio-only room composite egress for ${roomName} -> gs://${EGRESS_BUCKET}/${objectKey}`);

  await egressClient.startRoomCompositeEgress(
    roomName,
    {
      file: new EncodedFileOutput({
        fileType: EncodedFileType.OGG,
        filepath: objectKey,
        output: {
          case: "gcp",
          value: new GCPUpload({
            bucket: EGRESS_BUCKET,
            credentials: GCP_EGRESS_CREDENTIALS,
          }),
        },
      }),
    },
    { audioOnly: true }
  );
}

/**
 * Speaker attribution for online (LiveKit) meetings: rather than rely on
 * Gemini to guess who's who from one mixed-down room recording, record each
 * participant's own microphone as a separate labeled file the moment it's
 * published. When the meeting ends, if we have these per-speaker files
 * they're used instead of the mixed recording, so summaries can correctly
 * attribute decisions/action items to real names instead of "Speaker 1".
 * The room composite recording (handleRoomStarted) always keeps running
 * regardless, so a summary is still guaranteed even if this never fires.
 */
async function handleTrackPublished(roomName?: string, participant?: any, track?: any) {
  if (!roomName || !participant?.identity || !track) return;
  if (track.type !== TrackType.AUDIO) return;

  const identity = participant.identity;
  const trackDocRef = admin
    .firestore()
    .collection("meetings")
    .doc(roomName)
    .collection("speakerTracks")
    .doc(identity);

  // Avoid starting a second recording if this participant republishes audio.
  const existing = await trackDocRef.get();
  if (existing.exists) return;

  const name: string = participant.name || identity;
  const objectKey = `egress-tmp/${roomName}-speaker-${identity}-${Date.now()}.ogg`;

  await trackDocRef.set({
    name,
    identity,
    objectKey,
    status: "recording",
    startedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    console.log(`Starting per-speaker audio track for ${name} (${identity}) in room ${roomName}`);
    await egressClient.startTrackCompositeEgress(
      roomName,
      {
        file: new EncodedFileOutput({
          fileType: EncodedFileType.OGG,
          filepath: objectKey,
          output: {
            case: "gcp",
            value: new GCPUpload({
              bucket: EGRESS_BUCKET,
              credentials: GCP_EGRESS_CREDENTIALS,
            }),
          },
        }),
      },
      { audioTrackId: track.sid }
    );
  } catch (error) {
    console.error(`Failed to start speaker track egress for ${identity} in ${roomName}:`, error);
    await trackDocRef.set({ status: "failed" }, { merge: true });
  }
}

export async function handleEgressEnded(egressInfo: any) {
  if (!egressInfo) {
    console.error("egress_ended with no egressInfo");
    return;
  }

  const meetingId = egressInfo.roomName;
  const fileResult = egressInfo.fileResults?.[0];
  const objectKey: string | undefined = fileResult?.filename || fileResult?.location;

  if (!objectKey) {
    console.error(`Egress ended for ${meetingId} but no output file was found.`);
    return;
  }

  // A per-speaker track recording just finished (see handleTrackPublished) -
  // mark it complete and stop here. Only the room composite egress ending
  // (below) triggers actually generating the summary.
  if (egressInfo.request?.case === "trackComposite") {
    const db = admin.firestore();
    const speakerTracks = await db.collection("meetings").doc(meetingId).collection("speakerTracks").get();
    const match = speakerTracks.docs.find((d) => d.data().objectKey === objectKey);
    if (match) {
      await match.ref.set({ status: "complete" }, { merge: true });
      console.log(`Speaker track complete for ${match.data().name} in room ${meetingId}`);
    }
    return;
  }

  // LiveKit retries webhook deliveries that don't return quickly (Gemini
  // processing takes several seconds), so the same egress_ended event can
  // arrive multiple times *while the first attempt is still in flight*. A
  // plain "does it already have a threadId" read-then-write check has a race
  // window there - a retry can land and pass the check before the first
  // attempt finishes writing threadId, and both end up generating a thread.
  // Claim the meeting atomically in a transaction instead, so only one
  // attempt can ever proceed. A claim older than 5 minutes with no result is
  // treated as abandoned (e.g. a crashed attempt) and can be retried.
  const db = admin.firestore();
  const STALE_CLAIM_MS = 5 * 60 * 1000;
  const meetingRef = db.collection("meetings").doc(meetingId);

  const claimed = await db.runTransaction(async (tx) => {
    const doc = await tx.get(meetingRef);
    const data = doc.data();
    if (data?.threadId) return false;
    const claimedAt = data?.processingClaimedAt?.toMillis?.();
    if (claimedAt && Date.now() - claimedAt < STALE_CLAIM_MS) return false;
    tx.set(meetingRef, { processingClaimedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });

  if (!claimed) {
    console.log(`Meeting ${meetingId} is already processed or being processed, skipping duplicate.`);
    return;
  }

  const existingMeetingDoc = await meetingRef.get();

  console.log(`Processing recording for meeting ${meetingId} from gs://${EGRESS_BUCKET}/${objectKey}`);

  const bucket = admin.storage().bucket(EGRESS_BUCKET);
  const file = bucket.file(objectKey);
  const tmpFilePath = path.join(os.tmpdir(), `${meetingId}-${Date.now()}.ogg`);
  const cleanupPaths: string[] = [tmpFilePath];
  const cleanupFiles: string[] = [objectKey];

  try {
    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

    // Prefer labeled per-speaker recordings if any completed (real name
    // attribution), falling back to the single mixed room recording.
    const speakerTracksSnapshot = await db
      .collection("meetings")
      .doc(meetingId)
      .collection("speakerTracks")
      .where("status", "==", "complete")
      .get();

    const audioParts: any[] = [];

    if (!speakerTracksSnapshot.empty) {
      console.log(`Using ${speakerTracksSnapshot.size} labeled speaker track(s) for meeting ${meetingId}`);
      for (const doc of speakerTracksSnapshot.docs) {
        const trackData = doc.data();
        const trackObjectKey: string = trackData.objectKey;
        const speakerName: string = trackData.name || doc.id;
        const trackTmpPath = path.join(os.tmpdir(), `${meetingId}-${doc.id}-${Date.now()}.ogg`);
        try {
          await bucket.file(trackObjectKey).download({ destination: trackTmpPath });
        } catch (error) {
          console.error(`Failed to download speaker track for ${speakerName}, skipping it:`, error);
          continue;
        }
        cleanupPaths.push(trackTmpPath);
        cleanupFiles.push(trackObjectKey);

        const uploadResult = await ai.files.upload({
          file: trackTmpPath,
          config: { mimeType: "audio/ogg", displayName: `${meetingId} - ${speakerName}` },
        });
        audioParts.push(`Audio track from ${speakerName}:`);
        audioParts.push(createPartFromUri(uploadResult.uri!, uploadResult.mimeType!));
      }
    }

    // Fall back to the mixed room recording if no speaker tracks were usable.
    if (audioParts.length === 0) {
      await file.download({ destination: tmpFilePath });
      console.log(`Uploading ${tmpFilePath} to Gemini...`);
      const uploadResult = await ai.files.upload({
        file: tmpFilePath,
        config: { mimeType: "audio/ogg", displayName: `Meeting ${meetingId}` },
      });
      audioParts.push(createPartFromUri(uploadResult.uri!, uploadResult.mimeType!));
    }

    const usingSpeakerTracks = !speakerTracksSnapshot.empty && audioParts.length > 1;
    const prompt = `
      You are an expert meeting assistant. Analyze the audio of this meeting.
      If the recording is empty or silent, state that no meaningful content was captured.
      ${usingSpeakerTracks
        ? "You have been given separate labeled audio tracks, one per participant, each preceded by a text note naming who it belongs to. Use those exact names when attributing decisions, action items, and transcript lines to specific people."
        : "This is a single mixed recording of everyone in the meeting. If you can distinguish different speakers by voice, label them Speaker 1, Speaker 2, etc."}
      Extract:
      1. A brief summary of the meeting.
      2. The main decisions made.
      3. Action items with assignees if mentioned (use real names when available).
      4. A full transcript of the meeting, formatted as plain text with speaker
         turns on their own line (e.g. "${usingSpeakerTracks ? "Alex" : "Speaker 1"}: ..."). If the
         recording is empty or silent, use an empty string.
      Output the result in a structured JSON format matching this schema:
      {
        "vibe": "Productive & Focused",
        "vibeEmoji": "🚀",
        "blocks": [
          { "type": "summary", "title": "Summary", "content": "..." },
          { "type": "decisions", "title": "Decisions", "content": "- ..." },
          { "type": "action_items", "title": "Action Items", "content": "- ..." }
        ],
        "transcript": "..."
      }
    `;

    const result = await ai.models.generateContent({
      model: "gemini-3.5-flash",
      contents: [...audioParts, prompt],
    });

    const jsonText = result.text!.replace(/```json|```/g, "").trim();
    const parsedResult = JSON.parse(jsonText);

    let groupId = null;
    let meetingTitle = "Untitled Meeting";
    let participants: any[] = [];
    let participantIds: string[] = [];

    if (existingMeetingDoc.exists) {
      const data = existingMeetingDoc.data();
      groupId = data?.groupId ?? null;
      meetingTitle = data?.title || meetingTitle;
      participants = data?.participants || participants;
      participantIds = data?.participantIds || participantIds;
    }

    const threadRef = db.collection("threads").doc();
    const thread = {
      id: threadRef.id,
      meetingTitle,
      groupId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      participants,
      participantIds,
      vibe: parsedResult.vibe,
      vibeEmoji: parsedResult.vibeEmoji,
      blocks: parsedResult.blocks,
    };

    await threadRef.set(thread);

    // If it belongs to a group, update the group's thread list
    if (groupId) {
      await db.collection("groups").doc(groupId).update({
        threadIds: admin.firestore.FieldValue.arrayUnion(thread.id),
      });
    }

    await db.collection("meetings").doc(meetingId).set(
      {
        threadId: thread.id,
        summaryError: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    // Keep the transcript (but not the audio) for 30 days so participants can
    // read back what was actually said. Auto-deleted via a Firestore TTL
    // policy on `expiresAt` - no cleanup job needed.
    const transcriptText: string = parsedResult.transcript || "";
    if (transcriptText.trim().length > 0) {
      const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.collection("transcripts").doc(meetingId).set({
        meetingId,
        threadId: thread.id,
        groupId,
        participantIds,
        transcript: transcriptText,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
      });
    }

    // Only delete the recording(s) once fully processed into a thread - on
    // failure we keep them in GCS so a retry doesn't lose the meeting's audio.
    await Promise.all(cleanupFiles.map((key) => bucket.file(key).delete({ ignoreNotFound: true })));

    // Clean up the speaker-track bookkeeping docs now that they're consumed.
    if (!speakerTracksSnapshot.empty) {
      const batch = db.batch();
      speakerTracksSnapshot.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
  } catch (error: any) {
    console.error(`Failed to process recording for meeting ${meetingId}:`, error);
    // Surface the failure immediately so the app can tell the user their
    // summary didn't generate, instead of leaving them waiting indefinitely.
    await db.collection("meetings").doc(meetingId).set(
      {
        summaryError: String(error?.message || error).slice(0, 500),
        summaryErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    throw error;
  } finally {
    for (const p of cleanupPaths) {
      if (fs.existsSync(p)) fs.unlinkSync(p);
    }
  }
}
