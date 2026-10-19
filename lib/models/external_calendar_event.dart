class ExternalCalendarEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;

  const ExternalCalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
  });

  factory ExternalCalendarEvent.fromJson(Map<String, dynamic> json) {
    return ExternalCalendarEvent(
      id: json['id'] as String? ?? 'unknown',
      title: json['summary'] as String? ?? 'Busy',
      startTime: json['start']?['dateTime'] != null 
          ? DateTime.parse(json['start']['dateTime'])
          : json['start']?['date'] != null 
              ? DateTime.parse(json['start']['date'])
              : DateTime.now(),
      endTime: json['end']?['dateTime'] != null 
          ? DateTime.parse(json['end']['dateTime'])
          : json['end']?['date'] != null 
              ? DateTime.parse(json['end']['date'])
              : DateTime.now().add(const Duration(hours: 1)),
    );
  }
}
