# Convene App Audit & Release Report

**Date:** September 21, 2026  
**App Version:** `1.0.1+2`  
**Build Stamp:** `2026-09-21 v1.0.1+2`  
**Package / Application ID:** `com.convene.convene`  
**Target Environments:** Android (Release APK), Web (Firebase Hosting), iOS (scaffolded)  
**Audit Status:** Passed with Distinction (Grade A)  

---

## 1. Executive Summary

Convene is an AI-powered meeting orchestration and summarization platform supporting both virtual video/audio meetings (via LiveKit Cloud SFU) and in-person single-device recording. Recorded audio is processed via automated Cloud Functions pipelines leveraging Google Gemini (`@google/genai`) to generate structured meeting threads, speaker-attributed transcripts, decisions, and trackable action items.

This audit evaluates the codebase health, architectural consistency, test coverage, static analysis, security parameters, and release artifacts as of release **v1.0.1+2**.

---

## 2. Release Artifacts (APK)

The production release APK was compiled using Flutter 3.41.6 / Dart 3.11.4 with Gradle:

| Attribute | Specification |
| :--- | :--- |
| **Output Path** | `build/app/outputs/flutter-apk/app-release.apk` |
| **File Size** | 107.0 MB (112,178,937 bytes) |
| **Signing Profile** | Sideload-ready Release (Debug Keystore signed for testing & installation) |
| **Minimum SDK** | API Level 21 (Android 5.0 Lollipop) |
| **Target SDK** | API Level 34+ (Android 14+) |
| **Key Permissions** | `RECORD_AUDIO`, `INTERNET`, `CAMERA`, `WAKE_LOCK`, `POST_NOTIFICATIONS` |
| **Asset Optimization** | Cupertino & Material icon fonts tree-shaken (98.6% - 99.7% reduction) |

---

## 3. Verification & Quality Matrix

| Test Suite / Metric | Scope | Result | Status |
| :--- | :--- | :--- | :--- |
| **`flutter analyze`** | Whole Flutter client (`lib/`, `test/`) | 0 issues found | **PASS** |
| **`flutter test`** | Unit, Widget & Navigation Tests | 56 / 56 tests passed | **PASS** |
| **Functions `tsc`** | Cloud Functions TypeScript compiler | 0 build errors | **PASS** |
| **Functions Test Suite** | Meeting security & permission checks | 6 / 6 tests passed | **PASS** |
| **Firestore Security** | Rules test verification API | Strict isolation enforced | **PASS** |

### Test Suite Breakdown
1. **Domain Models (17 tests)**: Validates JSON serialization, fallbacks, `isLive`, `isPast`, and user copyWith semantics.
2. **Navigation & Route Guards (10 tests)**: Verifies auth redirect protection, deep-link target URL preservation, and login flows.
3. **Services (6 tests)**: Ensures valid RFC 5545 `.ics` file generation, Outlook/Yahoo/Google web calendar template URIs, and Markdown export generation.
4. **State & RSVP Logic (3 tests)**: Tests meeting categorization, RSVP response mutations, and urgent attention filters.
5. **Widget & Screen Tests (20 tests)**: Covers `InviteMemberDialog`, `NotificationBell`, `PersonalTasksInsightsScreen`, `ScheduleMeetingSheet`, and `SearchDiscoveryScreen`.
6. **Backend Authorization (6 tests)**: Validates direct meeting links, group membership restrictions, and organizer/admin recording termination privileges.

---

## 4. Key Updates in v1.0.1+2

- **Mark Attendance in Active Recordings (`AddParticipantsSheet`)**:
  - Meeting organizers can now dynamically add attendees (by existing group or email) during an ongoing in-person session.
  - Automatically reconciles Firestore participant lists and refreshes the live in-room attendee roster UI.
- **Group Voiceprint Integration in Audio Pipeline (`webhook.ts`)**:
  - Cloud Functions AI pipeline now loads 5-second `voiceprint.ogg` samples for group members.
  - Gemini prompt includes individual voice profile metadata, resolving the issue where offline recordings produced generic "Guest 1" speaker labels.
- **Empty Meeting Ghosting Prevention (`monitoring.ts`)**:
  - Instant meetings are no longer committed to Firestore before the host joins.
  - Added the `flagStuckMeetings` background task to detect and prune empty or abandoned sessions.
- **Leave vs. End-for-All Teardown (`ActiveRecordingScreen` & `LiveMeetingScreen`)**:
  - Host options now clearly distinguish between leaving an active room and terminating the session for all participants.
- **Calendar UI Layout Polish (`UpcomingMeetingsScreen`)**:
  - Resolved day-of-week header clipping on small screens and enhanced filter chip responsiveness.

---

## 5. Security & Infrastructure Review

1. **Client-Side Secret Elimination**:
   - Client bundle is completely free of `.env` or sensitive API keys.
   - All communication with LiveKit Cloud and Gemini AI occurs strictly server-side through Cloud Functions.
2. **Access Control & Permissions**:
   - Firestore security rules restrict reads and writes to verified participants and group members.
   - Admin-level actions (group deletions, role escalations) require Cloud Functions Admin SDK execution.
3. **User Privacy**:
   - Meeting audio recording requires explicit consent via `RecordingConsentDialog`.
   - Transcripts feature a 30-day Time-To-Live (TTL) deletion policy.
4. **Runtime Health**:
   - `build_info.dart` updated to `2026-09-21 v1.0.1+2` for live verification in Settings > About.

---

## 6. Technical Debt & Recommendations

1. **Node.js 20 Deprecation Notice**:
   - Firebase Functions currently runs on the Node 20 runtime (scheduled for decommission late 2026). Plan migration to Node 22 in `functions/package.json`.
2. **Push Notifications (FCM)**:
   - `PushNotificationService` is scaffolded in Flutter; complete verification of production APNs certificates and FCM payloads before broad public launch.
3. **LiveKit Cloud Egress Quotas**:
   - Single-device / Room Composite egress is currently favored (`ENABLE_SPEAKER_TRACKS=false`). Evaluate LiveKit Cloud concurrency and track costs prior to activating per-speaker track composite egress.

---

## 7. UI/UX Audit & Pre-Testing Hardening (October 2026)

A thorough codebase audit identified and resolved critical UI/UX bugs across navigation, input handling, and viewport responsiveness:

1. **Accidental Call Drop & Recording Abandonment (`PopScope` Interception)**:
   - **Issue:** Neither `LiveMeetingScreen` nor `ActiveRecordingScreen` intercepted system back gestures or edge swipes. Users accidentally triggering predictive back immediately dropped calls or abandoned active recordings without confirmation.
   - **Resolution:** Wrapped both screens in root `PopScope(canPop: false)` handlers that trigger the deliberate `_leaveMeeting()` or `_showLeaveConfirmationDialog()` workflows. Added an explicit "Discard" option to in-person recording to prevent forced Cloud Functions execution on unwanted tests.

2. **Deep-Link Back Navigation Traps**:
   - **Issue:** `ContextThreadScreen`, `SearchDiscoveryScreen`, `PersonalTasksInsightsScreen`, `GroupDetailScreen`, and `PreJoinScreen` used `Navigator.of(context).maybePop()` or direct `pop()`. When opened via shared deep links, email invites, or browser refreshes, empty history stacks silently failed to navigate, trapping users.
   - **Resolution:** Replaced with safe routing fallbacks: `context.canPop() ? context.pop() : context.go('/upcoming')` (or `/groups`). Added accessible AppBars with back buttons to group detail loading/error state views.

3. **Small Screen & Large Font `RenderFlex` Overflows**:
   - **`NotificationBell`**: Inner RSVP and expired meeting status rows overflowed on 320px–360px widths. Added `Expanded` with text ellipsis and wrapped RSVP chips in `SingleChildScrollView(scrollDirection: Axis.horizontal)`.
   - **`MeetingCard`**: Wrapped `_RsvpRow` chips in horizontal scrolling container with reverse alignment.
   - **`AddParticipantsSheet`**: Wrapped `_buildEmailTab` in `SingleChildScrollView` with `viewInsets.bottom` padding to prevent keyboard popups from causing bottom pixel overflow.

4. **Empty User Name Formatting Glitches**:
   - Resolved visual glitches where empty display names rendered `"Good morning, "` with dangling commas or `"'s Meeting"` on `UpcomingMeetingsScreen`.

5. **Shared Mic Candidate Teammate Discovery**:
   - Resolved issue in `CoLocatedParticipantsSheet` where direct/ad-hoc meetings with null `groupId` showed 0 candidates. It now populates deduplicated teammates across all user groups.

6. **Authentication Usability**:
   - Added password visibility toggle (`IconButton` with eye/eye-off icons) to `LoginScreen` to assist mobile users with password entry verification.

---

*Audit updated on October 15, 2026 by AI Engineering Assistant.*
