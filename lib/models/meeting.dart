import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

enum MeetingType { meet, room, audio }

enum RsvpStatus { yes, no, maybe }

class Meeting {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final MeetingType type;
  final List<AppUser> participants;
  final String? location; // Room name or null for virtual
  final String? groupId;
  final String? topicId; // if set, the summary appends to this existing topic
  final String? threadId; // non-null if meeting has a summary
  final String? summaryStatus; // recording | processing | ready | failed
  final String? summaryError; // non-null if summary generation failed/timed out
  final List<String> guestEmails;
  final bool isImportant;
  final bool isInstant;
  final Map<String, String> rsvps; // uid -> 'yes' | 'no' | 'maybe'
  final List<String> agenda; // Pre-meeting discussion topics
  final List<String> carriedOverTasks; // Unfinished action items from past meetings

  const Meeting({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.participants,
    this.location,
    this.groupId,
    this.topicId,
    this.threadId,
    this.summaryStatus,
    this.summaryError,
    this.guestEmails = const [],
    this.isImportant = false,
    this.isInstant = false,
    this.rsvps = const {},
    this.agenda = const [],
    this.carriedOverTasks = const [],
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as String? ?? 'unknown',
      title: json['title'] as String? ?? 'Untitled Meeting',
      startTime: json['startTime'] == null
          ? DateTime.now()
          : (json['startTime'] is Timestamp
              ? (json['startTime'] as Timestamp).toDate()
              : DateTime.parse(json['startTime'] as String)),
      endTime: json['endTime'] == null
          ? DateTime.now().add(const Duration(hours: 1))
          : (json['endTime'] is Timestamp
              ? (json['endTime'] as Timestamp).toDate()
              : DateTime.parse(json['endTime'] as String)),
      type: MeetingType.values.any((e) => e.name == json['type'])
          ? MeetingType.values.firstWhere((e) => e.name == json['type'])
          : MeetingType.meet,
      participants: (json['participants'] as List<dynamic>?)
              ?.map((e) => AppUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      location: json['location'] as String?,
      groupId: json['groupId'] as String?,
      topicId: json['topicId'] as String?,
      threadId: json['threadId'] as String?,
      summaryStatus: json['summaryStatus'] as String?,
      summaryError: json['summaryError'] as String?,
      guestEmails: (json['guestEmails'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isImportant: json['isImportant'] as bool? ?? false,
      isInstant: json['isInstant'] as bool? ?? false,
      rsvps: (json['rsvps'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as String)) ?? {},
      agenda: (json['agenda'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      carriedOverTasks: (json['carriedOverTasks'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
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
      // Flat list of participant UIDs, kept in sync with `participants` -
      // Firestore security rules key off this to check meeting access.
      'participantIds': participants.map((e) => e.id).toList(),
      'location': location,
      'groupId': groupId,
      'topicId': topicId,
      'threadId': threadId,
      'summaryStatus': summaryStatus,
      'guestEmails': guestEmails,
      'isImportant': isImportant,
      'isInstant': isInstant,
      'rsvps': rsvps,
      'agenda': agenda,
      'carriedOverTasks': carriedOverTasks,
    };
  }

  Meeting copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    MeetingType? type,
    List<AppUser>? participants,
    String? location,
    String? groupId,
    String? topicId,
    String? threadId,
    String? summaryStatus,
    String? summaryError,
    List<String>? guestEmails,
    bool? isImportant,
    bool? isInstant,
    Map<String, String>? rsvps,
    List<String>? agenda,
    List<String>? carriedOverTasks,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      type: type ?? this.type,
      participants: participants ?? this.participants,
      location: location ?? this.location,
      groupId: groupId ?? this.groupId,
      topicId: topicId ?? this.topicId,
      threadId: threadId ?? this.threadId,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      summaryError: summaryError ?? this.summaryError,
      guestEmails: guestEmails ?? this.guestEmails,
      isImportant: isImportant ?? this.isImportant,
      isInstant: isInstant ?? this.isInstant,
      rsvps: rsvps ?? this.rsvps,
      agenda: agenda ?? this.agenda,
      carriedOverTasks: carriedOverTasks ?? this.carriedOverTasks,
    );
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
    if (isPast) return false;
    final now = DateTime.now();
    if (isInstant) return true;
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// Whether this meeting has already ended.
  bool get isPast {
    if (threadId != null || summaryStatus == 'ready' || summaryStatus == 'failed') {
      return true;
    }
    if (isInstant) return false;
    return DateTime.now().isAfter(endTime);
  }

  RsvpStatus? rsvpFor(String uid) {
    switch (rsvps[uid]) {
      case 'yes':
        return RsvpStatus.yes;
      case 'no':
        return RsvpStatus.no;
      case 'maybe':
        return RsvpStatus.maybe;
      default:
        return null;
    }
  }

  int get yesCount => rsvps.values.where((v) => v == 'yes').length;
  int get noCount => rsvps.values.where((v) => v == 'no').length;
  int get maybeCount => rsvps.values.where((v) => v == 'maybe').length;
}
