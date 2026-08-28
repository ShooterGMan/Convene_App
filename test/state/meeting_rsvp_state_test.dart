import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';

void main() {
  group('Meeting and RSVP State Logic Tests', () {
    final selfUser = AppUser(id: 'self_123', name: 'Current User', email: 'me@example.com', isSelf: true);
    final otherUser = AppUser(id: 'other_456', name: 'Other User', email: 'other@example.com');

    final now = DateTime.now();

    test('separates live, upcoming, and past meetings correctly', () {
      final liveMeeting = Meeting(
        id: 'm_live',
        title: 'Live Standup',
        startTime: now.subtract(const Duration(minutes: 10)),
        endTime: now.add(const Duration(minutes: 20)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
      );

      final upcomingMeeting1 = Meeting(
        id: 'm_up1',
        title: 'Future Sync 1',
        startTime: now.add(const Duration(hours: 1)),
        endTime: now.add(const Duration(hours: 2)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
      );

      final upcomingMeeting2 = Meeting(
        id: 'm_up2',
        title: 'Future Sync 2',
        startTime: now.add(const Duration(hours: 4)),
        endTime: now.add(const Duration(hours: 5)),
        type: MeetingType.room,
        participants: [selfUser, otherUser],
      );

      final pastMeeting = Meeting(
        id: 'm_past',
        title: 'Old Meeting',
        startTime: now.subtract(const Duration(days: 1)),
        endTime: now.subtract(const Duration(days: 1, hours: -1)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
        summaryStatus: 'ready',
      );

      final allMeetings = [pastMeeting, upcomingMeeting2, liveMeeting, upcomingMeeting1];

      // Filter live
      final live = allMeetings.where((m) => m.isLive).toList();
      expect(live.length, 1);
      expect(live.first.id, 'm_live');

      // Filter upcoming (not past and not live)
      final upcoming = allMeetings.where((m) => !m.isPast && !m.isLive).toList();
      upcoming.sort((a, b) => a.startTime.compareTo(b.startTime));
      expect(upcoming.length, 2);
      expect(upcoming[0].id, 'm_up1');
      expect(upcoming[1].id, 'm_up2');

      // Filter past
      final past = allMeetings.where((m) => m.isPast).toList();
      expect(past.length, 1);
      expect(past.first.id, 'm_past');
    });

    test('identifies meetings needing RSVP attention for the current user', () {
      final unrespondedUpcoming = Meeting(
        id: 'm_unresp',
        title: 'Quarterly Planning',
        startTime: now.add(const Duration(days: 2)),
        endTime: now.add(const Duration(days: 2, hours: 1)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
        rsvps: {'other_456': 'yes'}, // self has not responded
      );

      final acceptedUpcoming = Meeting(
        id: 'm_accepted',
        title: '1-on-1',
        startTime: now.add(const Duration(days: 1)),
        endTime: now.add(const Duration(days: 1, hours: 1)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
        rsvps: {'self_123': 'yes'},
      );

      final unrespondedPast = Meeting(
        id: 'm_past',
        title: 'Past Unresponded',
        startTime: now.subtract(const Duration(days: 2)),
        endTime: now.subtract(const Duration(days: 2, hours: -1)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
        rsvps: {},
      );

      final list = [unrespondedUpcoming, acceptedUpcoming, unrespondedPast];

      // Needs attention: upcoming meeting where current user has no RSVP
      final needsAttention = list.where((m) => !m.isPast && m.rsvpFor(selfUser.id) == null).toList();
      expect(needsAttention.length, 1);
      expect(needsAttention.first.id, 'm_unresp');
    });

    test('updates RSVP state accurately on status change', () {
      var meeting = Meeting(
        id: 'm_test',
        title: 'Team Sync',
        startTime: now.add(const Duration(hours: 2)),
        endTime: now.add(const Duration(hours: 3)),
        type: MeetingType.meet,
        participants: [selfUser, otherUser],
        rsvps: const {},
      );

      expect(meeting.rsvpFor(selfUser.id), isNull);
      expect(meeting.yesCount, 0);

      // User votes Yes
      var updatedRsvps = Map<String, String>.from(meeting.rsvps)..[selfUser.id] = 'yes';
      meeting = Meeting.fromJson({...meeting.toJson(), 'rsvps': updatedRsvps});
      expect(meeting.rsvpFor(selfUser.id), RsvpStatus.yes);
      expect(meeting.yesCount, 1);

      // User changes vote to Maybe
      updatedRsvps = Map<String, String>.from(meeting.rsvps)..[selfUser.id] = 'maybe';
      meeting = Meeting.fromJson({...meeting.toJson(), 'rsvps': updatedRsvps});
      expect(meeting.rsvpFor(selfUser.id), RsvpStatus.maybe);
      expect(meeting.yesCount, 0);
      expect(meeting.maybeCount, 1);

      // User changes vote to No
      updatedRsvps = Map<String, String>.from(meeting.rsvps)..[selfUser.id] = 'no';
      meeting = Meeting.fromJson({...meeting.toJson(), 'rsvps': updatedRsvps});
      expect(meeting.rsvpFor(selfUser.id), RsvpStatus.no);
      expect(meeting.noCount, 1);
    });
  });
}
