import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';


import '../../models/meeting.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/firestore_repository.dart';
import '../../services/calendar_service.dart';
import '../../theme/app_theme.dart';

class ScheduleMeetingSheet extends ConsumerStatefulWidget {
  const ScheduleMeetingSheet({super.key});

  @override
  ConsumerState<ScheduleMeetingSheet> createState() => _ScheduleMeetingSheetState();
}

class _ScheduleMeetingSheetState extends ConsumerState<ScheduleMeetingSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _guestEmailsController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String? _selectedGroupId;
  String? _selectedTopicId; // if set, this meeting's summary appends to a topic
  MeetingType _selectedType = MeetingType.meet;
  bool _isLoading = false;
  bool _syncWithCalendar = true;
  int _durationMinutes = 30;

  static const List<int> _durationOptions = [15, 30, 45, 60, 90, 120];

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes / 60;
    return hours == hours.roundToDouble() ? '${hours.toInt()} hr' : '${hours.toStringAsFixed(1)} hr';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _guestEmailsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _scheduleMeeting() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a meeting title')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(appUserProvider);
      
      final startTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final endTime = startTime.add(Duration(minutes: _durationMinutes));

      List<String> guestEmails = [];
      if (_guestEmailsController.text.trim().isNotEmpty) {
        guestEmails = _guestEmailsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }

      if (_selectedGroupId != null) {
        final groups = ref.read(groupsProvider).value ?? [];
        try {
          final group = groups.firstWhere((g) => g.id == _selectedGroupId);
          guestEmails.addAll(group.members.map((m) => m.email).where((e) => e.isNotEmpty));
        } catch (_) {}
      }

      // Guests are resolved to real accounts and added as participants
      // SERVER-SIDE (onMeetingCreated), so this works no matter what build
      // the client is on. The creator is the only participant we set here.
      final participants = [user];

      // Direct meeting IDs form part of a shareable bearer link, so timestamps
      // alone are not safe: use 96 bits from the platform CSPRNG instead.
      final random = Random.secure();
      final meetingId = List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
      final conveneUrl = 'https://meeting-app-844aa.web.app/pre-join/$meetingId';

      final meeting = Meeting(
        id: meetingId,
        title: _titleController.text.trim(),
        groupId: _selectedGroupId,
        topicId: _selectedTopicId,
        startTime: startTime,
        endTime: endTime,
        type: _selectedType,
        participants: participants,
        guestEmails: guestEmails,
      );

      // Create the meeting FIRST - this is the operation that actually matters.
      // Calendar sync is a best-effort extra afterward, so a broken/expired
      // Google token (common for email-signup users who never granted Calendar
      // access) can never block the meeting from being scheduled.
      await ref.read(firestoreRepositoryProvider).createMeeting(meeting).timeout(const Duration(seconds: 10));

      bool calendarSynced = false;
      String? calendarError;
      if (_syncWithCalendar && _selectedType == MeetingType.meet) {
        try {
          await ref.read(calendarServiceProvider).createEvent(
                title: _titleController.text.trim(),
                startTime: startTime,
                endTime: endTime,
                guestEmails: guestEmails,
                conveneUrl: conveneUrl,
              ).timeout(const Duration(seconds: 15));
          calendarSynced = true;
        } catch (e) {
          calendarError = e.toString();
          debugPrint('Calendar sync failed (non-fatal): $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        final msg = !_syncWithCalendar || _selectedType != MeetingType.meet
            ? 'Meeting scheduled!'
            : calendarSynced
                ? 'Meeting scheduled & added to Google Calendar!'
                : 'Meeting scheduled. (Couldn\'t add to Google Calendar - reconnect Google to enable this.)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        if (calendarError != null) debugPrint(calendarError);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Optional: attach this meeting's future summary to an existing topic, so
  /// several meetings about the same subject accumulate into one running topic
  /// instead of spawning a separate summary each time.
  Widget _buildTopicSelector() {
    final threadsAsync = ref.watch(threadsProvider);
    return threadsAsync.maybeWhen(
      data: (threads) {
        if (threads.isEmpty) return const SizedBox.shrink();
        final sorted = List.of(threads)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTopicId,
              isExpanded: true,
              dropdownColor: context.colors.surface,
              icon: Icon(Icons.arrow_drop_down, color: context.colors.textMuted),
              hint: Text(
                'Add to existing topic (Optional)',
                style: GoogleFonts.plusJakartaSans(color: context.colors.textLight, fontWeight: FontWeight.w500),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('New topic', style: GoogleFonts.plusJakartaSans(color: context.colors.textMain)),
                ),
                ...sorted.take(30).map((t) => DropdownMenuItem<String>(
                      value: t.id,
                      child: Text(
                        t.meetingTitle,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(color: context.colors.textMain, fontWeight: FontWeight.w600),
                      ),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedTopicId = val),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Container(
      // Cap the height so the sheet never grows taller than the screen; the
      // content scrolls inside. Without this the tall form overflowed and the
      // Schedule button at the bottom couldn't be reached on small/keyboard-up
      // screens.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          // Keyboard-aware: extra bottom space so the Schedule button can be
          // scrolled up above the on-screen keyboard.
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Schedule Meeting',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: context.colors.textMuted),
              ),
            ],
          ),
          SizedBox(height: 24),
          TextField(
            controller: _titleController,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textMain,
            ),
            decoration: InputDecoration(
              hintText: 'Meeting Title (e.g., Weekly Sync)',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: context.colors.textLight,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: context.colors.primary),
                        SizedBox(width: 8),
                        Text(
                          DateFormat('MMM d, yyyy').format(_selectedDate),
                          style: GoogleFonts.plusJakartaSans(
                            color: context.colors.textMain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 18, color: context.colors.primary),
                        SizedBox(width: 8),
                        Text(
                          _selectedTime.format(context),
                          style: GoogleFonts.plusJakartaSans(
                            color: context.colors.textMain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Duration',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textMuted,
              ),
            ),
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durationOptions.map((minutes) {
              final isSelected = _durationMinutes == minutes;
              return GestureDetector(
                onTap: () => setState(() => _durationMinutes = minutes),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? context.colors.primary.withValues(alpha: 0.1) : context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? context.colors.primary : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    _formatDuration(minutes),
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? context.colors.primary : context.colors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 16),
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGroupId,
                    hint: Text(
                      'Link to a Group (Optional)',
                      style: GoogleFonts.plusJakartaSans(
                        color: context.colors.textLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    isExpanded: true,
                    dropdownColor: context.colors.surface,
                    icon: Icon(Icons.arrow_drop_down, color: context.colors.textMuted),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'No Group',
                          style: GoogleFonts.plusJakartaSans(color: context.colors.textMain),
                        ),
                      ),
                      ...groups.map((g) {
                        return DropdownMenuItem<String>(
                          value: g.id,
                          child: Text(
                            g.name,
                            style: GoogleFonts.plusJakartaSans(
                              color: context.colors.textMain,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedGroupId = val);
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          SizedBox(height: 16),
          _buildTopicSelector(),
          SizedBox(height: 16),
          TextField(
            controller: _guestEmailsController,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.textMain,
            ),
            decoration: InputDecoration(
              hintText: 'Guest Emails (comma-separated)',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: context.colors.textLight,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = MeetingType.meet),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedType == MeetingType.meet ? context.colors.primary.withValues(alpha: 0.1) : context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedType == MeetingType.meet ? context.colors.primary : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Online',
                        style: GoogleFonts.plusJakartaSans(
                          color: _selectedType == MeetingType.meet ? context.colors.primary : context.colors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = MeetingType.room),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedType == MeetingType.room ? context.colors.primary.withValues(alpha: 0.1) : context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedType == MeetingType.room ? context.colors.primary : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'In-Person',
                        style: GoogleFonts.plusJakartaSans(
                          color: _selectedType == MeetingType.room ? context.colors.primary : context.colors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Switch(
                value: _syncWithCalendar,
                onChanged: (val) => setState(() => _syncWithCalendar = val),
                activeThumbColor: context.colors.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Google Calendar Invites',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textMain,
                      ),
                    ),
                    Text(
                      'Invite group members to this meeting',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isLoading ? null : _scheduleMeeting,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    'Schedule',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          ],
        ),
      ),
    );
  }
}
