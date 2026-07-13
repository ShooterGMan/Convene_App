import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/auth_repository.dart';

final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService(ref.watch(authRepositoryProvider));
});

class CalendarService {
  final AuthRepository _authRepository;

  CalendarService(this._authRepository);

  /// Creates a Google Calendar event and returns the Google Meet link (hangoutLink)
  Future<String?> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required List<String> guestEmails,
  }) async {
    try {
      final token = await _authRepository.getGoogleAccessToken();
      if (token == null) {
        throw Exception('Google Access Token not available. Ensure you are signed in on a supported platform.');
      }

      final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1');
      
      final attendees = guestEmails.map((email) => {'email': email}).toList();

      final body = {
        'summary': title,
        'description': 'Meeting scheduled via Convene.',
        'start': {
          'dateTime': startTime.toUtc().toIso8601String(),
          'timeZone': 'UTC',
        },
        'end': {
          'dateTime': endTime.toUtc().toIso8601String(),
          'timeZone': 'UTC',
        },
        'attendees': attendees,
        'conferenceData': {
          'createRequest': {
            'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
            'conferenceSolutionKey': {
              'type': 'hangoutsMeet',
            },
          },
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['hangoutLink'] as String?;
      } else {
        throw Exception('Failed to create calendar event: ${response.body}');
      }
    } catch (e) {
      throw Exception('Calendar API Error: $e');
    }
  }
}
