# Changelog

All notable changes to this project will be documented in this file.

## [1.0.1+2] - 2026-09-21
### Added
- **Mark Attendance Sheet**: New UI in `ActiveRecordingScreen` to add participants to an in-person meeting by Group or Email.
- **Dynamic In-Room Roster**: The active attendees UI now dynamically updates when a participant is added during the recording.

### Fixed
- **In-Person Meeting Voiceprints**: Fixed a critical backend bug where the AI pipeline failed to load the 5-second `voiceprint.ogg` files for members of a linked group, which previously resulted in inaccurate diarization ("Guest 1").
- **Empty Meeting Ghosting**: Fixed an issue where instant meetings were being saved to the database immediately upon creation rather than upon joining. Also added a background cleanup task (`flagStuckMeetings`) to remove any leftover empty meetings.
- **End/Leave Meeting Logic**: Added separate "Leave" and "End for All" dialog options, allowing the creator to gracefully terminate the entire room for all participants.
- **Calendar UI**: Fixed clipping issues with the days-of-the-week header in the `UpcomingMeetingsScreen`.

## [1.0.0+1] - Initial Release
- Initial release featuring Google Calendar integration, AI transcription, and smart dashboard.
