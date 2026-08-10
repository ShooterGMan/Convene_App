# Convene Roadmap: From Current Build to User-Ready Release

**Product focus:** Convene is a shared decision memory for teams. It should make it easy to capture a meeting, understand what was decided, and follow one topic across meetings and teams.

## How to use this plan

- Work from top to bottom: each phase removes a prerequisite for the next one.
- Check an item only when its acceptance criteria have been verified.
- Keep `lib/build_info.dart` current for every build given to testers.
- Do all beta testing against a **staging** Firebase/LiveKit project, never the production project.

---

## Current state — already implemented

This is the starting point for the roadmap. These features exist in the codebase; they still need the device, security, and end-to-end verification called out later in this plan before being considered release-ready.

### Account and app foundation

- [x] Firebase Authentication with Google and email/password sign-in.
- [x] Firestore user profiles, profile editing, account deletion, onboarding, and light/dark/system themes.
- [x] Flutter web and Android project setup, Firebase Hosting configuration, and App Links configuration for Android.
- [x] Riverpod state management, GoRouter routing, and deep-link preservation through login.
- [x] In-app error fallback screen and build stamp shown in Settings.

### Meetings and collaboration

- [x] Schedule meetings with title, time, duration, group association, guest emails, and best-effort Google Calendar creation.
- [x] Instant/direct meetings and shareable meeting links.
- [x] RSVP states and attendee breakdown.
- [x] Upcoming meetings screen with filters, past/upcoming sections, live/starts-soon messaging, and an existing month-calendar view.
- [x] Groups: create, join by link, email invites, accept/decline, multiple admins, member removal, promotion/demotion, and deletion.
- [x] In-app notifications for group and meeting activity.

### Live meeting experience

- [x] Pre-join camera/microphone test, device selectors, mute toggles, and editable meeting name.
- [x] LiveKit-powered video/audio meetings on supported platforms.
- [x] Participant grid, speaker view, active-speaker indication, participant pinning, chat, reactions, elapsed time, and invite sharing.
- [x] Screen sharing on desktop web/native platforms; intentionally unavailable on mobile web.
- [x] In-person/single-device recording flow.

### AI meeting memory

- [x] LiveKit egress recording pipeline for online meetings.
- [x] Gemini-powered summary, decisions, action items, and transcript generation.
- [x] Context-thread UI with summary blocks, action-item completion, comments, transcript display, and group association.
- [x] Per-speaker track recording design for online speaker attribution, with mixed-audio fallback.
- [x] Firestore access rules around users, groups, meetings, threads, transcripts, comments, and notifications.
- [x] Stuck-meeting detection and surfaced summary errors.

### Work currently in progress (uncommitted at the time this roadmap was written)

- [ ] FCM push-notification registration, token cleanup on sign-out, web service worker, and server-side delivery.
  - Web push is not complete: the VAPID public key has not been configured or tested.
- [ ] Mobile form-sheet scrolling/keyboard fixes and routing refinements.

### Changes completed after this roadmap was created

- [x] Hardened LiveKit meeting access in the Cloud Functions source.
  - Unknown meeting IDs are rejected instead of creating a document implicitly.
  - Group meetings require either group membership or an existing participant entry.
  - Only the organizer or a group admin can stop meeting egress.
  - Newly created direct-meeting IDs use 96 cryptographically random bits rather than predictable timestamps.
  - Quick in-person recordings now create their meeting document before joining.
- [x] Removed insecure server credential fallbacks.
  - Required LiveKit, Gemini, egress bucket, and service-account configuration now fails closed when missing.
  - Required configuration is bound to the relevant Cloud Functions as Firebase Secret Manager secrets.
  - Added `functions/.env.example` as a safe local-development template.
- [x] Restored the Cloud Functions lint gate.
  - Added a TypeScript-aware ESLint configuration that excludes generated output.
  - `npm run lint` and `npm run build` now pass in `functions/`.
- [x] Added explicit summary-processing states.
  - The backend records `recording`, `processing`, `ready`, and `failed` as the egress pipeline progresses.
  - The meeting card shows a clear “Generating your meeting summary” state.
  - Stuck meetings and processing errors now consistently resolve to `failed`.
- [x] Chosen the beta recording-capacity approach: mixed audio only.
  - Per-speaker egress is disabled by default behind `ENABLE_SPEAKER_TRACKS=false`.
  - Gemini summaries will use Speaker 1/2/3 attribution for mixed audio during beta.
- [x] Added automated backend authorization-policy tests.
  - Six passing tests cover direct guests, group participants, group members, unrelated users, organizers, and group admins.
  - `npm run test` now builds and runs the Functions test suite.

### Known verification gaps

- [ ] Flutter analyze, Flutter tests, and release web build have not yet completed successfully in the current local environment.
- [ ] Only a placeholder Flutter test currently exists.
- [x] Cloud Functions TypeScript build and lint both pass locally.
- [ ] No CI workflow is present yet.

---

## Phase 0 — Establish the release baseline

**Goal:** Know exactly what is being tested and make the repository safe to change.

- [ ] Commit or intentionally discard the current local changes after review.
  - Current changes include push-notification wiring, dependency updates, routing, and sheet scrolling fixes.
  - Do not deploy changes that have not been reviewed on a real device.
- [ ] Replace the template `README.md` with project setup, local run, test, staging, and deployment instructions.
- [ ] Update web metadata in `web/index.html`.
  - Title: `Convene — Shared Decision Memory`.
  - Replace the generic description with a real product description.
  - Add social preview metadata and a branded sharing image.
- [ ] Reconcile `features.md` with the code.
  - Remove or mark as planned any feature that is not currently implemented (for example, custom vocabulary and configurable summary detail levels).
- [ ] Decide the supported beta platforms.
  - Recommended: **web + Android first**.
  - Treat iOS as a separate release track until camera/microphone, deep links, push, signing, and device tests are complete.
- [ ] Create `staging` and `production` environment inventories.
  - Record Firebase project IDs, Hosting URLs, LiveKit projects, egress buckets, Gemini access, and owners.
  - Store credentials in managed secrets, not source files or developer machines.

**Done when:** a new contributor can set up the app from the README, every planned feature is accurately labelled, and staging is clearly separate from production.

---

## Phase 1 — Close security and reliability blockers

**Goal:** Ensure users can access only meetings they are allowed to join, and ensure failures are recoverable.

### 1.1 Lock down meeting callables (P0)

- [x] Update `getLivekitToken` to authorize the caller before minting a token.
  - Group meetings allow only existing participants or group members.
  - Direct meetings remain signed-in, link-based invites; newly generated meeting IDs have 96 random bits and must already exist in Firestore.
  - Do not add a caller to `participantIds` until authorization succeeds.
- [ ] Add expiring/revocable invite tokens for direct meetings if stronger invite control is needed beyond an unguessable bearer link.
- [x] Update `stopMeetingEgress` so only the organizer/host or a group admin can stop a recording.
- [x] Add automated authorization-policy tests for unauthorized join, authorized join, unauthorized stop, and authorized stop.
- [ ] Add Firebase Emulator integration tests that invoke the deployed callable wrappers, not just the shared policy.
- [ ] Test with two accounts: a participant, a group member, and an unrelated signed-in user.

**Done when:** an unrelated authenticated user cannot join, read, or stop a known meeting.

### 1.2 Make configuration fail closed (P0)

- [x] Remove development fallback values for `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, and `GEMINI_API_KEY`.
- [x] Validate required environment variables during function startup/deploy and return a clear configuration error if missing.
- [x] Bind sensitive configuration to Firebase/Google Cloud secret management in the Cloud Functions definitions.
- [ ] Enter the existing real values into Firebase Secret Manager before the next production deploy.
  - Run `firebase functions:secrets:set <NAME>` for `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `GEMINI_API_KEY`, `LIVEKIT_HOST`, `EGRESS_BUCKET`, and `GCP_EGRESS_CREDENTIALS`.
  - Deploy the Functions afterward so the declared secret bindings take effect.
  - Exact commands are retained in `HANDOFF.md`; never paste the values into chat, source files, or git.
- [ ] Rotate any secret that may previously have been copied into an unsafe place.
- [ ] Restrict GCP IAM: only the deployment service account and necessary operators should access recordings, secrets, and production data.

**Done when:** a deploy with missing secrets fails safely, and no real secret appears in Git history, client code, or logs.

### 1.3 Decide and enforce recording capacity (P0)

- [x] Choose one approach before multi-user beta: record mixed audio only during beta.
  - Keep `ENABLE_SPEAKER_TRACKS=false`; re-enable it only after a LiveKit capacity/cost review.
- [ ] Add a clear user-facing error if recording capacity is unavailable.
- [ ] Load-test the chosen setup with the expected number of simultaneous meetings.
- [ ] Document expected cost per meeting and an alert threshold.

**Done when:** the beta's maximum concurrent usage has a tested capacity and cost model.

### 1.4 Make summary processing recoverable

- [x] Store clear meeting processing states: `recording`, `processing`, `ready`, and `failed`.
- [x] Show the in-progress and failure states in the meeting UI.
- [ ] Add the `retrying` state as part of the retry implementation.
- [ ] Add an authorized “Retry summary” action for recoverable failures.
- [ ] Add a bounded server-side retry policy for temporary upload/Gemini failures.
- [ ] Keep audio until a successful thread is written; delete it afterwards according to a documented retention policy.
- [ ] Verify a failed Gemini response, missing webhook, and duplicate webhook all reach a safe final state.

**Done when:** a tester never waits indefinitely wondering where their summary went.

---

## Phase 1.5 — Cost, abuse, and consent (production blockers the rest of the plan under-weights)

**Goal:** Convene records people and pays a third party (LiveKit + Gemini + GCS) per meeting. Before real users — especially strangers — you must control what each meeting costs you, stop anyone from running up that bill, and be honest and lawful about the recording. These are not beta niceties; they are what separates "beta-ready" from "safe to open to the public."

### 1.5.1 Unit economics and budget safety (P0 before public launch)

- [ ] Write down the real cost of one meeting: LiveKit egress minutes + Gemini tokens (audio in, summary out) + GCS storage/egress + Functions/Firestore. Use actual numbers from a few real meetings. *(Operational — needs real usage data.)*
- [ ] Decide the sustainable model: is a meeting free, capped, or paid? What is the most a single user can cost you per day/month? *(Business decision.)*
- [x] **Budget kill-switch implemented in code:** `config/system.pauseNewMeetings` (set from the Firebase console) makes `getLivekitToken` turn away new joins with a clear "temporarily paused" message. See `functions/src/limits.ts`. *(Still TODO operationally: wire Google Cloud budget alerts to flip this flag automatically.)*
- [ ] Alert on cost anomalies (sudden spike in meetings, egress minutes, or Gemini calls). *(Operational — Cloud Monitoring.)*

**Done when:** you know your cost per meeting, the worst case a single user can cost you is bounded, and runaway spend trips an alert and a stop — not a surprise invoice.

### 1.5.2 Abuse prevention and quotas (P0 before public launch)

- [x] **Per-user daily meeting quota implemented and enforced server-side** in `getLivekitToken` (`assertWithinDailyQuota`, default 25 distinct meetings/user/day, `DAILY_MEETING_LIMIT` overridable). A single client can no longer spin up unlimited recordings.
- [ ] Reject or queue meeting creation beyond the concurrency capacity chosen in 1.3, with a clear error. *(Depends on the capacity decision.)*
- [ ] Consider App Check (Firebase) so only your real app can call the Functions, cutting off scripted abuse. *(Operational — console + provider setup.)*
- [ ] Log and be able to disable an individual abusive account quickly. *(The kill-switch is global; per-user disable is still TODO.)*

**Done when:** a single malicious or buggy client cannot exhaust capacity or budget for everyone else.

### 1.5.3 Recording consent and legal basics (P0 before external users)

- [x] **Consent shown before recording:** pre-join screen carries a recording/AI-processing notice above Join (joining = consent); the in-person recording flow is gated behind a full consent screen with an "everyone here agreed" checkbox before anything connects. See `lib/widgets/recording_consent.dart`.
- [ ] Decide and document the jurisdiction stance: several US states require all-party consent to record, and the EU (GDPR) treats this as processing personal data. Know which users you will and won't accept until you can comply. *(Legal/business decision.)*
- [x] **Data flow disclosed:** the Privacy Policy text now names the recording → GCS → Google Gemini → summary flow, audio deletion, and the 30-day transcript TTL, in the consent notice and Settings.
- [ ] Publish a real (hosted, lawyer-reviewed) privacy policy. *(The in-app text is a placeholder for testing.)*
- [x] **Support/deletion contact added** in Settings ("Contact & data requests"); account deletion already exists. *(Replace the placeholder email before public launch.)*

**Done when:** every recorded participant is clearly informed and consents, the data flow is disclosed, and you can honor a deletion request.

### 1.5.4 Early observability (do this at the start of beta, not after)

- [x] **Summary metrics instrumented:** the webhook emits a structured `metric:"summary"` log line on every success and failure with `status`, `durationMs` (time-to-summary), `usedSpeakerTracks`, and error — query in Cloud Logging on `jsonPayload.metric="summary"` for success rate and latency.
- [ ] Add error reporting (Crashlytics/Sentry) and a minimal ops dashboard before the first external tester joins. *(Operational — package + console setup.)*

**Done when:** you can answer "how many summaries succeeded, how fast, and what did they cost" for any day of the beta without guessing.

> **Implementation status:** the code pieces above (kill-switch, quota, consent gate, disclosure, metrics) are written and pass local build/lint/analyze, but ship with the **next functions/hosting deploy** — which is blocked on migrating secrets to Firebase Secret Manager (roadmap 1.2). Set the kill-switch by creating a Firestore doc `config/system` with `{ pauseNewMeetings: true, pauseMessage: "..." }` from the console.

---

## Phase 2 — Simplify the core experience

**Goal:** Make Convene feel as easy to enter as a familiar meeting app, while keeping its cross-meeting context advantage.

> **Status (code-complete, not yet deployed):** The simplification work below is implemented and passes `flutter analyze`, but ships with the next deploy, which is held on the Secret Manager migration (1.2). Items still marked `[ ]` need backend/data-model work or on-device verification, noted inline.

### Product principle

The first question on every screen should be obvious:

- Home: **What do I need to join or catch up on?**
- Meeting: **Can I join and participate immediately?**
- Thread: **What changed and what should I do?**

### 2.1 Simplify the home screen

- [x] Make the primary action a single prominent **New meeting** button.
  - First choice: `Start now` or `Schedule` (with `Record in-person` as a third option in the sheet).
  - Advanced choices stay behind the second step (the schedule sheet), not the dashboard.
- [x] Put `Join with link` beside the primary action, not inside a crowded form.
- [x] Limit the default home view to three sections:
  1. **Next up** — one next meeting and a join button.
  2. **Needs your attention** — pending invites + your assigned open actions.
  3. **Recent topics** — 3–5 context threads with `See all`.
- [x] Use progressive disclosure for the 30-day calendar.
  - Compact horizontal **7-day date strip** near the top; selecting a day filters `Next up`.
  - Discoverable collapsed row `Calendar · <month>  ⌄` expands an inline month calendar.
  - Selected date is remembered while the dashboard is open and shared by strip + calendar.
- [x] Move past meetings, filters, calendar, and complete history behind an `All meetings` disclosure row.
- [~] Plain labels: `Topics` renamed in nav + screens. `Teams`/`Profile` renames deferred (touch group/settings terminology app-wide).

**Acceptance test:** a first-time user can start or join a meeting in under 10 seconds without reading help text, and can find the full calendar from the clearly labelled collapsed calendar row.

### 2.2 Reduce pre-join friction

- [x] Keep camera/microphone preview, but make it visually secondary to the large **Join now** button (compact mic/cam toggles now overlay the preview).
- [x] Autofill the user's name; the field only unfolds when missing or the user taps `Edit`.
- [x] Collapse device selectors under `Device settings` (an expansion tile below the fold).
- [x] Clearly show permission failures with a one-step fix: `Allow microphone`, `Allow camera`, or `Continue anyway`.
- [x] Preserve the invite destination through login, then return directly to this screen (router already round-trips `?redirect=`).

**Acceptance test:** users who have granted permissions need one click from an invite link to join.

### 2.3 Make the in-meeting interface calm

- [x] Use a compact floating control bar with only: mic, camera, share, `More`, and Leave.
- [x] Put chat, participants, reactions, layout, invite link, and recording status inside the `More` menu (desktop keeps chat as an optional side panel).
- [x] Make `Leave` visually distinct but not alarmingly dominant; confirmation is asked only when you're the last participant (recording would stop for everyone).
- [x] Show a small persistent recording indicator with plain text `Recording for summary` (app bar + More menu).
- [x] Adaptive layout: full frame for one, split for two, grid for more; speaker view stays an optional switch.
- [x] Empty-room state with one direct action: `Copy invite link`.
- [ ] Verify all controls on a narrow Android viewport and desktop browser — **pending on-device/browser check** (layout is `LayoutBuilder`-responsive; not yet manually run).

**Acceptance test:** a user recognizes the basic controls without onboarding and can find chat/invite in one tap.

### 2.4 Turn threads into the product's “aha” moment

- [x] Rename/describe Threads in the UI as **Topics** (nav tab, list screen, empty states); technical `threads` model retained internally.
- [x] At the top of every topic show a **Topic overview** card:
  - one-sentence current status (distilled from the summary block);
  - latest decisions;
  - key points (stands in for “open questions” — the summary model has no distinct question type yet);
  - action items assigned to the current user.
- [x] Add a `What changed` banner (new summary / corrections / new comments since your last visit), tracked per-topic via `shared_preferences`.
- [x] Link each decision/action back to its source meeting and date (overview shows `From <meeting> · <date>`; one topic == one meeting today).
- [x] Lightweight “Edit/correct summary” workflow with a persistent `Edited by X · <date>` marker (new `editedBy`/`editedAt` on `SmartBlock`).
- [ ] Attach a meeting to an existing topic at scheduling time and after — **deferred to Phase 3** (explicit meeting-to-topic association is a Phase 3 item; needs data-model work).

**Acceptance test:** someone who missed three meetings can understand the current decision state in under two minutes.

---

## Phase 3 — Finish the essential beta features

**Goal:** Support the real workflow: several teams discussing the same topic, both online and in person.

> **Status (code-complete, not yet deployed):** Implemented and passing `flutter analyze` + functions build/lint. Server-side pieces (summary prompt, notifications, topic-append) only take effect after the next deploy (held on the Secret Manager migration, 1.2). Items marked `[ ]` need your input (VAPID key) or ops (hosted policy).

- [x] Implement in-person attendee context for AI summaries.
  - [x] Pass the meeting's attendee/roster names into the offline prompt as a prior for speaker attribution (`webhook.ts`).
  - [x] Let the meeting owner correct speaker names after processing — a "Fix speaker names" tool on a topic remaps every `Speaker N` to a real name across all blocks, stamped as an edit.
- [x] Add an explicit meeting-to-topic association.
  - [x] A meeting can create a new topic or attach to an existing one (`Add to existing topic` in the schedule sheet → `meeting.topicId`; the summary pipeline appends the session to that topic with a divider block).
  - [x] A topic never requires a group.
- [~] Notification center around useful events only.
  - [x] New meeting invite (existing).
  - [x] Summary ready (`summary_ready`, emitted to participants when a summary generates).
  - [x] You were assigned an action (`action_assigned`, matched from structured action-item blocks).
  - [ ] A decision changed in a followed topic — **deferred** (no "follow"/decision-diff concept yet).
- [ ] Complete FCM only if it is part of the beta promise.
  - [ ] Add the web VAPID key — **needs you** (`kWebPushVapidKey` in `push_notification_service.dart`).
  - [ ] Test permission denied, Android foreground/background/closed, token cleanup — **needs devices**.
  - Defer iOS push until APNs setup is complete.
- [x] Add a feedback entry point in Settings and after a summary is viewed.
  - "Was this summary accurate?" (Yes/No + "what was missing?") on each topic, plus "Send feedback" in Settings; writes to a write-only `feedback` collection (new Firestore rule).
- [x] Add a clear recording/AI-processing consent notice before a recording begins (shipped in Phase 1.5).
- [~] Publish a privacy policy, retention explanation, and support contact before external testing — in-app copy is done (Phase 1.5); a **hosted** policy page is still ops.

**Structured-summary upgrade (bonus):** the summary prompt now emits one block per decision/action item with a per-item `assignee`, so the home "My Tasks", the topic "Your action items", and action-assigned notifications actually populate (previously the AI returned one lumped bullet block and assignees were never set).

**Done when:** the beta workflow works without asking testers to use a separate notes document.

---

## Phase 4 — Build a real test and release pipeline

**Goal:** Make every release repeatable and safe.

### 4.1 Automated checks

- [ ] Replace the dummy Flutter test with unit/widget tests for:
  - meeting model parsing;
  - routing and login redirect/deep links;
  - RSVP/action completion permissions and UI states;
  - error, empty, and loading states.
- [ ] Add Cloud Function tests using Firebase emulators or mocked Admin SDK services.
- [x] Add an ESLint configuration or replace the broken lint command with the chosen TypeScript lint setup.
- [ ] Run and require:
  - `dart format --set-exit-if-changed .`
  - `flutter analyze`
  - `flutter test`
  - Functions build, lint, and tests.
- [ ] Add GitHub Actions to run these checks on each pull request.

### 4.2 Device and end-to-end test matrix

- [ ] Test Chrome desktop, Android Chrome, and Android native app for every beta build.
- [ ] Test two-account calls across each supported platform combination.
- [ ] Test permissions denied/re-enabled, bad network, reconnect, leaving/rejoining, and expired/deep links.
- [ ] Test recording and summary generation for a 1-person, 2-person, and group meeting.
- [ ] Test access boundaries with an unrelated signed-in account.
- [ ] Test summary failure and retry.
- [ ] Add Firebase Crashlytics/error reporting and an operational log dashboard before beta.

### 4.3 Staging deployment

- [ ] Create a staging Firebase Hosting URL and Android application ID/flavor if practical.
- [ ] Configure staging Cloud Functions, Firestore rules, indexes, egress bucket, and LiveKit webhook.
- [ ] Deploy rules and functions before the app that depends on them.
- [ ] Run the full device matrix against staging.
- [ ] Tag the tested commit and update the build stamp.

**Done when:** a tagged commit can be rebuilt, tested, and promoted without manual source edits.

---

## Phase 5 — Controlled user beta

**Goal:** Validate the core value before broad launch.

- [ ] Recruit 10–20 testers from one or two cross-functional projects.
- [ ] Give them one concrete use case: keep decisions for a shared project/topic in Convene for two weeks.
- [ ] Provide a short onboarding message:
  - Start/join meetings normally.
  - Attach them to the project topic.
  - Review and correct the generated summary.
- [ ] Track these measures weekly:
  - meetings recorded;
  - summaries successfully generated;
  - time to summary;
  - summaries viewed;
  - decisions/actions corrected;
  - return usage after the first week;
  - qualitative “would you miss this?” feedback.
- [ ] Hold two feedback reviews: after the first three meetings and at the end of week two.
- [ ] Fix the three highest-frequency friction points before expanding access.

**Success signal:** people use Convene to answer “what did we decide?” instead of searching chat, recordings, or asking another person.

---

## Phase 6 — Production deployment

**Goal:** Ship a reliable, supportable web and Android release.

- [ ] Confirm production LiveKit capacity, Gemini quota/billing, Firebase billing budgets, and alerts.
- [ ] Confirm production secrets and least-privilege IAM.
- [ ] Deploy and verify Firestore rules/indexes, Functions, and Hosting.
- [ ] Build a signed Android release; verify Google sign-in SHA fingerprints and App Links.
- [ ] Run a production smoke test with two internal accounts.
- [ ] Confirm analytics/error reporting and an escalation owner.
- [ ] Publish release notes, support channel, privacy policy, and known limitations.
- [ ] Roll out gradually; monitor summaries, errors, costs, and user feedback daily for the first week.

**Done when:** the team can identify a bad release, diagnose it, and either fix or roll it back quickly.

---

## Later / deliberately deferred

- [ ] iOS release after native permissions, Universal Links, APNs, signing, and real-device QA are complete.
- [ ] Better offline speaker attribution / voiceprint work only after consent, privacy, and accuracy requirements are defined.
- [ ] Video recording playback.
- [ ] Mobile-browser screen sharing (not broadly supported by browsers; do not promise it).
- [ ] Richer AI customization such as vocabulary and detail levels, after the basic summary is trusted.
- [ ] App-layer encryption only if the product can support it without preventing the server-side AI workflow.

## Recommended immediate next five tasks

1. Secure `getLivekitToken` and `stopMeetingEgress` with explicit authorization tests.
2. Decide LiveKit recording capacity for the beta.
3. Create staging and run a two-account end-to-end call/summary test.
4. Simplify the home and pre-join flows around `Start`, `Schedule`, and `Join`.
5. Replace the dummy tests, fix Functions linting, and add CI.
