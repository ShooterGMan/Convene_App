import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { WebhookReceiver, EgressClient, EncodedFileType, EncodedFileOutput, GCPUpload, TrackType } from "livekit-server-sdk";
import { GoogleGenAI, createPartFromUri } from "@google/genai";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { assertCanJoinMeeting } from "./livekit";
import { requiredEnv } from "./config";
import { canStopMeeting } from "./meeting_access";
import { notifyUser } from "./notifications";

// All server-side integration configuration is required. It is read LAZILY
// (as functions, called inside handlers) and never at module top level:
// secrets bound via runWith({ secrets }) are only injected at runtime, not
// during the deploy-time source analysis, so a top-level read would throw and
// break `firebase deploy`.
const livekitApiKey = () => requiredEnv("LIVEKIT_API_KEY");
const livekitApiSecret = () => requiredEnv("LIVEKIT_API_SECRET");
const geminiApiKey = () => requiredEnv("GEMINI_API_KEY");
// Host of your LiveKit Cloud project, e.g. https://your-project.livekit.cloud
const livekitHost = () => requiredEnv("LIVEKIT_HOST");
// GCS bucket egress recordings are temporarily uploaded to before being sent
// to Gemini. Explicit so recordings can never silently land elsewhere.
const egressBucket = () => requiredEnv("EGRESS_BUCKET");
// LiveKit Cloud's egress workers run outside this GCP project, so they need an
// explicit service-account key (JSON, one-line string) with Storage Object
// Admin on the egress bucket in order to upload recordings there.
const gcpEgressCredentials = () => requiredEnv("GCP_EGRESS_CREDENTIALS");
const WEBHOOK_SECRETS = [
  "LIVEKIT_API_KEY",
  "LIVEKIT_API_SECRET",
  "GEMINI_API_KEY",
  "LIVEKIT_HOST",
  "EGRESS_BUCKET",
  "GCP_EGRESS_CREDENTIALS",
];
// Beta default: record one mixed room-audio stream only. Per-speaker tracks
// require an additional LiveKit egress for every participant and therefore
// exceed the practical capacity/cost of the initial user test. Keep the
// existing implementation behind an explicit opt-in for a later plan upgrade.
// (Safe to read at top level: this never throws when unset.)
const ENABLE_SPEAKER_TRACKS = process.env.ENABLE_SPEAKER_TRACKS === "true";

// LiveKit clients are built on first use at runtime (when the secrets exist),
// not at import time.
let _receiver: WebhookReceiver | undefined;
function getReceiver(): WebhookReceiver {
  if (!_receiver) _receiver = new WebhookReceiver(livekitApiKey(), livekitApiSecret());
  return _receiver;
}
let _egressClient: EgressClient | undefined;
function getEgressClient(): EgressClient {
  if (!_egressClient) _egressClient = new EgressClient(livekitHost(), livekitApiKey(), livekitApiSecret());
  return _egressClient;
}

/**
 * Single entrypoint for all LiveKit server webhooks. Configure this function's URL
 * as the "Webhook URL" in the LiveKit Cloud project dashboard so both events below fire.
 *
 * - room_started: automatically starts one mixed, audio-only Room Composite
 *   Egress the moment the first participant joins. This runs regardless of
 *   which client app/device joins, so summaries don't depend on any participant
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
export const livekitWebhook = functions.region("asia-south1").runWith({ secrets: WEBHOOK_SECRETS }).https.onRequest(async (req, res) => {
  try {
    const event = await getReceiver().receive(req.body, req.headers.authorization);

    if (event.event === "room_started") {
      await handleRoomStarted(event.room?.name);
      res.status(200).send("Egress started");
      return;
    }

    if (event.event === "track_published" && ENABLE_SPEAKER_TRACKS) {
      await handleTrackPublished(event.room?.name, event.participant, event.track);
      res.status(200).send("Speaker track handled");
      return;
    }

    if (event.event === "participant_left" || event.event === "room_finished") {
      const roomName = event.room?.name;
      const numParticipants = event.room?.numParticipants ?? 0;
      if (roomName && (numParticipants === 0 || event.event === "room_finished")) {
        console.log(`Room ${roomName} is empty or finished. Stopping egress immediately...`);
        const active = await getEgressClient().listEgress({ roomName, active: true });
        await Promise.all(active.map((e) => getEgressClient().stopEgress(e.egressId)));
      }
      res.status(200).send("Room cleanup handled");
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
export const stopMeetingEgress = functions.region("asia-south1").runWith({ secrets: WEBHOOK_SECRETS }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be logged in.");
  }

  const { meetingId } = data;
  if (!meetingId) {
    throw new functions.https.HttpsError("invalid-argument", "meetingId required.");
  }

  const db = admin.firestore();
  const meetingRef = await assertCanJoinMeeting(meetingId, context.auth.uid);
  const meeting = (await meetingRef.get()).data()!;
  const participantIds = (meeting.participantIds || []) as string[];
  const organizerId = meeting.participants?.[0]?.id || participantIds[0];
  let adminIds: string[] = [];
  if (meeting.groupId) {
    const group = await db.collection("groups").doc(meeting.groupId).get();
    adminIds = (group.data()?.adminIds || []) as string[];
  }

  if (!canStopMeeting(
    { groupId: meeting.groupId, participantIds, organizerId },
    context.auth.uid,
    adminIds
  )) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the meeting organizer or a group admin can stop the recording."
    );
  }

  await meetingRef.set(
    { lastActivityAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  // Egress starts asynchronously off the room_started webhook, so it may not have
  // started yet if the caller ends the session within a second or two of joining.
  // Give it a couple of short retries before giving up.
  let active = await getEgressClient().listEgress({ roomName: meetingId, active: true });
  for (let attempt = 0; active.length === 0 && attempt < 3; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    active = await getEgressClient().listEgress({ roomName: meetingId, active: true });
  }

  await Promise.all(active.map((e) => getEgressClient().stopEgress(e.egressId)));
  return { stopped: active.length };
});

export async function handleRoomStarted(roomName?: string) {
  if (!roomName) return;

  await admin.firestore().collection("meetings").doc(roomName).set(
    {
      summaryStatus: "recording",
      summaryError: admin.firestore.FieldValue.delete(),
      lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // Avoid double-starting egress if room_started fires more than once for the same room.
  const active = await getEgressClient().listEgress({ roomName, active: true });
  if (active.length > 0) {
    console.log(`Egress already running for room ${roomName}`);
    return;
  }

  const objectKey = `egress-tmp/${roomName}-${Date.now()}.ogg`;
  console.log(`Starting audio-only room composite egress for ${roomName} -> gs://${egressBucket()}/${objectKey}`);

  await getEgressClient().startRoomCompositeEgress(
    roomName,
    {
      file: new EncodedFileOutput({
        fileType: EncodedFileType.OGG,
        filepath: objectKey,
        output: {
          case: "gcp",
          value: new GCPUpload({
            bucket: egressBucket(),
            credentials: gcpEgressCredentials(),
          }),
        },
      }),
    },
    { audioOnly: true }
  );
}

/**
 * Optional speaker attribution for online (LiveKit) meetings: rather than rely on
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
    await getEgressClient().startTrackCompositeEgress(
      roomName,
      {
        file: new EncodedFileOutput({
          fileType: EncodedFileType.OGG,
          filepath: objectKey,
          output: {
            case: "gcp",
            value: new GCPUpload({
              bucket: egressBucket(),
              credentials: gcpEgressCredentials(),
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
    tx.set(
      meetingRef,
      {
        processingClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        summaryStatus: "processing",
        summaryError: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
    return true;
  });

  if (!claimed) {
    console.log(`Meeting ${meetingId} is already processed or being processed, skipping duplicate.`);
    return;
  }

  const existingMeetingDoc = await meetingRef.get();
  // Start of processing - used to report time-to-summary (Phase 1.5.4).
  const processingStartedMs = Date.now();

  console.log(`Processing recording for meeting ${meetingId} from gs://${egressBucket()}/${objectKey}`);

  const bucket = admin.storage().bucket(egressBucket());
  const file = bucket.file(objectKey);
  const tmpFilePath = path.join(os.tmpdir(), `${meetingId}-${Date.now()}.ogg`);
  const cleanupPaths: string[] = [tmpFilePath];
  const cleanupFiles: string[] = [objectKey];

  try {
    const ai = new GoogleGenAI({ apiKey: geminiApiKey() });

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

    // Check for registered Voice ID voiceprints for attendees
    let loadedVoiceprintsCount = 0;
    if (!usingSpeakerTracks && existingMeetingDoc.exists) {
      const d = existingMeetingDoc.data();
      const pList: any[] = d?.participants || [];
      for (const p of pList) {
        if (!p?.id || !p?.name) continue;
        const voiceFile = bucket.file(`users/${p.id}/voiceprint.ogg`);
        try {
          const [exists] = await voiceFile.exists();
          if (exists) {
            const vpTmpPath = path.join(os.tmpdir(), `voiceprint-${p.id}-${Date.now()}.ogg`);
            await voiceFile.download({ destination: vpTmpPath });
            cleanupPaths.push(vpTmpPath);
            const vpUpload = await ai.files.upload({
              file: vpTmpPath,
              config: { mimeType: "audio/ogg", displayName: `Voice ID reference for ${p.name}` },
            });
            audioParts.unshift(createPartFromUri(vpUpload.uri!, vpUpload.mimeType!));
            audioParts.unshift(`Reference 5-second Voice ID sample for ${p.name}:`);
            loadedVoiceprintsCount++;
            console.log(`Attached reference Voice ID for ${p.name} (${p.id})`);
          }
        } catch (vpErr) {
          console.error(`Failed to load voiceprint for ${p.name}:`, vpErr);
        }
      }
    }

    // Attendee roster as a prior for speaker attribution on the single mixed
    // recording (in-person meetings especially). We can't positively identify
    // voices, but giving the model the list of people who were expected helps
    // it use real names where the conversation makes the speaker clear, instead
    // of defaulting everyone to "Speaker N". Names come from the meeting's
    // participants plus, for a group meeting, the group's member list.
    const attendeeNames: string[] = [];
    if (existingMeetingDoc.exists) {
      const d = existingMeetingDoc.data();
      for (const p of (d?.participants || [])) {
        if (p?.name && typeof p.name === "string" && !attendeeNames.includes(p.name)) {
          attendeeNames.push(p.name);
        }
      }
      if (d?.groupId) {
        try {
          const g = await db.collection("groups").doc(d.groupId).get();
          for (const m of (g.data()?.members || [])) {
            if (m?.name && typeof m.name === "string" && !attendeeNames.includes(m.name)) {
              attendeeNames.push(m.name);
            }
          }
        } catch (rosterErr) {
          console.error(`Could not load group roster for ${meetingId}:`, rosterErr);
        }
      }
    }
    const rosterHint = attendeeNames.length > 0
      ? `The following people were expected to attend: ${attendeeNames.join(", ")}. When the conversation makes it reasonably clear who is speaking, attribute lines to these names. `
      : "";

    const prompt = `
      You are an expert meeting assistant. Analyze the audio of this meeting.
      If the recording is empty or silent, state that no meaningful content was captured.
      
      AUDIO NOISE & REVERB CANCELLATION:
      The audio may contain non-speech background noise (fans, keyboard typing, HVAC hums, paper rustling, air conditioning, reverb, background babble). Ignore all non-speech background noise and isolate distinct human vocal frequencies for transcription, voice matching, and summary extraction.

      ${usingSpeakerTracks
        ? "You have been given separate labeled audio tracks, one per participant, each preceded by a text note naming who it belongs to. Use those exact names when attributing decisions, action items, and transcript lines to specific people."
        : loadedVoiceprintsCount > 0
          ? `You have been provided ${loadedVoiceprintsCount} reference Voice ID audio sample(s) for registered attendees above. Compare the acoustic voice timber and pitch in the main meeting audio against these reference voice samples to attribute quotes, decisions, and action items to real names. If a voice does not match any registered reference voice sample or roster name, label them "Guest" (or "Guest 1", "Guest 2", etc.).`
          : `This is a single mixed recording of everyone in the meeting. ${rosterHint}If a speaker's voice matches an expected attendee, use their real name. If a speaker is an unregistered guest or cannot be identified, label them "Guest" (or "Guest 1", "Guest 2", etc.).`}
      Extract:
      1. A brief summary of the meeting (a single "summary" block).
      2. The main decisions made — ONE "decision" block per distinct decision.
      3. Action items — ONE "action_item" block per task. If a task is clearly
         assigned to someone, set "assignee" to that person's FIRST name only
         (e.g. "Alex"); if it isn't clearly assigned, omit "assignee".
      4. Optionally, notable "key_insight" blocks for important points that are
         neither decisions nor action items.
      5. A full transcript of the meeting, formatted as plain text with speaker
         turns on their own line (e.g. "${usingSpeakerTracks ? "Alex" : "Speaker 1"}: ..."). If the
         recording is empty or silent, use an empty string.
      Output the result in a structured JSON format matching this schema. Emit a
      SEPARATE block object for each decision and each action item (do not lump
      them into one bulleted block):
      {
        "vibe": "Productive & Focused",
        "vibeEmoji": "🚀",
        "blocks": [
          { "type": "summary", "content": "..." },
          { "type": "decision", "content": "..." },
          { "type": "action_item", "content": "...", "assignee": "Alex" },
          { "type": "key_insight", "content": "..." }
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

    // A meeting can be attached to an existing topic at scheduling time
    // (meeting.topicId). If so, append this session's blocks to that topic
    // instead of creating a new one, so several meetings about the same subject
    // accumulate into one running topic. Otherwise, create a fresh topic.
    const targetTopicId: string | null =
      existingMeetingDoc.exists ? (existingMeetingDoc.data()?.topicId ?? null) : null;

    let threadId = "";
    let isNewTopic = true;

    if (targetTopicId) {
      const topicRef = db.collection("threads").doc(targetTopicId);
      const appended = await db.runTransaction(async (tx) => {
        const snap = await tx.get(topicRef);
        if (!snap.exists) return false;
        const existing = snap.data()!;
        const dateLabel = new Date().toISOString().slice(0, 10);
        // A divider block makes each appended session visually distinct in the
        // topic's block list.
        const dividerBlock = {
          type: "key_insight",
          content: `🗓️ New session — ${meetingTitle} · ${dateLabel}`,
        };
        const mergedBlocks = [...(existing.blocks || []), dividerBlock, ...(parsedResult.blocks || [])];
        const mergedParticipantIds = Array.from(
          new Set([...((existing.participantIds || []) as string[]), ...participantIds])
        );
        const byId: Record<string, any> = {};
        for (const p of [...((existing.participants || []) as any[]), ...participants]) {
          if (p?.id) byId[p.id] = p;
        }
        tx.set(
          topicRef,
          {
            blocks: mergedBlocks,
            participantIds: mergedParticipantIds,
            participants: Object.values(byId),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastSessionTitle: meetingTitle,
          },
          { merge: true }
        );
        return true;
      });
      if (appended) {
        threadId = targetTopicId;
        isNewTopic = false;
      }
    }

    if (!threadId) {
      const threadRef = db.collection("threads").doc();
      await threadRef.set({
        id: threadRef.id,
        meetingTitle,
        groupId,
        meetingId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        participants,
        participantIds,
        vibe: parsedResult.vibe,
        vibeEmoji: parsedResult.vibeEmoji,
        blocks: parsedResult.blocks,
      });
      threadId = threadRef.id;

      // If it belongs to a group, update the group's thread list
      if (groupId) {
        await db.collection("groups").doc(groupId).update({
          threadIds: admin.firestore.FieldValue.arrayUnion(threadId),
        });
      }
    }

    await db.collection("meetings").doc(meetingId).set(
      {
        threadId,
        summaryStatus: "ready",
        summaryError: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    // Notify participants their summary is ready, and anyone assigned an action.
    // Best-effort: a notification failure must never fail the whole summary.
    try {
      for (const uid of new Set<string>(participantIds)) {
        await notifyUser(uid, {
          type: "summary_ready",
          title: isNewTopic ? "Summary ready" : "Topic updated",
          body: `"${meetingTitle}" has a new AI summary.`,
          route: `/thread/${threadId}`,
          relatedId: threadId,
        });
      }
      const actionBlocks = ((parsedResult.blocks || []) as any[]).filter(
        (b) => typeof b?.type === "string" && b.type.includes("action") && b?.assignee
      );
      for (const b of actionBlocks) {
        const assignee = String(b.assignee).trim().toLowerCase();
        const match = (participants as any[]).find(
          (p) => typeof p?.name === "string" && p.name.split(" ")[0].toLowerCase() === assignee
        );
        if (match?.id) {
          await notifyUser(match.id, {
            type: "action_assigned",
            title: "You were assigned an action",
            body: b.content,
            route: `/thread/${threadId}`,
            relatedId: threadId,
          });
        }
      }
    } catch (notifyErr) {
      console.error(`Failed to send summary notifications for ${meetingId}:`, notifyErr);
    }

    // Structured metric line for observability (Phase 1.5.4). Query in Cloud
    // Logging on jsonPayload.metric="summary" for success rate + time-to-summary.
    console.log(JSON.stringify({
      metric: "summary",
      status: "ready",
      meetingId,
      durationMs: Date.now() - processingStartedMs,
      usedSpeakerTracks: !speakerTracksSnapshot.empty && audioParts.length > 1,
      hasTranscript: (parsedResult.transcript || "").trim().length > 0,
    }));

    // Keep the transcript (but not the audio) for 30 days so participants can
    // read back what was actually said. Auto-deleted via a Firestore TTL
    // policy on `expiresAt` - no cleanup job needed.
    const transcriptText: string = parsedResult.transcript || "";
    if (transcriptText.trim().length > 0) {
      const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.collection("transcripts").doc(meetingId).set({
        meetingId,
        threadId,
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
    console.log(JSON.stringify({
      metric: "summary",
      status: "failed",
      meetingId,
      durationMs: Date.now() - processingStartedMs,
      error: String(error?.message || error).slice(0, 200),
    }));
    // Surface the failure immediately so the app can tell the user their
    // summary didn't generate, instead of leaving them waiting indefinitely.
    await db.collection("meetings").doc(meetingId).set(
      {
        summaryError: String(error?.message || error).slice(0, 500),
        summaryStatus: "failed",
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
