# Convene: Feature List
*A living document tracking the capabilities of the Convene application.*

## Core Meeting Features (Custom Platform)
- **Live Video & Audio Grid**: Native WebRTC video conferencing powered by LiveKit.
- **Pre-Join Screen**: Test and configure camera/microphone before entering a room.
- **Screen Sharing**: Broadcast your screen to all participants in the room.
- **In-Meeting Text Chat**: Real-time messaging during the call using WebRTC Data Channels.
- **Shareable Invite Links**: Generate web links that allow guests outside the group to join meetings directly from their browser.
- **Local Recording Trigger**: Manual control for hosts to start the meeting recording and summary generation process.

## AI & Summarization (Gemini 3.0 Flash)
- **Automated Summaries**: Cloud Functions automatically process LiveKit meeting recordings (Egress) and generate summaries upon meeting completion.
- **Context Threads**: Summaries are categorized and saved into long-running context threads for groups.
- **Custom Vocabulary**: Option to provide jargon to the AI to ensure perfect transcriptions.
- **Speaker Attribution**: Summaries can identify and attribute quotes/actions to specific speakers.
- **Detail Levels**: Configurable AI summary detail (Concise, Detailed, Comprehensive).

## Infrastructure & Integrations
- **Google Calendar Sync**: Imports meetings from Google Calendar and pushes new scheduled meetings to it (embedding Convene invite links instead of Google Meet).
- **Serverless Backend**: Powered by Firebase Cloud Functions (zero-maintenance, autoscaling).

## Removed Features (Legacy)
- ~~**Google Meet Deep Integration**: The app no longer relies on Google Meet as its video provider.~~
- ~~**Headless Bot Recorders**: Removed the heavy Puppeteer/Playwright server bots used to join Google Meets and record screens.~~
- ~~**Meet URL Database Tracking**: Removed all database fields tracking external meeting URLs.~~

## Phase 2 Roadmap: UI/UX Polish & Future Upgrades

### UI/UX Meeting Polish
- **Dynamic Video Layouts**: The meeting grid currently forces a 2x2 square. We need dynamic scaling (Full screen for 1, split for 2, 3x3 for 5+ people).
- **True Active Speaker View**: Overhaul the Speaker View toggle so it actually watches LiveKit's audio levels and dynamically swaps the largest video tile to the current active speaker.
- **Floating Glassmorphic Controls**: Move the clunky bottom control bar into a sleek, floating island over the video grid to maximize screen real estate.
- **Participant Sidebar Panel**: Add a new tab next to "Chat" for "Participants", showing a list of everyone in the room and their live mic/camera status.
- **In-Tile Indicators**: Add persistent visual overlays on the video tiles (e.g., a red struck-through mic icon) so you know instantly if someone is talking while muted.
- **Mobile Responsive Polish**: Ensure all meeting controls and side panels stack beautifully on iOS/Android and smaller browser windows.

### Major Future Features
- **Server-Side Transcription (Google Chirp 3)**: Replace the client-side native dictation with a LiveKit Agent backend. This will allow flawless "Hinglish" transcription, multi-language auto-detection, and uniform accuracy across all devices. ** (OPTIONAL)
- **Smart Action Items**: Train Gemini to explicitly extract "To-Do" lists from the transcript and automatically assign them to specific team members in the Thread UI.
- **Hand Raising & Queue**: Add a persistent "Raise Hand" queue for larger team meetings.
- **Cloud Recording Playback**: Use LiveKit Egress to save an MP4 of the meeting so users can replay the video alongside the generated transcript.

### Tech Debt & Known Issues to Fix
- **Transcription Stability**: Build a more robust auto-reconnect loop in case a user's Bluetooth headphones disconnect mid-meeting and break the speech engine.
- **Firebase Mock Cleanup**: Purge any remaining legacy hardcoded/mock data from the Firestore schema from the early prototyping days.
