import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  WebhookReceiver,
  EgressClient,
  RoomServiceClient,
  EncodedFileType,
  EncodedFileOutput,
  GCPUpload,
  TrackType,
} from "livekit-server-sdk";
import { GoogleGenAI, Type, Schema, Part } from "@google/genai";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { assertCanJoinMeeting } from "./livekit";
import { requiredEnv } from "./config";
import { canStopMeeting } from "./meeting_access";
import { notifyUser } from "./notifications";

// All server-side integration configuration is read LAZILY inside handlers.
const livekitApiKey = () => requiredEnv("LIVEKIT_API_KEY");
const livekitApiSecret = () => requiredEnv("LIVEKIT_API_SECRET");
const geminiApiKey = () => requiredEnv("GEMINI_API_KEY");
const livekitHost = () => requiredEnv("LIVEKIT_HOST");
const egressBucket = () => requiredEnv("EGRESS_BUCKET");
const gcpEgressCredentials = () => requiredEnv("GCP_EGRESS_CREDENTIALS");

const WEBHOOK_SECRETS = [
  "LIVEKIT_API_KEY",
  "LIVEKIT_API_SECRET",
  "GEMINI_API_KEY",
  "LIVEKIT_HOST",
  "EGRESS_BUCKET",
  "GCP_EGRESS_CREDENTIALS",
];

const ENABLE_SPEAKER_TRACKS = process.env.ENABLE_SPEAKER_TRACKS === "true";

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

let _roomClient: RoomServiceClient | undefined;
function getRoomClient(): RoomServiceClient {
  if (!_roomClient) _roomClient = new RoomServiceClient(livekitHost(), livekitApiKey(), livekitApiSecret());
  return _roomClient;
}

let _genAI: GoogleGenAI | undefined;
function getGenAI(): GoogleGenAI {
  if (!_genAI) _genAI = new GoogleGenAI({ apiKey: geminiApiKey() });
  return _genAI;
}

export const meetingAnalysisSchema: Schema = {
  type: Type.OBJECT,
  properties: {
    detectedSpeakerProfiles: {
      type: Type.ARRAY,
      description:
        "Acoustic and contextual mapping of every distinct physical speaker in the meeting. Do NOT create separate profiles when the same person walks away from the mic or to a whiteboard.",
      items: {
        type: Type.OBJECT,
        properties: {
          internalVoiceId: {
            type: Type.STRING,
            description: "Unique ID per physical person, e.g., Speaker_A, Speaker_B",
          },
          invariantVocalTraits: {
            type: Type.STRING,
            description:
              "Distance-invariant vocal traits ONLY (pitch contour, vocal tract timbre/formants, accent, cadence). Ignore volume drops or room echo changes.",
          },
          matchedAttendeeName: {
            type: Type.STRING,
            description:
              "Matched real name from the Active Present Roster, or 'Guest 1', 'Guest 2' if unidentifiable.",
          },
          attributionEvidence: {
            type: Type.STRING,
            description:
              "Why this voice matches this name (e.g., 'Matched Reference Voiceprint for Alice + proximity to Mic #1 + conversational context').",
          },
        },
        required: [
          "internalVoiceId",
          "invariantVocalTraits",
          "matchedAttendeeName",
          "attributionEvidence",
        ],
      },
    },
    executiveSummary: {
      type: Type.STRING,
      description: "Comprehensive executive summary of the meeting.",
    },
    keyDecisions: {
      type: Type.ARRAY,
      description: "Final decisions agreed upon during the meeting.",
      items: { type: Type.STRING },
    },
    actionItems: {
      type: Type.ARRAY,
      description: "Concrete tasks and action items extracted from the meeting.",
      items: {
        type: Type.OBJECT,
        properties: {
          task: { type: Type.STRING },
          assignee: {
            type: Type.STRING,
            description:
              "Real name of the assignee (can be a present attendee or an absent group member mentioned by name).",
          },
          dueDateOrContext: { type: Type.STRING },
        },
        required: ["task", "assignee"],
      },
    },
    fullTranscript: {
      type: Type.ARRAY,
      description:
        "Complete chronological transcript using matchedAttendeeName from detectedSpeakerProfiles.",
      items: {
        type: Type.OBJECT,
        properties: {
          timestamp: { type: Type.STRING, description: "MM:SS format" },
          speaker: { type: Type.STRING },
          text: { type: Type.STRING },
        },
        required: ["timestamp", "speaker", "text"],
      },
    },
  },
  required: [
    "detectedSpeakerProfiles",
    "executiveSummary",
    "keyDecisions",
    "actionItems",
    "fullTranscript",
  ],
};

export interface AttendeeProfile {
  uid: string;
  name: string;
  voiceprintGcsPath?: string;
  geminiVoiceprintUri?: string;
  geminiVoiceprintExpiresAt?: number;
}

export interface UploadedMicTrack {
  userId: string;
  userName: string;
  gcsPath: string;
}

/**
 * Helper: Gets or uploads a user's 48-hour cached Gemini Voiceprint URI.
 * Checks Firestore users/{uid} for a cached geminiVoiceprintUri and reuses it
 * if valid within a 47-hour safe window.
 */
async function getOrUploadVoiceprintUri(
  bucket: any,
  attendee: AttendeeProfile,
  tempFilesToClean: string[]
): Promise<string | null> {
  if (!attendee.voiceprintGcsPath) return null;

  const now = Date.now();
  const SAFE_47_HOURS_MS = 47 * 60 * 60 * 1000;

  if (
    attendee.geminiVoiceprintUri &&
    attendee.geminiVoiceprintExpiresAt &&
    now < attendee.geminiVoiceprintExpiresAt - 3600000
  ) {
    return attendee.geminiVoiceprintUri;
  }

  const fileObj = bucket.file(attendee.voiceprintGcsPath);
  const [exists] = await fileObj.exists();
  if (!exists) return null;

  const localVoicePath = path.join(os.tmpdir(), `vp_${attendee.uid}_${now}.ogg`);
  await fileObj.download({ destination: localVoicePath });
  tempFilesToClean.push(localVoicePath);

  const ai = getGenAI();
  const uploadedVoice = await ai.files.upload({
    file: localVoicePath,
    config: {
      mimeType: "audio/ogg",
    },
  });

  if (!uploadedVoice.uri) return null;

  const expiresAt = now + SAFE_47_HOURS_MS;
  await admin
    .firestore()
    .collection("users")
    .doc(attendee.uid)
    .set(
      {
        geminiVoiceprintUri: uploadedVoice.uri,
        geminiVoiceprintExpiresAt: expiresAt,
      },
      { merge: true }
    );

  attendee.geminiVoiceprintUri = uploadedVoice.uri;
  attendee.geminiVoiceprintExpiresAt = expiresAt;

  return uploadedVoice.uri;
}

/**
 * Single entrypoint for all LiveKit server webhooks.
 *
 * Configured with timeoutSeconds: 540 and memory: 1GB to handle processing without timing out.
 * - room_started: Marks waiting_for_participants. Does NOT start egress for 1 person!
 * - participant_joined: Starts Egress only when numParticipants >= 2, guarded by Firestore transaction lock.
 * - egress_ended: If meeting < 30s, deletes audio and cancels to avoid silent hallucinations.
 */
export const livekitWebhook = functions
  .region("asia-south1")
  .runWith({
    secrets: WEBHOOK_SECRETS,
    timeoutSeconds: 540,
    memory: "1GB",
  })
  .https.onRequest(async (req, res) => {
    try {
      const event = await getReceiver().receive(req.body, req.headers.authorization);

      if (event.event === "room_started") {
        const roomName = event.room?.name;
        if (roomName) {
          await admin.firestore().collection("meetings").doc(roomName).set(
            {
              summaryStatus: "waiting_for_participants",
              lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
        res.status(200).send("Room started noted (waiting for 2+ participants)");
        return;
      }

      if (event.event === "participant_joined") {
        const roomName = event.room?.name;
        const numParticipants = event.room?.numParticipants ?? 0;
        if (roomName && numParticipants >= 2) {
          await handleParticipantJoined(roomName, numParticipants);
        }
        res.status(200).send("Participant joined handled");
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
 * Starts LiveKit Room Composite Egress only when 2 or more participants have joined.
 * Uses a Firestore transaction lock so concurrent joins don't trigger duplicate egress jobs.
 */
export async function handleParticipantJoined(roomName?: string, numParticipants?: number) {
  if (!roomName || (numParticipants !== undefined && numParticipants < 2)) return;

  const db = admin.firestore();
  const meetingRef = db.collection("meetings").doc(roomName);

  // Firestore transaction to guarantee only one egress starts
  const shouldStart = await db.runTransaction(async (tx) => {
    const doc = await tx.get(meetingRef);
    const data = doc.data();
    if (data?.egressStatus === "starting" || data?.egressStatus === "active" || data?.egressId) {
      return false;
    }
    tx.set(
      meetingRef,
      {
        egressStatus: "starting",
        summaryStatus: "recording",
        summaryError: admin.firestore.FieldValue.delete(),
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return true;
  });

  if (!shouldStart) {
    return;
  }

  // Double check with LiveKit that no egress is already active for this room
  const active = await getEgressClient().listEgress({ roomName, active: true });
  if (active.length > 0) {
    console.log(`Egress already running for room ${roomName}`);
    await meetingRef.set({ egressStatus: "active", egressId: active[0].egressId }, { merge: true });
    return;
  }

  const objectKey = `egress-tmp/${roomName}-${Date.now()}.ogg`;
  console.log(`Starting audio-only room composite egress for ${roomName} (>=2 participants) -> gs://${egressBucket()}/${objectKey}`);

  try {
    const info = await getEgressClient().startRoomCompositeEgress(
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
    await meetingRef.set({ egressStatus: "active", egressId: info.egressId, egressObjectKey: objectKey }, { merge: true });
  } catch (err) {
    console.error(`Failed to start egress for ${roomName}:`, err);
    await meetingRef.set({ egressStatus: "failed" }, { merge: true });
  }
}

/**
 * Legacy handler kept for interface consistency.
 */
export async function handleRoomStarted(roomName?: string) {
  if (!roomName) return;
  await admin.firestore().collection("meetings").doc(roomName).set(
    {
      summaryStatus: "waiting_for_participants",
      lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Optional per-speaker microphone recording when ENABLE_SPEAKER_TRACKS is enabled.
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

/**
 * Handles completion of LiveKit Egress.
 * Enforces the minimum duration guard: recordings under 30s are deleted and marked cancelled_too_short.
 */
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

  // Check recording duration
  let durationSec = 0;
  if (egressInfo.duration) {
    const d = Number(egressInfo.duration);
    durationSec = d > 1e6 ? d / 1e9 : d;
  } else if (egressInfo.startedAt && egressInfo.endedAt) {
    const diff = Number(egressInfo.endedAt) - Number(egressInfo.startedAt);
    durationSec = diff > 1e12 ? diff / 1e9 : diff > 1e6 ? diff / 1e3 : diff;
  }

  // Minimum Duration Guard: less than 30 seconds
  if (durationSec > 0 && durationSec < 30) {
    console.log(`Meeting ${meetingId} egress lasted ${durationSec.toFixed(1)}s (< 30s). Cancelling without AI hallucination.`);
    const bucket = admin.storage().bucket(egressBucket());
    try {
      await bucket.file(objectKey).delete({ ignoreNotFound: true });
    } catch (delErr) {
      console.warn(`Could not delete short recording ${objectKey}:`, delErr);
    }
    await admin.firestore().collection("meetings").doc(meetingId).set(
      {
        status: "cancelled_too_short",
        summaryStatus: "cancelled_too_short",
        summaryError: "Meeting was under 30 seconds. No summary generated.",
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return;
  }

  // Speaker track recording finished
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

  // Process the room composite recording
  await processAudioAndSummarize({
    meetingId,
    bucketName: egressBucket(),
    micTracks: [
      {
        userId: "room",
        userName: "LiveKit Room Audio",
        gcsPath: objectKey,
      },
    ],
  });
}

/**
 * Lets a client proactively finalize a meeting's recording.
 */
export const stopMeetingEgress = functions
  .region("asia-south1")
  .runWith({ secrets: WEBHOOK_SECRETS, timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
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

    if (!canStopMeeting({ groupId: meeting.groupId, participantIds, organizerId }, context.auth.uid, adminIds)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the meeting organizer or a group admin can stop the recording."
      );
    }

    await meetingRef.set({ lastActivityAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    let active = await getEgressClient().listEgress({ roomName: meetingId, active: true });
    for (let attempt = 0; active.length === 0 && attempt < 3; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      active = await getEgressClient().listEgress({ roomName: meetingId, active: true });
    }

    await Promise.all(active.map((e) => getEgressClient().stopEgress(e.egressId)));
    return { stopped: active.length };
  });

/**
 * Forcefully terminates the room, kicking all participants and stopping egress.
 */
export const endMeetingRoom = functions
  .region("asia-south1")
  .runWith({ secrets: WEBHOOK_SECRETS, timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
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

    if (!canStopMeeting({ groupId: meeting.groupId, participantIds, organizerId }, context.auth.uid, adminIds)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the meeting organizer or a group admin can end the meeting."
      );
    }

    await meetingRef.set({ lastActivityAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    try {
      await getRoomClient().deleteRoom(meetingId);
      return { success: true };
    } catch (error: any) {
      console.error(`Failed to delete room ${meetingId}:`, error);
      let active = await getEgressClient().listEgress({ roomName: meetingId, active: true });
      await Promise.all(active.map((e) => getEgressClient().stopEgress(e.egressId)));
      return { success: true };
    }
  });

/**
 * Uploads directly recorded in-person meeting audio to GCS and triggers AI summarization.
 */
export const uploadMeetingAudio = functions
  .region("asia-south1")
  .runWith({ secrets: WEBHOOK_SECRETS, timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const { meetingId, audioBase64, mimeType } = data;
    if (!meetingId || !audioBase64) {
      throw new functions.https.HttpsError("invalid-argument", "meetingId and audioBase64 are required.");
    }

    await assertCanJoinMeeting(meetingId, context.auth.uid);

    const buffer = Buffer.from(audioBase64, "base64");
    const ext = mimeType?.includes("webm") ? "webm" : mimeType?.includes("mp4") ? "mp4" : "ogg";
    const objectKey = `egress-tmp/${meetingId}-${Date.now()}.${ext}`;
    const bucketName = egressBucket();
    const bucket = admin.storage().bucket(bucketName);
    const file = bucket.file(objectKey);

    await file.save(buffer, {
      metadata: {
        contentType: mimeType || "audio/ogg",
      },
    });

    console.log(`Saved in-person audio to gs://${bucketName}/${objectKey} (${buffer.length} bytes, format: ${ext}).`);

    await admin.firestore().collection("meetings").doc(meetingId).set(
      {
        status: "ready_for_ai",
        summaryStatus: "processing",
        inPersonObjectKey: objectKey,
        uploadedAudioPaths: [
          {
            userId: context.auth.uid,
            userName: context.auth.token.name || "Host",
            gcsPath: objectKey,
          },
        ],
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { success: true };
  });

/**
 * Background trigger for in-person meetings.
 * Fires when status transitions to 'ready_for_ai' or when summaryStatus becomes 'processing'.
 */
export const processInPersonAudio = functions
  .region("asia-south1")
  .runWith({ secrets: WEBHOOK_SECRETS, timeoutSeconds: 540, memory: "1GB" })
  .firestore.document("meetings/{meetingId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const isReadyForAi = before.status !== "ready_for_ai" && after.status === "ready_for_ai";
    const isLegacyProcessing =
      before.summaryStatus !== "processing" && after.summaryStatus === "processing" && after.inPersonObjectKey;

    if (isReadyForAi || isLegacyProcessing) {
      const meetingId = context.params.meetingId;
      console.log(`Background processing started for in-person meeting ${meetingId}`);

      const micTracks: UploadedMicTrack[] = [];
      if (Array.isArray(after.uploadedAudioPaths) && after.uploadedAudioPaths.length > 0) {
        for (const item of after.uploadedAudioPaths) {
          if (item?.gcsPath) {
            micTracks.push({
              userId: item.userId || "unknown",
              userName: item.userName || "Participant",
              gcsPath: item.gcsPath,
            });
          }
        }
      } else if (after.inPersonObjectKey) {
        micTracks.push({
          userId: after.hostUserId || "host",
          userName: "Room Mic",
          gcsPath: after.inPersonObjectKey,
        });
      }

      await processAudioAndSummarize({
        meetingId,
        bucketName: egressBucket(),
        micTracks,
      });
    }
  });

/**
 * Main AI Ingestion & Summarization Pipeline.
 *
 * Supports both LiveKit single-file and In-Person multi-mic spatial recordings.
 *
 * Architectural Features:
 * 1. Separates Present Attendees from Absent Group Members.
 * 2. Caches Gemini File API URIs for 48 hours on users/{uid}.
 * 3. Enforces Two-Pass Schema: detectedSpeakerProfiles first, fullTranscript last.
 * 4. Imparts distance-invariant vocal trait instructions for room movement & whiteboard speakers.
 * 5. Passes multiple .ogg tracks as spatial zone parts without destructive comb filtering.
 * 6. Preserves complete backward compatibility with threads/{threadId} and transcripts/{meetingId}.
 */
export async function processAudioAndSummarize(input: {
  meetingId: string;
  bucketName?: string;
  micTracks?: UploadedMicTrack[];
  presentAttendees?: AttendeeProfile[];
  absentGroupMemberNames?: string[];
  coLocatedPairs?: Record<string, string[]>;
}): Promise<string> {
  const db = admin.firestore();
  const meetingId = input.meetingId;
  const bucketName = input.bucketName || egressBucket();
  const bucket = admin.storage().bucket(bucketName);
  const STALE_CLAIM_MS = 5 * 60 * 1000;
  const meetingRef = db.collection("meetings").doc(meetingId);

  // Claim processing lock
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
    const currentDoc = await meetingRef.get();
    return currentDoc.data()?.threadId || "";
  }

  const processingStartedMs = Date.now();
  const meetingDocSnap = await meetingRef.get();
  const meetingData = meetingDocSnap.data() || {};

  // 1. Resolve Mic Tracks
  let micTracks: UploadedMicTrack[] = input.micTracks || [];
  if (micTracks.length === 0) {
    if (Array.isArray(meetingData.uploadedAudioPaths) && meetingData.uploadedAudioPaths.length > 0) {
      micTracks = meetingData.uploadedAudioPaths;
    } else if (meetingData.inPersonObjectKey) {
      micTracks = [
        {
          userId: meetingData.hostUserId || "host",
          userName: "Room Mic",
          gcsPath: meetingData.inPersonObjectKey,
        },
      ];
    } else if (meetingData.egressObjectKey) {
      micTracks = [
        {
          userId: "room",
          userName: "LiveKit Room Audio",
          gcsPath: meetingData.egressObjectKey,
        },
      ];
    }
  }

  if (micTracks.length === 0) {
    console.error(`No audio tracks found for meeting ${meetingId}`);
    await meetingRef.set({ summaryStatus: "failed", summaryError: "No audio tracks found." }, { merge: true });
    return "";
  }

  // 2. Resolve Present Attendees vs Absent Group Members
  const presentUids = new Set<string>();
  const coLocatedMap: Record<string, string[]> = meetingData.coLocatedMap || {};

  if (Array.isArray(meetingData.presentParticipantIds)) {
    meetingData.presentParticipantIds.forEach((uid: string) => presentUids.add(uid));
  }
  if (Array.isArray(meetingData.participantIds)) {
    meetingData.participantIds.forEach((uid: string) => presentUids.add(uid));
  }
  for (const track of micTracks) {
    if (track.userId && track.userId !== "room") presentUids.add(track.userId);
  }
  for (const [hostId, guestIds] of Object.entries(coLocatedMap)) {
    presentUids.add(hostId);
    if (Array.isArray(guestIds)) guestIds.forEach((gid) => presentUids.add(gid));
  }

  const presentAttendees: AttendeeProfile[] = [];
  const userDocs = await Promise.all(
    Array.from(presentUids).map(async (uid) => {
      try {
        const uSnap = await db.collection("users").doc(uid).get();
        return { uid, snap: uSnap };
      } catch (_) {
        return { uid, snap: null };
      }
    })
  );

  for (const item of userDocs) {
    const uData = item.snap?.data();
    const meetingParticipant = (meetingData.participants || []).find((p: any) => p.id === item.uid);
    const resolvedName = meetingParticipant?.name || uData?.name || `Participant ${item.uid.substring(0, 5)}`;
    presentAttendees.push({
      uid: item.uid,
      name: resolvedName,
      voiceprintGcsPath: `users/${item.uid}/voiceprint.ogg`,
      geminiVoiceprintUri: uData?.geminiVoiceprintUri,
      geminiVoiceprintExpiresAt: uData?.geminiVoiceprintExpiresAt,
    });
  }

  // Absent group members
  const absentGroupMemberNames: string[] = [];
  if (meetingData.groupId) {
    try {
      const gSnap = await db.collection("groups").doc(meetingData.groupId).get();
      const gData = gSnap.data();
      const members: any[] = gData?.members || [];
      for (const m of members) {
        if (m?.id && !presentUids.has(m.id)) {
          if (m?.name && !absentGroupMemberNames.includes(m.name)) {
            absentGroupMemberNames.push(m.name);
          }
        }
      }
    } catch (gErr) {
      console.error(`Could not load group roster for meeting ${meetingId}:`, gErr);
    }
  }

  // Co-located named map
  const coLocatedPairs: Record<string, string[]> = {};
  for (const [hostId, guestIds] of Object.entries(coLocatedMap)) {
    const hostAttendee = presentAttendees.find((a) => a.uid === hostId);
    const hostName = hostAttendee?.name || "Host";
    const guestNames = guestIds.map((gid) => {
      const ga = presentAttendees.find((a) => a.uid === gid);
      return ga?.name || "Guest";
    });
    if (guestNames.length > 0) {
      coLocatedPairs[hostName] = guestNames;
    }
  }

  const tempFilesToClean: string[] = [];
  const uploadedMeetingFileNames: string[] = [];
  const ai = getGenAI();

  try {
    const promptParts: Part[] = [];

    // Step A: Attach Reference Voiceprints ONLY for Present Attendees (using 48h URI cache)
    for (const attendee of presentAttendees) {
      const voiceUri = await getOrUploadVoiceprintUri(bucket, attendee, tempFilesToClean);
      if (!voiceUri) continue;

      promptParts.push({
        text: `REFERENCE VOICEPRINT FOR PRESENT ATTENDEE "${attendee.name}":`,
      });
      promptParts.push({
        fileData: {
          fileUri: voiceUri,
          mimeType: "audio/ogg",
        },
      });
    }

    // Step B: Build Roster, Co-Location & Multi-Mic Context
    const presentNames = presentAttendees.map((a) => a.name);
    const absentNames = absentGroupMemberNames.filter((n) => !presentNames.includes(n));

    let coLocationNote = "";
    if (Object.keys(coLocatedPairs).length > 0) {
      const lines = Object.entries(coLocatedPairs).map(
        ([hostName, guests]) =>
          `- ${hostName} and ${guests.join(", ")} are sitting in the same physical room sharing a single microphone.`
      );
      coLocationNote = `\nSHARED MICROPHONE / CO-LOCATED SPEAKERS ALERT:\n${lines.join("\n")}\n`;
    }

    const multiMicNotice =
      micTracks.length > 1
        ? `
MULTI-MICROPHONE SPATIAL AUDIO NOTICE:
This in-person meeting was recorded simultaneously using ${micTracks.length} phones placed in different zones of the room to cover a larger group.
- All ${micTracks.length} audio files below capture the EXACT SAME meeting simultaneously from different table/room positions.
- DO NOT duplicate transcript lines, decisions, or action items heard across multiple microphones!
- Cross-reference the microphones: if a speaker walks to the whiteboard and sounds distant/echoey on Microphone #1, listen to Microphone #2 or #3 where their voice is clearer to transcribe their words and identify their voice accurately.
`
        : "";

    // Step C: Construct Instructions with Distance-Invariant Movement Rules
    promptParts.push({
      text: `
You are analyzing a recorded group meeting audio stream for Convexa.

ACTIVE SPEAKERS PRESENT IN THIS MEETING:
${presentNames.length > 0 ? presentNames.join(", ") : "Unknown (Use Guest 1, Guest 2, etc.)"}

ABSENT GROUP MEMBERS (NOT speaking in this audio, but tasks/action items CAN still be assigned to them if mentioned by name):
${absentNames.length > 0 ? absentNames.join(", ") : "None"}
${coLocationNote}
${multiMicNotice}
CRITICAL SPEAKER IDENTIFICATION & ROOM MOVEMENT RULES:
1. ONLY attribute spoken dialogue in the transcript to people in the ACTIVE SPEAKERS PRESENT list (or "Guest 1", "Guest 2" for unidentified voices). NEVER attribute spoken lines to ABSENT GROUP MEMBERS.
2. SPEAKERS WILL MOVE AROUND THE ROOM: In in-person or shared-mic meetings, speakers frequently walk to whiteboards, pace, or turn away from the microphone.
   - DO NOT split one physical person into multiple speakers when their volume drops or room echo/reverb increases.
   - Ignore loudness, microphone distance, and room reverberation.
   - Match voices strictly using distance-invariant vocal traits: vocal tract timbre (formants), pitch contour, accent, speaking cadence, the Reference Voiceprints provided above, and conversational continuity (e.g., if Alice says "Let me draw this on the board" and a distant voice continues the explanation, keep labeling that voice as Alice).
3. Complete "detectedSpeakerProfiles" FIRST to lock in your voice-to-name mapping before generating the executiveSummary, keyDecisions, actionItems, and fullTranscript.
      `.trim(),
    });

    // Step D: Download & Upload Meeting Audio Tracks to Gemini Files API
    for (let i = 0; i < micTracks.length; i++) {
      const track = micTracks[i];
      const ext = track.gcsPath.endsWith(".webm") ? "webm" : track.gcsPath.endsWith(".mp4") ? "mp4" : "ogg";
      const inferredMime = ext === "webm" ? "audio/webm" : ext === "mp4" ? "audio/mp4" : "audio/ogg";
      const localMeetingPath = path.join(os.tmpdir(), `meeting_${meetingId}_mic_${i}_${Date.now()}.${ext}`);

      await bucket.file(track.gcsPath).download({ destination: localMeetingPath });
      tempFilesToClean.push(localMeetingPath);

      const uploadedMeeting = await ai.files.upload({
        file: localMeetingPath,
        config: {
          mimeType: inferredMime,
        },
      });

      if (uploadedMeeting.name) {
        uploadedMeetingFileNames.push(uploadedMeeting.name);
      }

      promptParts.push({
        text:
          micTracks.length === 1
            ? `FULL MEETING AUDIO RECORDING (${track.userName}):`
            : `ROOM MICROPHONE #${i + 1} (Placed near ${track.userName}'s area of the room):`,
      });

      promptParts.push({
        fileData: {
          fileUri: uploadedMeeting.uri,
          mimeType: inferredMime,
        },
      });
    }

    // Step E: Call Gemini 3.8 Flash with Two-Pass Schema
    console.log(`Calling gemini-3.8-flash for meeting ${meetingId} with ${micTracks.length} mic track(s)...`);
    const response = await ai.models.generateContent({
      model: "gemini-3.8-flash",
      contents: [{ role: "user", parts: promptParts }],
      config: {
        responseMimeType: "application/json",
        responseSchema: meetingAnalysisSchema,
        temperature: 0.1,
      },
    });

    const rawJson = response.text || "{}";
    const parsedResult = JSON.parse(rawJson);

    // Step F: Transform and Commit Results
    const meetingTitle = meetingData.title || "Untitled Meeting";
    const groupId = meetingData.groupId || null;
    const participants = meetingData.participants || presentAttendees.map((a) => ({ id: a.uid, name: a.name }));
    const participantIds = Array.from(presentUids);

    // Convert structured analysis to SmartBlock items for thread backward compatibility
    const smartBlocks: any[] = [];
    if (parsedResult.executiveSummary) {
      smartBlocks.push({ type: "summary", content: parsedResult.executiveSummary });
    }
    for (const decision of parsedResult.keyDecisions || []) {
      smartBlocks.push({ type: "decision", content: decision });
    }
    for (const item of parsedResult.actionItems || []) {
      const taskLabel = item.dueDateOrContext ? `${item.task} (${item.dueDateOrContext})` : item.task;
      smartBlocks.push({
        type: "action_item",
        content: taskLabel,
        assignee: item.assignee,
      });
    }

    // Convert full transcript array to text string
    const transcriptLines = (parsedResult.fullTranscript || []).map((entry: any) => {
      const ts = entry.timestamp ? `[${entry.timestamp}] ` : "";
      return `${ts}${entry.speaker}: ${entry.text}`;
    });
    const formattedTranscript = transcriptLines.join("\n");

    // Manage Topic/Thread
    const targetTopicId: string | null = meetingData.topicId || null;
    let threadId = "";
    let isNewTopic = true;

    if (targetTopicId) {
      const topicRef = db.collection("threads").doc(targetTopicId);
      const appended = await db.runTransaction(async (tx) => {
        const snap = await tx.get(topicRef);
        if (!snap.exists) return false;
        const existing = snap.data()!;
        const dateLabel = new Date().toISOString().slice(0, 10);
        const dividerBlock = {
          type: "key_insight",
          content: `🗓️ New session — ${meetingTitle} · ${dateLabel}`,
        };
        const mergedBlocks = [...(existing.blocks || []), dividerBlock, ...smartBlocks];
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
        vibe: "Productive & Focused",
        vibeEmoji: "🚀",
        blocks: smartBlocks,
      });
      threadId = threadRef.id;

      if (groupId) {
        await db.collection("groups").doc(groupId).update({
          threadIds: admin.firestore.FieldValue.arrayUnion(threadId),
        });
      }
    }

    // Save final analysis on the meeting document
    await meetingRef.set(
      {
        status: "completed",
        summaryStatus: "ready",
        summaryError: admin.firestore.FieldValue.delete(),
        threadId,
        detectedSpeakerProfiles: parsedResult.detectedSpeakerProfiles || [],
        executiveSummary: parsedResult.executiveSummary || "",
        keyDecisions: parsedResult.keyDecisions || [],
        actionItems: parsedResult.actionItems || [],
        transcript: parsedResult.fullTranscript || [],
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Save 30-day TTL transcript document
    if (formattedTranscript.trim().length > 0) {
      const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.collection("transcripts").doc(meetingId).set({
        meetingId,
        threadId,
        groupId,
        participantIds,
        transcript: formattedTranscript,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
      });
    }

    // Best-effort user notifications
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

      for (const item of parsedResult.actionItems || []) {
        if (!item?.assignee) continue;
        const assigneeLower = String(item.assignee).trim().toLowerCase();
        const match = participants.find((p: any) =>
          typeof p?.name === "string" && p.name.split(" ")[0].toLowerCase() === assigneeLower
        );
        if (match?.id) {
          await notifyUser(match.id, {
            type: "action_assigned",
            title: "You were assigned an action",
            body: item.task,
            route: `/thread/${threadId}`,
            relatedId: threadId,
          });
        }
      }
    } catch (notifyErr) {
      console.error(`Failed to send summary notifications for ${meetingId}:`, notifyErr);
    }

    console.log(
      JSON.stringify({
        metric: "summary",
        status: "ready",
        meetingId,
        durationMs: Date.now() - processingStartedMs,
        numMics: micTracks.length,
        hasTranscript: formattedTranscript.length > 0,
      })
    );

    // Delete meeting recordings from GCS now that they are processed
    for (const track of micTracks) {
      if (track.gcsPath) {
        await bucket.file(track.gcsPath).delete({ ignoreNotFound: true });
      }
    }

    return threadId;
  } catch (err: any) {
    console.error(`Error processing meeting ${meetingId}:`, err);
    await meetingRef.set(
      {
        summaryStatus: "failed",
        summaryError: String(err?.message || err),
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    throw err;
  } finally {
    // Cleanup local /tmp files and temporary meeting files in Gemini Files API
    // Note: Cached user voiceprints are intentionally preserved for 48 hours
    for (const filePath of tempFilesToClean) {
      if (fs.existsSync(filePath)) {
        try {
          fs.unlinkSync(filePath);
        } catch (e) {
          // Ignore local temp cleanup error
        }
      }
    }
    for (const geminiFileName of uploadedMeetingFileNames) {
      try {
        await ai.files.delete({ name: geminiFileName });
      } catch (e) {
        // Ignore gemini file deletion error
      }
    }
  }
}
