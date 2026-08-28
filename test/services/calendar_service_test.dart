import 'package:flutter_test/flutter_test.dart';
import 'package:convene/services/calendar_service.dart';

void main() {
  group('CalendarService Template & ICS Generation Tests', () {
    final startTime = DateTime.utc(2026, 8, 30, 14, 0, 0);
    final endTime = DateTime.utc(2026, 8, 30, 15, 0, 0);
    const title = 'Quarterly Strategy Review';
    const conveneUrl = 'https://meeting-app-844aa.web.app/pre-join/meet_123';

    test('buildGoogleCalendarTemplateUrl formats correct web template URL', () {
      final url = CalendarService.buildGoogleCalendarTemplateUrl(
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
      );

      expect(url, startsWith('https://calendar.google.com/calendar/render?action=TEMPLATE'));
      expect(url, contains('text=Quarterly%20Strategy%20Review'));
      expect(url, contains('dates=20260830T140000Z/20260830T150000Z'));
      expect(url, contains(Uri.encodeComponent(conveneUrl)));
    });

    test('buildOutlookCalendarTemplateUrl formats correct web template URL', () {
      final url = CalendarService.buildOutlookCalendarTemplateUrl(
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
      );

      expect(url, startsWith('https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent'));
      expect(url, contains('subject=Quarterly%20Strategy%20Review'));
      expect(url, contains('startdt=2026-08-30T14%3A00%3A00.000Z'));
      expect(url, contains('enddt=2026-08-30T15%3A00%3A00.000Z'));
      expect(url, contains(Uri.encodeComponent(conveneUrl)));
    });

    test('buildYahooCalendarTemplateUrl formats correct web template URL', () {
      final url = CalendarService.buildYahooCalendarTemplateUrl(
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
      );

      expect(url, startsWith('https://calendar.yahoo.com/?v=60'));
      expect(url, contains('title=Quarterly%20Strategy%20Review'));
      expect(url, contains('st=20260830T140000Z'));
      expect(url, contains('et=20260830T150000Z'));
      expect(url, contains(Uri.encodeComponent(conveneUrl)));
    });

    test('generateIcsFileContent produces valid RFC 5545 iCalendar content', () {
      final ics = CalendarService.generateIcsFileContent(
        meetingId: 'meet_123',
        title: title,
        startTime: startTime,
        endTime: endTime,
        conveneUrl: conveneUrl,
        attendees: ['alice@example.com', 'bob@example.com'],
      );

      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('VERSION:2.0'));
      expect(ics, contains('PRODID:-//Convene//Meeting App//EN'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('UID:meet_123_convene@meeting-app-844aa.web.app'));
      expect(ics, contains('SUMMARY:Quarterly Strategy Review'));
      expect(ics, contains('DTSTART:20260830T140000Z'));
      expect(ics, contains('DTEND:20260830T150000Z'));
      expect(ics, contains('URL:https://meeting-app-844aa.web.app/pre-join/meet_123'));
      expect(ics, contains('LOCATION:https://meeting-app-844aa.web.app/pre-join/meet_123'));
      expect(ics, contains('STATUS:CONFIRMED'));
      expect(ics, contains('ATTENDEE;RSVP=TRUE:mailto:alice@example.com'));
      expect(ics, contains('ATTENDEE;RSVP=TRUE:mailto:bob@example.com'));
      expect(ics, contains('END:VEVENT'));
      expect(ics, contains('END:VCALENDAR'));
    });
  });
}
