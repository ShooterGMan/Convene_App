import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/meeting.dart';
import 'package:convene/models/user.dart';

void main() {
  group('Meeting Agenda & Carried-Over Tasks Model Tests', () {
    test('Meeting serializes and deserializes agenda and carried-over tasks', () {
      final meeting = Meeting(
        id: 'm123',
        title: 'Sprint Planning & Retrospective',
        startTime: DateTime(2026, 9, 1, 10, 0),
        endTime: DateTime(2026, 9, 1, 11, 0),
        type: MeetingType.meet,
        participants: const [
          AppUser(id: 'u1', email: 'alex@example.com', name: 'Alex Rivera'),
        ],
        agenda: const [
          '1. Sprint Goals Review',
          '2. Team Capacity Check',
          '3. Backlog Item Estimations',
        ],
        carriedOverTasks: const [
          'Fix authentication deep-link bug',
          'Update theme colors',
        ],
      );

      final json = meeting.toJson();
      expect(json['agenda'], isA<List>());
      expect((json['agenda'] as List).length, 3);
      expect((json['agenda'] as List).first, '1. Sprint Goals Review');
      expect(json['carriedOverTasks'], isA<List>());
      expect((json['carriedOverTasks'] as List).length, 2);

      final deserialized = Meeting.fromJson(json);
      expect(deserialized.agenda.length, 3);
      expect(deserialized.agenda[1], '2. Team Capacity Check');
      expect(deserialized.carriedOverTasks.length, 2);
      expect(deserialized.carriedOverTasks.first, 'Fix authentication deep-link bug');
    });

    test('Meeting copyWith safely updates agenda and carried-over tasks', () {
      final meeting = Meeting(
        id: 'm1',
        title: 'Daily Standup',
        startTime: DateTime(2026, 9, 1, 9, 0),
        endTime: DateTime(2026, 9, 1, 9, 15),
        type: MeetingType.meet,
        participants: const [],
      );

      expect(meeting.agenda, isEmpty);
      expect(meeting.carriedOverTasks, isEmpty);

      final updated = meeting.copyWith(
        agenda: ['Review blockers', 'Set priorities'],
        carriedOverTasks: ['Finish PR #12'],
      );

      expect(updated.agenda.length, 2);
      expect(updated.carriedOverTasks.length, 1);
      expect(updated.title, 'Daily Standup');
    });
  });
}
