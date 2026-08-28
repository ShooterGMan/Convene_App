import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';

void main() {
  group('Meeting Model Tests', () {
    final sampleUser = AppUser(id: 'u1', name: 'Alice Smith', email: 'alice@example.com');
    final sampleUser2 = AppUser(id: 'u2', name: 'Bob Jones', email: 'bob@example.com');

    test('serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final startTime = now.add(const Duration(minutes: 30));
      final endTime = startTime.add(const Duration(hours: 1));

      final meeting = Meeting(
        id: 'meet_123',
        title: 'Sprint Planning',
        startTime: startTime,
        endTime: endTime,
        type: MeetingType.meet,
        participants: [sampleUser, sampleUser2],
        location: 'Room 402',
        groupId: 'grp_1',
        topicId: 'topic_1',
        threadId: 'thread_1',
        summaryStatus: 'ready',
        guestEmails: ['guest@example.com'],
        isImportant: true,
        isInstant: false,
        rsvps: {
          'u1': 'yes',
          'u2': 'maybe',
        },
      );

      final json = meeting.toJson();
      expect(json['id'], 'meet_123');
      expect(json['title'], 'Sprint Planning');
      expect(json['type'], 'meet');
      expect(json['participantIds'], ['u1', 'u2']);
      expect(json['location'], 'Room 402');
      expect(json['groupId'], 'grp_1');
      expect(json['topicId'], 'topic_1');
      expect(json['threadId'], 'thread_1');
      expect(json['summaryStatus'], 'ready');
      expect(json['guestEmails'], ['guest@example.com']);
      expect(json['isImportant'], true);
      expect(json['isInstant'], false);
      expect(json['rsvps'], {'u1': 'yes', 'u2': 'maybe'});

      final fromJson = Meeting.fromJson(json);
      expect(fromJson.id, meeting.id);
      expect(fromJson.title, meeting.title);
      expect(fromJson.type, MeetingType.meet);
      expect(fromJson.participants.length, 2);
      expect(fromJson.participants.first.id, 'u1');
      expect(fromJson.location, 'Room 402');
      expect(fromJson.isImportant, true);
      expect(fromJson.rsvps['u1'], 'yes');
      expect(fromJson.rsvps['u2'], 'maybe');
    });

    test('typeLabel and typeIcon behavior', () {
      final meet = Meeting(
        id: '1',
        title: 'Video',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        type: MeetingType.meet,
        participants: [],
      );
      expect(meet.typeLabel, 'Meet');
      expect(meet.typeIcon, 'videocam');

      final room = Meeting(
        id: '2',
        title: 'Room',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        type: MeetingType.room,
        location: 'Conference Room B',
        participants: [],
      );
      expect(room.typeLabel, 'Conference Room B');
      expect(room.typeIcon, 'domain');

      final audio = Meeting(
        id: '3',
        title: 'Audio',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        type: MeetingType.audio,
        participants: [],
      );
      expect(audio.typeLabel, 'Audio');
      expect(audio.typeIcon, 'call');
    });

    test('RSVP status calculations', () {
      final meeting = Meeting(
        id: 'm1',
        title: 'Review',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        type: MeetingType.meet,
        participants: [sampleUser],
        rsvps: {
          'u1': 'yes',
          'u2': 'no',
          'u3': 'maybe',
          'u4': 'yes',
        },
      );

      expect(meeting.rsvpFor('u1'), RsvpStatus.yes);
      expect(meeting.rsvpFor('u2'), RsvpStatus.no);
      expect(meeting.rsvpFor('u3'), RsvpStatus.maybe);
      expect(meeting.rsvpFor('unknown_user'), isNull);

      expect(meeting.yesCount, 2);
      expect(meeting.noCount, 1);
      expect(meeting.maybeCount, 1);
    });

    test('isPast calculation based on time and summary status', () {
      final pastTimeMeeting = Meeting(
        id: 'm_past',
        title: 'Yesterday Meeting',
        startTime: DateTime.now().subtract(const Duration(hours: 3)),
        endTime: DateTime.now().subtract(const Duration(hours: 2)),
        type: MeetingType.meet,
        participants: [],
      );
      expect(pastTimeMeeting.isPast, true);

      final futureMeeting = Meeting(
        id: 'm_future',
        title: 'Tomorrow Meeting',
        startTime: DateTime.now().add(const Duration(days: 1)),
        endTime: DateTime.now().add(const Duration(days: 1, hours: 1)),
        type: MeetingType.meet,
        participants: [],
      );
      expect(futureMeeting.isPast, false);

      final futureMeetingWithSummary = Meeting(
        id: 'm_summarized',
        title: 'Early Summarized Meeting',
        startTime: DateTime.now().add(const Duration(hours: 2)),
        endTime: DateTime.now().add(const Duration(hours: 3)),
        type: MeetingType.meet,
        participants: [],
        threadId: 'thread_xyz',
      );
      expect(futureMeetingWithSummary.isPast, true);
    });

    test('isLive calculation', () {
      final liveMeeting = Meeting(
        id: 'm_live',
        title: 'Live Now',
        startTime: DateTime.now().subtract(const Duration(minutes: 10)),
        endTime: DateTime.now().add(const Duration(minutes: 50)),
        type: MeetingType.meet,
        participants: [],
      );
      expect(liveMeeting.isLive, true);

      final instantMeeting = Meeting(
        id: 'm_instant',
        title: 'Instant Meeting',
        startTime: DateTime.now().add(const Duration(hours: 5)),
        endTime: DateTime.now().add(const Duration(hours: 6)),
        type: MeetingType.meet,
        participants: [],
        isInstant: true,
      );
      expect(instantMeeting.isLive, true);

      final futureMeeting = Meeting(
        id: 'm_future',
        title: 'Later Today',
        startTime: DateTime.now().add(const Duration(hours: 2)),
        endTime: DateTime.now().add(const Duration(hours: 3)),
        type: MeetingType.meet,
        participants: [],
      );
      expect(futureMeeting.isLive, false);
    });
  });
}
