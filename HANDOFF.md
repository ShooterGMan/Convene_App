# Convene — Project Handoff & Continuation Notes

AI-powered meeting app: records meetings (online via LiveKit, or in-person on one
device), and a server-side Gemini pipeline auto-generates a shared summary
(decisions, action items, transcript) per meeting.

- **Live web app:** https://meeting-app-844aa.web.app
- **Firebase project:** `meeting-app-844aa`
- **GitHub:** https://github.com/ShooterGMan/Convene_App
- **LiveKit Cloud:** `wss://convene-app-a9liwgoq.livekit.cloud`

---

## Architecture

- **Client:** Flutter (web + Android). Riverpod state, go_router navigation.
- **Backend:** Firebase — Firestore (data), Auth (Google + email/password),
  Cloud Functions (1st-gen / Node 20), Hosting.
- **Realtime meetings:** LiveKit Cloud (SFU). Room Composite Egress (mixed audio)
  + per-participant Track Composite Egress (for speaker attribution).
- **AI summaries:** Cloud Function `livekitWebhook` receives LiveKit's
  `egress_ended`, downloads the audio from a GCS bucket, sends it to Gemini
  (`@google/genai`), and writes one summary "thread" to Firestore.
- **Webhook delivery:** LiveKit → `/livekitWebhook` (Firebase Hosting rewrite →
  function, to dodge a Cloud Run OIDC header quirk).

### Firestore collections
`users`, `groups` (+ `pendingInvites` subcol), `meetings`, `threads`
(+ `comments` subcol), `transcripts` (30-day TTL), `users/{id}/notifications`.
Security rules restrict all reads/writes to owners/participants/group-members;
membership/admin changes go through Cloud Functions (Admin SDK).

---

## Setup on a NEW device

```bash
git clone https://github.com/ShooterGMan/Convene_App.git
cd Convene_App
flutter pub get
cd functions && npm install && cd ..
firebase login          # must have access to project meeting-app-844aa
flutterfire configure   # only if firebase_options.dart is missing
```

### ⚠️ Secrets are NOT in git (by design) — recreate them manually
The `.gitignore` excludes `.env` and `functions/.env`. Copy these from your
other device (or your password manager) — they are NOT in the repo:

**`functions/.env`** (the important one — server-side, powers everything):
```
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
GEMINI_API_KEY=...            # rotate if ever exposed; this is the live one
LIVEKIT_HOST=https://convene-app-a9liwgoq.livekit.cloud
EGRESS_BUCKET=...             # GCS bucket for egress audio
GCP_EGRESS_CREDENTIALS=...    # service-account JSON, minified to one line
```
`functions/.env.example` is the safe local template. The backend now fails
closed if any required setting is absent. Before the next production deploy,
migrate each value into Firebase Secret Manager and grant it to the matching
functions (the code declares these bindings):

```bash
firebase functions:secrets:set LIVEKIT_API_KEY
firebase functions:secrets:set LIVEKIT_API_SECRET
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set LIVEKIT_HOST
firebase functions:secrets:set EGRESS_BUCKET
firebase functions:secrets:set GCP_EGRESS_CREDENTIALS
firebase deploy --only functions
```
There is **no** client-side `.env` anymore (removed — it was exposing the Gemini
key in the web bundle). Don't recreate one.

### Build & deploy
```bash
flutter build web --release
firebase deploy --only hosting
firebase deploy --only functions            # or functions:<name>
firebase deploy --only firestore:rules
flutter build apk --release                 # Android build
```
Android Google Sign-In needs the debug/release keystore SHA-1 registered in
Firebase (already done for the current debug key). App Links use
`web/.well-known/assetlinks.json`.

**Build stamp:** `lib/build_info.dart` holds `kBuildStamp`, shown in
Settings → About. Bump it each deploy so you can confirm a device isn't on a
stale cached build. (Hosting sends no-cache headers on index.html/service worker
to prevent staleness.)

---

## What's built (working)

- Auth: Google + email/password (both now create Firestore user docs; signup
  collects a name).
- Online meetings (LiveKit): pre-join screen (device check + **name entry**),
  live meeting (grid/speaker view, **pin any participant**, chat, reactions,
  screen share on desktop/native only, elapsed timer, invite link).
- In-person/offline recording (single device → same egress/summary pipeline).
- AI summaries with speaker attribution via per-participant tracks (real names
  flow: signup/pre-join name → LiveKit identity → track label → Gemini).
- Groups: create, shareable invite links, email invites w/ accept/decline,
  **multiple admins**, promote/demote, remove members, **delete group**, "New"
  badges.
- Meetings: schedule (duration picker, group link, guest emails auto-resolved to
  participants server-side), **RSVP yes/no/maybe** + attendee breakdown, best-
  effort Google Calendar sync (non-blocking).
- Upcoming screen: real upcoming vs collapsed past, filters (type/group),
  **month calendar view**, "live now / starts soon" banner.
- Threads: summary blocks, check-off action items (persisted), comments,
  transcript view, group pill.
- In-app **notifications** (bell + nav-tab badges + chime) — invites,
  accept/decline, added-to-meeting. NO push notifications yet (in-app only).
- First-run **onboarding tutorial** (replayable from Settings).
- Settings: profile edit, theme (light/dark/system), delete account.
- Firestore security rules verified via the rules-test API (cross-user reads
  denied).

---

## Known issues / open decisions

1. **Beta recording capacity: mixed audio only.** Per-speaker track egress is
   disabled by default via `ENABLE_SPEAKER_TRACKS=false`, so each meeting uses
   one room-composite egress. Gemini will attribute mixed audio as Speaker 1,
   Speaker 2, etc. Re-enable per-speaker tracks only after upgrading LiveKit
   capacity and testing the associated cost/concurrency limits.
2. **Direct (non-group) meeting links** reported flaky by a tester; join path is
   shared with working group meetings, so cause unconfirmed. Instant meetings
   now create a real doc up front. If still failing, capture the EXACT symptom
   (spinner? error text? nothing on tap?).
3. **At-rest data visibility:** project owner can read all data in the Firestore
   console — this is normal for any hosted DB (rules govern app access, not
   console). True E2EE is impossible here because the server must read meeting
   content to run Gemini. Deferred: app-layer field encryption (big rework,
   partial protection). For now: lock down GCP IAM access.
4. **Offline speaker attribution:** plan is A+C (context-aware Gemini using
   RSVP'd attendee names + human correction) now, voiceprints (D) later. NOT yet
   implemented — the offline Gemini path doesn't yet receive attendee names.
   See memory `offline-attribution-strategy`.
5. **Node 20 runtime deprecated** (decommission 2026-10-30) and
   `firebase-functions` is outdated — upgrade before then.
6. Deferred: WhatsApp/external deep-link opening reliability, mobile-web screen
   share (browser limitation — impossible on mobile browsers).

---

## Suggested next steps

1. Decide the LiveKit $50 plan (needed for any real multi-user test).
2. Polish whatever friction shows up in the next real-user test (onboarding,
   first-run clarity, error states).
3. Implement offline attribution A (pass RSVP'd attendee names into the offline
   Gemini prompt) — small, high-value.
4. Consider push notifications (FCM) so invites/reminders reach closed apps.
