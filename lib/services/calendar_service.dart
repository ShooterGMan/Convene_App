import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/auth_repository.dart';

final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService(ref.watch(authRepositoryProvider));
});

class CalendarService {
  final AuthRepository _authRepository;

  CalendarService(this._authRepository);

  /// Generates a standard Google Calendar web URL template (1-click add to Google Calendar)
  static String buildGoogleCalendarTemplateUrl({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) {
    final startIso = startTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first + 'Z';
    final endIso = endTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first + 'Z';
    final details = Uri.encodeComponent('Meeting scheduled via Convene.\n\nJoin Convene Meeting: $conveneUrl');
    final text = Uri.encodeComponent(title);
    final location = Uri.encodeComponent(conveneUrl);

    return 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$text&dates=$startIso/$endIso&details=$details&location=$location';
  }

  /// Opens Google Calendar in browser/app to add event
  Future<bool> launchGoogleCalendarTemplate({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) async {
    final urlStr = buildGoogleCalendarTemplateUrl(
      title: title,
      startTime: startTime,
      endTime: endTime,
      conveneUrl: conveneUrl,
    );
    final uri = Uri.parse(urlStr);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Creates a Google Calendar event with the Convene meeting link.
  /// Returns `true` if directly created via Google API, or `false` if template fallback was launched.
  Future<bool> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required List<String> guestEmails,
    required String conveneUrl,
  }) async {
    try {
      final token = await _authRepository.getGoogleAccessToken();
      if (token == null) {
        // Fall back to 1-click template URL launch
        await launchGoogleCalendarTemplate(
          title: title,
          startTime: startTime,
          endTime: endTime,
          conveneUrl: conveneUrl,
        );
        return false;
      }

      final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1');
      
      final attendees = guestEmails.map((email) => {'email': email}).toList();

      final body = {
        'summary': title,
        'description': 'Meeting scheduled via Convene.\n\nJoin Online: $conveneUrl',
        'location': conveneUrl,
        'start': {
          'dateTime': startTime.toUtc().toIso8601String(),
          'timeZone': 'UTC',
        },
        'end': {
          'dateTime': endTime.toUtc().toIso8601String(),
          'timeZone': 'UTC',
        },
        'attendees': attendees,
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
        return true;
      }

      debugPrint('Google Calendar API returned status ${response.statusCode}: ${response.body}');
      await launchGoogleCalendarTemplate(
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
      );
      return false;
    } catch (e) {
      debugPrint('Calendar API Exception: $e');
      await launchGoogleCalendarTemplate(
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
      );
      return false;
    }
  }
}
