import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/context_thread.dart';
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
  final TextEditingController _newAgendaController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String? _selectedGroupId;
  String? _selectedTopicId; // if set, this meeting's summary appends to a topic
  MeetingType _selectedType = MeetingType.meet;
  bool _isLoading = false;
  bool _syncWithCalendar = true;
  int _durationMinutes = 30;

  final List<String> _agendaItems = [];
  final List<String> _carriedOverTasks = [];
  bool _isGeneratingAiAgenda = false;

  static const List<int> _durationOptions = [15, 30, 45, 60, 90, 120];

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes / 60;
    return hours == hours.roundToDouble() ? '${hours.toInt()} hr' : '${hours.toStringAsFixed(1)} hr';
  }

  @override
  void initState() {
    super.initState();
    _syncWithCalendar = ref.read(calendarAutoSyncProvider);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _guestEmailsController.dispose();
    _newAgendaController.dispose();
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

  void _generateAiAgenda() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a meeting title first.')),
      );
      return;
    }

    setState(() => _isGeneratingAiAgenda = true);

    final threads = ref.read(threadsProvider).value ?? [];
    final carriedTasks = <String>[];

    // Find prior open action items in this topic or group
    for (final thread in threads) {
      final isMatch = (_selectedTopicId != null && thread.id == _selectedTopicId) ||
          (_selectedGroupId != null && thread.groupId == _selectedGroupId);
      if (isMatch) {
        for (final block in thread.blocks) {
          if (block.type == SmartBlockType.actionItem && !block.isCompleted) {
            carriedTasks.add(block.content);
          }
        }
      }
    }

    // AI Smart Agenda Heuristics based on Title & Context
    final generatedAgenda = <String>[];
    final titleLower = title.toLowerCase();

    if (titleLower.contains('standup') || titleLower.contains('sync')) {
      generatedAgenda.addAll([
        'Yesterday\'s progress & wins',
        'Today\'s priority commitments',
        'Blockers & cross-team dependencies',
      ]);
    } else if (titleLower.contains('sprint') || titleLower.contains('planning')) {
      generatedAgenda.addAll([
        'Sprint goals & scope review',
        'Capacity & team bandwidth alignment',
        'Carried-over backlog estimation',
        'Action items & milestone commitments',
      ]);
    } else if (titleLower.contains('design') || titleLower.contains('ui') || titleLower.contains('ux')) {
      generatedAgenda.addAll([
        'Design mockup walkthrough & user flows',
        'Component edge-cases & accessibility',
        'Engineering handoff & feasibility review',
      ]);
    } else if (titleLower.contains('review') || titleLower.contains('retro')) {
      generatedAgenda.addAll([
        'What went well & key milestones',
        'What can be improved & process friction',
        'Actionable commitments for next cycle',
      ]);
    } else {
      generatedAgenda.addAll([
        'Context & key objective alignment',
        'Discussion & options evaluation',
        'Decisions, ownership & next steps',
      ]);
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _isGeneratingAiAgenda = false;
          _agendaItems.clear();
          _agendaItems.addAll(generatedAgenda);
          _carriedOverTasks.clear();
          _carriedOverTasks.addAll(carriedTasks.take(5));
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              carriedTasks.isNotEmpty
                  ? 'Generated ${generatedAgenda.length} agenda items + carried over ${carriedTasks.length} action items!'
                  : 'AI Smart Agenda generated!',
            ),
          ),
        );
      }
    });
  }

  Future<void> _scheduleMeeting() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a meeting title')),
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
        guestEmails = _guestEmailsController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e.contains('@'))
            .toList();
      }

      final random = Random();
      final meetingId = 'meet_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000)}';

      final meeting = Meeting(
        id: meetingId,
        title: _titleController.text.trim(),
        startTime: startTime,
        endTime: endTime,
        type: _selectedType,
        participants: [user],
        groupId: _selectedGroupId,
        topicId: _selectedTopicId,
        guestEmails: guestEmails,
        agenda: _agendaItems,
        carriedOverTasks: _carriedOverTasks,
        rsvps: {user.id: 'yes'},
      );

      await ref.read(firestoreRepositoryProvider).createMeeting(meeting);

      // Multi-Provider Calendar sync
      bool calendarSynced = false;
      if (_syncWithCalendar && _selectedType == MeetingType.meet) {
        try {
          final conveneUrl = 'https://meeting-app-844aa.web.app/pre-join/$meetingId';

          calendarSynced = await ref.read(calendarServiceProvider).createEvent(
            title: meeting.title,
            startTime: startTime,
            endTime: endTime,
            guestEmails: guestEmails,
            conveneUrl: conveneUrl,
          ).timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('Calendar sync failed (non-fatal): $e');
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        final msg = !_syncWithCalendar || _selectedType != MeetingType.meet
            ? 'Meeting scheduled!'
            : calendarSynced
                ? 'Meeting scheduled & synced to Google Calendar! 📅'
                : 'Meeting scheduled! Opened Google Calendar template to save.';
        messenger.showSnackBar(SnackBar(content: Text(msg)));
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

  Widget _buildAgendaBuilder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.format_list_bulleted_rounded, size: 18, color: context.colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Meeting Agenda & Prep',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _isGeneratingAiAgenda ? null : _generateAiAgenda,
                icon: _isGeneratingAiAgenda
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 14),
                label: Text(
                  _isGeneratingAiAgenda ? 'Generating...' : '✨ AI Agenda',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Agenda Items List
          if (_agendaItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No agenda items added yet. Tap "✨ AI Agenda" to auto-generate or type below.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted),
              ),
            )
          else
            ..._agendaItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textMain,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _agendaItems.removeAt(idx)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: context.colors.textLight,
                    ),
                  ],
                ),
              );
            }),

          // Carried over tasks chips
          if (_carriedOverTasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'Carried Over Action Items (${_carriedOverTasks.length}):',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.textMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _carriedOverTasks.map((task) {
                return Chip(
                  label: Text(task, style: const TextStyle(fontSize: 11)),
                  backgroundColor: context.colors.background,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => _carriedOverTasks.remove(task)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),
          // Add custom agenda input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newAgendaController,
                  style: TextStyle(fontSize: 13, color: context.colors.textMain),
                  decoration: InputDecoration(
                    hintText: 'Add agenda item...',
                    hintStyle: TextStyle(fontSize: 12, color: context.colors.textLight),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: context.colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      setState(() {
                        _agendaItems.add(val.trim());
                        _newAgendaController.clear();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.add_circle, color: context.colors.primary, size: 28),
                onPressed: () {
                  final text = _newAgendaController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _agendaItems.add(text);
                      _newAgendaController.clear();
                    });
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Container(
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
                  icon: Icon(Icons.close, color: context.colors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              autofocus: true,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textMain,
              ),
              decoration: InputDecoration(
                hintText: 'Meeting Title',
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 18, color: context.colors.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('MMM d, y').format(_selectedDate),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textMain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 18, color: context.colors.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            _selectedTime.format(context),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textMain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 8),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _buildTopicSelector(),
            const SizedBox(height: 16),

            // AI Smart Agenda Builder
            _buildAgendaBuilder(),
            const SizedBox(height: 16),

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
            const SizedBox(height: 16),
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
                const SizedBox(width: 12),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: _syncWithCalendar,
                  onChanged: (val) => setState(() => _syncWithCalendar = val),
                  activeThumbColor: context.colors.primary,
                ),
                const SizedBox(width: 8),
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
            const SizedBox(height: 32),
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
                  ? const SizedBox(
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
