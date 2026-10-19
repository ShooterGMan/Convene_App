import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/external_calendar_event.dart';
import '../models/meeting.dart';
import '../repositories/auth_repository.dart';
import '../theme/app_theme.dart';

final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService(ref.watch(authRepositoryProvider));
});

class CalendarService {
  final AuthRepository _authRepository;

  CalendarService(this._authRepository);

  Future<List<ExternalCalendarEvent>> fetchExternalEvents(DateTime start, DateTime end) async {
    try {
      final token = await _authRepository.getGoogleAccessToken();
      if (token == null) return [];

      final url = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events'
        '?timeMin=${start.toUtc().toIso8601String()}'
        '&timeMax=${end.toUtc().toIso8601String()}'
        '&singleEvents=true'
        '&orderBy=startTime',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>? ?? [];
        return items.map((e) => ExternalCalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
      }
      debugPrint('Failed to fetch calendar events: ${response.statusCode} ${response.body}');
      return [];
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
      return [];
    }
  }

  /// Generates a standard Google Calendar web URL template (1-click add to Google Calendar)
  static String buildGoogleCalendarTemplateUrl({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) {
    final startIso = '${startTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final endIso = '${endTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final details = Uri.encodeComponent('Meeting scheduled via Convene.\n\nJoin Convene Meeting: $conveneUrl');
    final text = Uri.encodeComponent(title);
    final location = Uri.encodeComponent(conveneUrl);

    return 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$text&dates=$startIso/$endIso&details=$details&location=$location';
  }

  /// Generates Microsoft Outlook / Office 365 Calendar web URL template
  static String buildOutlookCalendarTemplateUrl({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) {
    final startIso = Uri.encodeComponent(startTime.toUtc().toIso8601String());
    final endIso = Uri.encodeComponent(endTime.toUtc().toIso8601String());
    final body = Uri.encodeComponent('Meeting scheduled via Convene.\n\nJoin Convene Meeting: $conveneUrl');
    final subject = Uri.encodeComponent(title);
    final location = Uri.encodeComponent(conveneUrl);

    return 'https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent&subject=$subject&startdt=$startIso&enddt=$endIso&body=$body&location=$location';
  }

  /// Generates Yahoo Calendar web URL template
  static String buildYahooCalendarTemplateUrl({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) {
    final startIso = '${startTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final endIso = '${endTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final desc = Uri.encodeComponent('Meeting scheduled via Convene.\n\nJoin Convene Meeting: $conveneUrl');
    final text = Uri.encodeComponent(title);
    final loc = Uri.encodeComponent(conveneUrl);

    return 'https://calendar.yahoo.com/?v=60&title=$text&st=$startIso&et=$endIso&desc=$desc&in_loc=$loc';
  }

  /// Generates standard RFC 5545 iCalendar (`.ics`) file content
  static String generateIcsFileContent({
    required String meetingId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
    String? description,
    List<String> attendees = const [],
  }) {
    final nowUtc = '${DateTime.now().toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final startUtc = '${startTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final endUtc = '${endTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';

    final safeTitle = title.replaceAll('\n', ' ').replaceAll(';', ',');
    final safeDesc = (description ?? 'Meeting scheduled via Convene.\n\nJoin Convene Meeting: $conveneUrl')
        .replaceAll('\n', '\\n');

    final attendeeLines = attendees.map((email) => 'ATTENDEE;RSVP=TRUE:mailto:$email').join('\r\n');

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Convene//Meeting App//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      'UID:${meetingId}_convene@meeting-app-844aa.web.app',
      'DTSTAMP:$nowUtc',
      'DTSTART:$startUtc',
      'DTEND:$endUtc',
      'SUMMARY:$safeTitle',
      'DESCRIPTION:$safeDesc',
      'URL:$conveneUrl',
      'LOCATION:$conveneUrl',
      'STATUS:CONFIRMED',
      if (attendeeLines.isNotEmpty) attendeeLines,
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');
  }

  /// Downloads or exports an `.ics` calendar invite
  static Future<bool> downloadOrExportIcs({
    required String meetingId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) async {
    final icsContent = generateIcsFileContent(
      meetingId: meetingId,
      title: title,
      startTime: startTime,
      endTime: endTime,
      conveneUrl: conveneUrl,
    );

    final bytes = utf8.encode(icsContent);
    final base64String = base64Encode(bytes);
    final dataUri = Uri.parse('data:text/calendar;charset=utf8;base64,$base64String');

    if (await canLaunchUrl(dataUri)) {
      return await launchUrl(dataUri);
    }
    return false;
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

  /// Opens Outlook Calendar in browser/app to add event
  static Future<bool> launchOutlookCalendarTemplate({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) async {
    final urlStr = buildOutlookCalendarTemplateUrl(
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

  /// Opens Yahoo Calendar in browser/app to add event
  static Future<bool> launchYahooCalendarTemplate({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String conveneUrl,
  }) async {
    final urlStr = buildYahooCalendarTemplateUrl(
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

  /// Displays the interactive "Add to Calendar" bottom sheet
  static void showAddToCalendarSheet(
    BuildContext context, {
    required Meeting meeting,
  }) {
    final conveneUrl = 'https://meeting-app-844aa.web.app/pre-join/${meeting.id}';

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add to Calendar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meeting.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _CalendarOptionTile(
                icon: Icons.calendar_month_rounded,
                title: 'Google Calendar',
                subtitle: 'Open in Google Calendar web/app',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final url = buildGoogleCalendarTemplateUrl(
                    title: meeting.title,
                    startTime: meeting.startTime,
                    endTime: meeting.endTime,
                    conveneUrl: conveneUrl,
                  );
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
              ),
              _CalendarOptionTile(
                icon: Icons.mail_outline_rounded,
                title: 'Microsoft Outlook / Office 365',
                subtitle: 'Open in Outlook Calendar',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  launchOutlookCalendarTemplate(
                    title: meeting.title,
                    startTime: meeting.startTime,
                    endTime: meeting.endTime,
                    conveneUrl: conveneUrl,
                  );
                },
              ),
              _CalendarOptionTile(
                icon: Icons.apple_rounded,
                title: 'Apple Calendar / .ICS File',
                subtitle: 'Download universal calendar invite file',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  downloadOrExportIcs(
                    meetingId: meeting.id,
                    title: meeting.title,
                    startTime: meeting.startTime,
                    endTime: meeting.endTime,
                    conveneUrl: conveneUrl,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Calendar invite (.ics) generated! 📅')),
                  );
                },
              ),
              _CalendarOptionTile(
                icon: Icons.language_rounded,
                title: 'Yahoo Calendar',
                subtitle: 'Open in Yahoo Calendar',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  launchYahooCalendarTemplate(
                    title: meeting.title,
                    startTime: meeting.startTime,
                    endTime: meeting.endTime,
                    conveneUrl: conveneUrl,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CalendarOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: context.colors.primary, size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.colors.textMain,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: context.colors.textMuted,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: context.colors.textMuted,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
