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
  MeetingType _selectedType = MeetingType.meet;
  bool _isLoading = false;
  bool _syncWithCalendar = true;

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
      final endTime = startTime.add(const Duration(minutes: 60));

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

      guestEmails = guestEmails.toSet().toList();

      String? meetUrl;
      if (_syncWithCalendar && _selectedType == MeetingType.meet) {
        meetUrl = await ref.read(calendarServiceProvider).createEvent(
          title: _titleController.text.trim(),
          startTime: startTime,
          endTime: endTime,
          guestEmails: guestEmails,
        );
      }

      final meeting = Meeting(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        groupId: _selectedGroupId,
        startTime: startTime,
        endTime: endTime,
        type: _selectedType,
        participants: [user],
        meetUrl: meetUrl,
        guestEmails: guestEmails,
      );

      await ref.read(firestoreRepositoryProvider).createMeeting(meeting);

      if (_syncWithCalendar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Meeting scheduled & added to Google Calendar!')),
        );
      }

      if (mounted) {
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            error: (_, __) => const SizedBox.shrink(),
          ),
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
                activeColor: context.colors.primary,
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
    );
  }
}
