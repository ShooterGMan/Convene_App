import 'user.dart';

enum MeetingType { meet, room, audio }

class Meeting {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final MeetingType type;
  final List<AppUser> participants;
  final String? location; // Room name or null for virtual
  final String? groupId;
  final String? threadId; // non-null if meeting has a summary
  final String? meetUrl;
  final List<String> guestEmails;

  const Meeting({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.participants,
    this.location,
    this.groupId,
    this.threadId,
    this.meetUrl,
    this.guestEmails = const [],
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as String,
      title: json['title'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      type: MeetingType.values.firstWhere((e) => e.name == json['type']),
      participants: (json['participants'] as List<dynamic>?)
              ?.map((e) => AppUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      location: json['location'] as String?,
      groupId: json['groupId'] as String?,
      threadId: json['threadId'] as String?,
      meetUrl: json['meetUrl'] as String?,
      guestEmails: (json['guestEmails'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'type': type.name,
      'participants': participants.map((e) => e.toJson()).toList(),
      'location': location,
      'groupId': groupId,
      'threadId': threadId,
      'meetUrl': meetUrl,
      'guestEmails': guestEmails,
    };
  }

  /// Returns human-readable meeting type label
  String get typeLabel {
    switch (type) {
      case MeetingType.meet:
        return 'Meet';
      case MeetingType.room:
        return location ?? 'In-Person';
      case MeetingType.audio:
        return 'Audio';
    }
  }

  /// Returns the icon data for the meeting type
  String get typeIcon {
    switch (type) {
      case MeetingType.meet:
        return 'videocam';
      case MeetingType.room:
        return 'domain';
      case MeetingType.audio:
        return 'call';
    }
  }

  /// Returns minutes until meeting starts, or null if already started/passed
  int? get minutesUntil {
    final now = DateTime.now();
    if (startTime.isAfter(now)) {
      return startTime.difference(now).inMinutes;
    }
    return null;
  }

  /// Whether the meeting is currently happening
  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }
}
