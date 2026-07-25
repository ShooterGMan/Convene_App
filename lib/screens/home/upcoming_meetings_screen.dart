import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';

import '../../models/context_thread.dart';
import '../../models/group.dart';
import '../../models/meeting.dart';
import '../../models/user.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/live_soon_banner.dart';
import '../../widgets/meeting_card.dart';
import '../../widgets/mini_month_calendar.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/schedule_meeting_sheet.dart';

enum _TypeFilter { all, online, inPerson }

enum _ViewMode { list, calendar }

/// The home/dashboard screen showing upcoming meetings.
///
/// Real upcoming meetings (not yet happened) are shown prominently, sorted
/// soonest-first; past meetings are collapsed below, de-emphasized, and
/// sorted most-recent-first - a history you can dig into, not the main
/// event. Supports filtering by group/type and a Convene-only calendar view.
class UpcomingMeetingsScreen extends ConsumerStatefulWidget {
  const UpcomingMeetingsScreen({super.key});

  @override
  ConsumerState<UpcomingMeetingsScreen> createState() => _UpcomingMeetingsScreenState();
}

class _UpcomingMeetingsScreenState extends ConsumerState<UpcomingMeetingsScreen> {
  _ViewMode _viewMode = _ViewMode.list;
  _TypeFilter _typeFilter = _TypeFilter.all;
  String? _groupFilterId; // null = all groups
  bool _pastExpanded = false;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  /// Group meetings by calendar date.
  Map<DateTime, List<Meeting>> _groupByDate(List<Meeting> meetings) {
    final Map<DateTime, List<Meeting>> grouped = {};
    for (final meeting in meetings) {
      final dateKey = DateTime(meeting.startTime.year, meeting.startTime.month, meeting.startTime.day);
      grouped.putIfAbsent(dateKey, () => []).add(meeting);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return grouped;
  }

  String _dateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));
    final formattedDate = DateFormat('MMM d').format(date);

    if (date == today) return 'Today, $formattedDate';
    if (date == tomorrow) return 'Tomorrow, $formattedDate';
    if (date == yesterday) return 'Yesterday, $formattedDate';
    return DateFormat('EEEE, MMM d').format(date);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  List<Meeting> _applyFilters(List<Meeting> meetings) {
    return meetings.where((m) {
      if (_groupFilterId != null && m.groupId != _groupFilterId) return false;
      switch (_typeFilter) {
        case _TypeFilter.all:
          return true;
        case _TypeFilter.online:
          return m.type == MeetingType.meet;
        case _TypeFilter.inPerson:
          return m.type == MeetingType.room || m.type == MeetingType.audio;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final selfUser = ref.watch(appUserProvider);
    final meetingsAsync = ref.watch(meetingsProvider);
    final threadsAsync = ref.watch(threadsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final groups = groupsAsync.maybeWhen(data: (g) => g, orElse: () => const <Group>[]);

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: _buildFabs(context),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${_greeting()}, ${selfUser.name.split(' ').first}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textMain,
                              height: 1.2,
                            ),
                          ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.03, end: 0, duration: 500.ms, curve: Curves.easeOut),
                        ),
                        const NotificationBell(),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildSyncPill(context, meetingsAsync),
                    SizedBox(height: 16),
                    const LiveSoonBanner(),
                    _buildViewToggle(context),
                    SizedBox(height: 12),
                    _buildFilterRow(context, groups),
                    SizedBox(height: 24),
                    Text(
                      'My Tasks',
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.textMain),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                    SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 140,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: _buildMyTasksCards(context, threadsAsync, selfUser),
                  ),
                ),
              ),
            ),
            meetingsAsync.when(
              data: (allMeetings) {
                final meetings = _applyFilters(allMeetings);
                return _viewMode == _ViewMode.list
                    ? _buildListView(context, meetings)
                    : _buildCalendarView(context, meetings);
              },
              loading: () => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator(color: context.colors.primary)),
                ),
              ),
              error: (e, st) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Center(child: Text('Error loading meetings: $e', style: TextStyle(color: context.colors.textMuted))),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncPill(BuildContext context, AsyncValue<List<Meeting>> meetingsAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: meetingsAsync.hasError ? Colors.redAccent.withValues(alpha: 0.15) : context.colors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            meetingsAsync.hasError
                ? Icons.sync_problem_rounded
                : meetingsAsync.isLoading
                    ? Icons.sync_rounded
                    : Icons.check_circle_outline_rounded,
            size: 14,
            color: meetingsAsync.hasError ? Colors.redAccent : context.colors.textMuted,
          ),
          SizedBox(width: 6),
          Text(
            meetingsAsync.hasError ? 'Sync failed' : (meetingsAsync.isLoading ? 'Syncing…' : 'Synced'),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: meetingsAsync.hasError ? Colors.redAccent : context.colors.textMuted,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildViewToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(child: _viewToggleButton(context, 'List', Icons.view_list_rounded, _ViewMode.list)),
          Expanded(child: _viewToggleButton(context, 'Calendar', Icons.calendar_month_rounded, _ViewMode.calendar)),
        ],
      ),
    );
  }

  Widget _viewToggleButton(BuildContext context, String label, IconData icon, _ViewMode mode) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : context.colors.textMuted),
            SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context, List<Group> groups) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(context, 'All', _typeFilter == _TypeFilter.all, () => setState(() => _typeFilter = _TypeFilter.all)),
          SizedBox(width: 8),
          _filterChip(context, 'Online', _typeFilter == _TypeFilter.online, () => setState(() => _typeFilter = _TypeFilter.online)),
          SizedBox(width: 8),
          _filterChip(
              context, 'In-Person', _typeFilter == _TypeFilter.inPerson, () => setState(() => _typeFilter = _TypeFilter.inPerson)),
          if (groups.isNotEmpty) ...[
            SizedBox(width: 8),
            Container(width: 1, height: 20, color: context.colors.border),
            SizedBox(width: 8),
            _filterChip(context, 'All Groups', _groupFilterId == null, () => setState(() => _groupFilterId = null)),
            for (final g in groups) ...[
              SizedBox(width: 8),
              _filterChip(context, g.name, _groupFilterId == g.id, () => setState(() => _groupFilterId = g.id)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _filterChip(BuildContext context, String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primary.withValues(alpha: 0.12) : context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: isSelected ? context.colors.primary : context.colors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? context.colors.primary : context.colors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildListView(BuildContext context, List<Meeting> meetings) {
    final upcoming = meetings.where((m) => !m.isPast).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
    final past = meetings.where((m) => m.isPast).toList()..sort((a, b) => b.startTime.compareTo(a.startTime));

    final List<Widget> children = [];

    if (upcoming.isEmpty && past.isEmpty) {
      children.add(_buildEmptyState(context));
    } else {
      final grouped = _groupByDate(upcoming);
      final sortedKeys = grouped.keys.toList()..sort();
      int cardIndex = 0;
      for (final key in sortedKeys) {
        children.add(_sectionHeader(context, _dateHeader(key), cardIndex));
        for (final meeting in grouped[key]!) {
          final delay = (cardIndex * 80).ms;
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MeetingCard(meeting: meeting)
                .animate()
                .fadeIn(delay: delay, duration: 500.ms)
                .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: delay, curve: Curves.easeOut),
          ));
          cardIndex++;
        }
      }

      if (upcoming.isEmpty) {
        children.add(_buildEmptyState(context));
      }

      if (past.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: GestureDetector(
              onTap: () => setState(() => _pastExpanded = !_pastExpanded),
              child: Row(
                children: [
                  Icon(
                    _pastExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: context.colors.textMuted,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Past meetings (${past.length})',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        );
        if (_pastExpanded) {
          for (final meeting in past) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Opacity(opacity: 0.55, child: MeetingCard(meeting: meeting)),
            ));
          }
        }
      }
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
  }

  Widget _sectionHeader(BuildContext context, String label, int cardIndex) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 24, bottom: 12),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMuted, letterSpacing: 0.5),
      ).animate().fadeIn(delay: (cardIndex * 80).ms, duration: 400.ms),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: context.colors.primaryLight.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(Icons.event_available, size: 48, color: context.colors.primary),
          ),
          SizedBox(height: 24),
          Text(
            'No upcoming meetings',
            style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: context.colors.textMain),
          ),
          SizedBox(height: 8),
          Text(
            'Your schedule is clear! Take a breather or schedule your next big sync.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: context.colors.textMuted, height: 1.5),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const ScheduleMeetingSheet(),
              );
            },
            icon: Icon(Icons.add, size: 20),
            label: Text('Schedule Meeting'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
              textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
    );
  }

  Widget _buildCalendarView(BuildContext context, List<Meeting> meetings) {
    final eventCounts = <DateTime, int>{};
    for (final m in meetings) {
      final key = DateTime(m.startTime.year, m.startTime.month, m.startTime.day);
      eventCounts[key] = (eventCounts[key] ?? 0) + 1;
    }

    final selected = _selectedDate ?? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final dayMeetings = meetings.where((m) {
      return m.startTime.year == selected.year && m.startTime.month == selected.month && m.startTime.day == selected.day;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          MiniMonthCalendar(
            visibleMonth: _visibleMonth,
            selectedDate: _selectedDate,
            eventCounts: eventCounts,
            onDaySelected: (date) => setState(() => _selectedDate = date),
            onMonthChanged: (month) => setState(() => _visibleMonth = month),
          ),
          SizedBox(height: 20),
          Text(
            DateFormat('EEEE, MMM d').format(selected),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMuted),
          ),
          SizedBox(height: 12),
          if (dayMeetings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No meetings this day', style: GoogleFonts.plusJakartaSans(color: context.colors.textMuted)),
              ),
            )
          else
            for (final meeting in dayMeetings)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Opacity(opacity: meeting.isPast ? 0.55 : 1.0, child: MeetingCard(meeting: meeting)),
              ),
        ]),
      ),
    );
  }

  List<Widget> _buildMyTasksCards(BuildContext context, AsyncValue<List<ContextThread>> threadsAsync, AppUser selfUser) {
    return threadsAsync.when(
      data: (allThreads) {
        final List<Widget> cards = [];
        int index = 0;
        final myFirstName = selfUser.name.split(' ').first;

        for (final thread in allThreads) {
          for (final block in thread.blocks) {
            if (block.type == SmartBlockType.actionItem && block.assignee == myFirstName && !block.isCompleted) {
              final delay = (index * 100).ms;
              cards.add(
                GestureDetector(
                  onTap: () => context.push('/thread/${thread.id}'),
                  child: Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      boxShadow: AppShadows.card,
                      border: Border(left: BorderSide(color: context.colors.primary, width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: context.colors.primary, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                thread.meetingTitle,
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            block.content,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: context.colors.textMain, height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: delay + 300.ms, duration: 400.ms).slideX(begin: 0.05, end: 0, delay: delay + 300.ms),
              );
              index++;
            }
          }
        }

        if (cards.isEmpty) {
          return [
            Center(
              child: Text('No pending tasks!', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: context.colors.textMuted)),
            )
          ];
        }
        return cards;
      },
      loading: () => [Center(child: CircularProgressIndicator(color: context.colors.primary))],
      error: (e, st) => [Center(child: Text('Error: $e'))],
    );
  }

  Future<void> _startInstantMeeting(BuildContext context) async {
    final user = ref.read(appUserProvider);
    final meetingId = 'meet_${DateTime.now().millisecondsSinceEpoch}';
    // Create a real meeting doc up front (title, type, creator) so an instant
    // meeting is first-class like a scheduled one - a shared link always
    // points at a real meeting, and the AI summary has proper participant
    // data instead of a bare doc the join call scrapes together.
    final now = DateTime.now();
    final meeting = Meeting(
      id: meetingId,
      title: '${user.name.split(' ').first}\'s Meeting',
      startTime: now,
      endTime: now.add(const Duration(hours: 1)),
      type: MeetingType.meet,
      participants: [user],
    );
    try {
      await ref.read(firestoreRepositoryProvider).createMeeting(meeting).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Non-fatal: getLivekitToken still creates a minimal doc on join.
      debugPrint('Failed to pre-create instant meeting doc: $e');
    }
    if (context.mounted) {
      context.push('/pre-join/$meetingId', extra: {'title': meeting.title});
    }
  }

  Widget _buildFabs(BuildContext context) {
    // Single compact button that opens a menu of the three "new" actions, so
    // three stacked extended FABs no longer overlap the content behind them
    // on narrow screens.
    return FloatingActionButton(
      heroTag: 'new_fab',
      onPressed: () => _showNewMenu(context),
      backgroundColor: context.colors.primary,
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack);
  }

  void _showNewMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.only(top: 12, bottom: MediaQuery.of(sheetContext).padding.bottom + 16),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _newMenuItem(
              context,
              icon: Icons.add_rounded,
              iconBg: context.colors.primary,
              iconColor: Colors.white,
              title: 'Schedule Meeting',
              subtitle: 'Pick a time, invite people or a group',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const ScheduleMeetingSheet(),
                );
              },
            ),
            _newMenuItem(
              context,
              icon: Icons.videocam_rounded,
              iconBg: context.colors.primaryLight,
              iconColor: context.colors.primary,
              title: 'Start Meeting Now',
              subtitle: 'Begin an instant online meeting',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startInstantMeeting(context);
              },
            ),
            _newMenuItem(
              context,
              icon: Icons.mic_rounded,
              iconBg: context.colors.primaryLight,
              iconColor: context.colors.primary,
              title: 'Record In-Person',
              subtitle: 'Record a meeting happening in the room',
              onTap: () {
                Navigator.of(sheetContext).pop();
                final newMeetingId = 'audio_${DateTime.now().millisecondsSinceEpoch}';
                context.push('/recording/$newMeetingId', extra: {'title': 'Quick Recording', 'participants': <AppUser>[]});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _newMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textMain)),
      subtitle: Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted)),
    );
  }
}
