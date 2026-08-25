import 'dart:math';

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
import '../../models/group_invite.dart';
import '../../models/meeting.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/live_soon_banner.dart';
import '../../widgets/meeting_card.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/schedule_meeting_sheet.dart';

enum _TypeFilter { all, online, inPerson }

/// Direct meeting IDs are bearer invite links, so they need substantially more
/// entropy than a predictable timestamp. 96 random bits makes guessing a live
/// link impractical while keeping IDs URL-safe.
String _newMeetingId(String prefix) {
  final random = Random.secure();
  final suffix = List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${prefix}_$suffix';
}

/// The home/dashboard screen.
///
/// Phase 2 redesign: the dashboard answers one question — "what do I need to
/// join or catch up on?" — with a single prominent action (New meeting) plus
/// Join-with-link, then three focused sections (Next up · Needs your attention
/// · Recent topics). A 7-day strip sits up top for quick day scanning; the full
/// 30-day calendar and complete meeting history are progressive-disclosure rows
/// so they're discoverable without crowding the default view.
class UpcomingMeetingsScreen extends ConsumerStatefulWidget {
  const UpcomingMeetingsScreen({super.key});

  @override
  ConsumerState<UpcomingMeetingsScreen> createState() => _UpcomingMeetingsScreenState();
}

class _UpcomingMeetingsScreenState extends ConsumerState<UpcomingMeetingsScreen> {
  DateTime? _selectedDate; // top date picker filter
  bool _allMeetingsExpanded = false;

  // Filters only apply inside the "All meetings" disclosure, keeping the main
  // dashboard uncluttered.
  _TypeFilter _typeFilter = _TypeFilter.all;
  String? _groupFilterId;
  bool _pastExpanded = false;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final selfUser = ref.watch(appUserProvider);
    final meetingsAsync = ref.watch(meetingsProvider);
    final threadsAsync = ref.watch(threadsProvider);
    final invitesAsync = ref.watch(pendingInvitesProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final groups = groupsAsync.maybeWhen(data: (g) => g, orElse: () => const <Group>[]);
    final threads = threadsAsync.maybeWhen(data: (t) => t, orElse: () => const <ContextThread>[]);
    final invites = invitesAsync.maybeWhen(data: (i) => i, orElse: () => const <GroupInvite>[]);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: () async {
            ref.invalidate(meetingsProvider);
            ref.invalidate(threadsProvider);
            ref.invalidate(pendingInvitesProvider);
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, selfUser.name),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildTopCalendarPicker(context),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildPrimaryActions(context),
                      const SizedBox(height: 16),
                      const LiveSoonBanner(),
                      const SizedBox(height: 16),
                      _buildNextUp(context, meetingsAsync),
                      _buildNeedsAttention(context, invites, threads, selfUser.name),
                      _buildMyActionItemsWidget(context, threads, selfUser.name),
                      _buildRecentTopics(context, threads),
                      const SizedBox(height: 12),
                      _buildAllMeetingsDisclosure(context, meetingsAsync, groups),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Header -------------------------------------------------------------

  Widget _buildHeader(BuildContext context, String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '${_greeting()}, ${name.split(' ').first}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.textMain,
              height: 1.2,
            ),
          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.03, end: 0, duration: 400.ms, curve: Curves.easeOut),
        ),
        const NotificationBell(),
      ],
    );
  }

  Widget _buildTopCalendarPicker(BuildContext context) {
    final label = _selectedDate == null
        ? 'All Meetings'
        : _isSameDay(_selectedDate!, _today)
            ? 'Today · ${DateFormat('MMM d').format(_today)}'
            : DateFormat('EEE, MMM d').format(_selectedDate!);

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: context.colors.primary,
                  onPrimary: Colors.white,
                  surface: context.colors.surface,
                  onSurface: context.colors.textMain,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() => _selectedDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: AppShadows.card,
          border: Border.all(
            color: _selectedDate != null ? context.colors.primary.withValues(alpha: 0.5) : context.colors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: _selectedDate != null ? context.colors.primary : context.colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _selectedDate != null ? context.colors.primary : context.colors.textMain,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _selectedDate != null ? context.colors.primary : context.colors.textMuted,
            ),
            if (_selectedDate != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _selectedDate = null),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.colors.textMuted.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 12, color: context.colors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Primary actions ----------------------------------------------------

  Widget _buildPrimaryActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: () => _showNewMeetingSheet(context),
            icon: const Icon(Icons.add_rounded, size: 22),
            label: Text(
              'New meeting',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: () => _showJoinWithLink(context),
            icon: const Icon(Icons.link_rounded, size: 20),
            label: Text(
              'Join link',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.primary,
              side: BorderSide(color: context.colors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }



  // ---- Next up ------------------------------------------------------------

  Widget _buildNextUp(BuildContext context, AsyncValue<List<Meeting>> meetingsAsync) {
    return meetingsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: context.colors.primary)),
      ),
      error: (e, _) => _sectionShell(
        context,
        title: 'Next up',
        child: Text('Couldn\'t load meetings: $e', style: TextStyle(color: context.colors.textMuted)),
      ),
      data: (all) {
        // With a day selected in the strip/calendar, show that day; otherwise
        // surface the single soonest upcoming meeting.
        if (_selectedDate != null) {
          final dayMeetings = all.where((m) => _isSameDay(m.startTime, _selectedDate!)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          return _sectionShell(
            context,
            title: DateFormat('EEEE, MMM d').format(_selectedDate!),
            action: _clearDayAction(context),
            child: dayMeetings.isEmpty
                ? _emptyHint(context, 'No meetings on this day.')
                : Column(
                    children: [
                      for (final m in dayMeetings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Opacity(opacity: m.isPast ? 0.6 : 1.0, child: MeetingCard(meeting: m)),
                        ),
                    ],
                  ),
          );
        }

        final upcoming = all.where((m) => !m.isPast).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
        return _sectionShell(
          context,
          title: 'Next up',
          child: upcoming.isEmpty
              ? _buildNextUpEmpty(context)
              : MeetingCard(meeting: upcoming.first),
        );
      },
    );
  }

  Widget _clearDayAction(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selectedDate = null),
      child: Text(
        'Clear',
        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.primary),
      ),
    );
  }

  Widget _buildNextUpEmpty(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 36, color: context.colors.primary),
          const SizedBox(height: 12),
          Text(
            'Nothing scheduled',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textMain),
          ),
          const SizedBox(height: 4),
          Text(
            'Start a meeting now or schedule your next one.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _showNewMeetingSheet(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New meeting'),
            style: TextButton.styleFrom(foregroundColor: context.colors.primary),
          ),
        ],
      ),
    );
  }

  // ---- Needs your attention ----------------------------------------------

  Widget _buildNeedsAttention(
    BuildContext context,
    List<GroupInvite> invites,
    List<ContextThread> threads,
    String selfName,
  ) {
    final myFirstName = selfName.split(' ').first;
    final myActions = <({ContextThread thread, SmartBlock block})>[];
    for (final thread in threads) {
      for (final block in thread.blocks) {
        if (block.type == SmartBlockType.actionItem && block.assignee == myFirstName && !block.isCompleted) {
          myActions.add((thread: thread, block: block));
        }
      }
    }

    if (invites.isEmpty && myActions.isEmpty) return const SizedBox.shrink();

    return _sectionShell(
      context,
      title: 'Needs your attention',
      child: Column(
        children: [
          for (final invite in invites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttentionTile(
                icon: Icons.group_add_rounded,
                accent: context.colors.primary,
                title: 'Invite to ${invite.groupName}',
                subtitle: 'From ${invite.invitedBy.name} · tap to respond',
                onTap: () => context.go('/groups'),
              ),
            ),
          for (final item in myActions.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttentionTile(
                icon: Icons.check_circle_outline_rounded,
                accent: context.colors.primary,
                title: item.block.content,
                subtitle: 'Action from ${item.thread.meetingTitle}',
                onTap: () => context.push('/thread/${item.thread.id}'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleActionItem(ContextThread thread, SmartBlock block) async {
    final updatedBlocks = thread.blocks.map((b) {
      if (b.id == block.id) {
        return b.copyWith(isCompleted: !b.isCompleted);
      }
      return b;
    }).toList();

    try {
      await ref.read(firestoreRepositoryProvider).updateThreadBlocks(thread.id, updatedBlocks);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(block.isCompleted ? 'Marked incomplete' : 'Action item completed! 🎉'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update action item: $e')),
        );
      }
    }
  }

  Widget _buildMyActionItemsWidget(
    BuildContext context,
    List<ContextThread> threads,
    String selfName,
  ) {
    final myFirstName = selfName.split(' ').first.toLowerCase();
    final myActions = <({ContextThread thread, SmartBlock block})>[];
    for (final thread in threads) {
      for (final block in thread.blocks) {
        if (block.type == SmartBlockType.actionItem &&
            block.assignee != null &&
            block.assignee!.trim().toLowerCase() == myFirstName &&
            !block.isCompleted) {
          myActions.add((thread: thread, block: block));
        }
      }
    }

    if (myActions.isEmpty) return const SizedBox.shrink();

    return _sectionShell(
      context,
      title: 'My Action Items (${myActions.length})',
      child: Column(
        children: [
          for (final item in myActions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttentionTile(
                icon: Icons.circle_outlined,
                accent: context.colors.primary,
                title: item.block.content,
                subtitle: 'From ${item.thread.meetingTitle}',
                onTap: () => context.push('/thread/${item.thread.id}'),
                onCheckTap: () => _toggleActionItem(item.thread, item.block),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Recent topics ------------------------------------------------------

  Widget _buildRecentTopics(BuildContext context, List<ContextThread> threads) {
    if (threads.isEmpty) return const SizedBox.shrink();
    final recent = List<ContextThread>.from(threads)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final show = recent.take(4).toList();

    return _sectionShell(
      context,
      title: 'Recent topics',
      action: GestureDetector(
        onTap: () => context.go('/threads'),
        child: Text(
          'See all',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.primary),
        ),
      ),
      child: Column(
        children: [
          for (final t in show)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecentTopicCard(thread: t),
            ),
        ],
      ),
    );
  }



  // ---- All meetings disclosure (past + filters) ---------------------------

  Widget _buildAllMeetingsDisclosure(
    BuildContext context,
    AsyncValue<List<Meeting>> meetingsAsync,
    List<Group> groups,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _disclosureRow(
          context,
          icon: Icons.history_rounded,
          label: 'All meetings',
          expanded: _allMeetingsExpanded,
          onTap: () => setState(() => _allMeetingsExpanded = !_allMeetingsExpanded),
        ),
        if (_allMeetingsExpanded) ...[
          const SizedBox(height: 12),
          _buildFilterRow(context, groups),
          const SizedBox(height: 12),
          meetingsAsync.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.colors.primary)),
            error: (e, _) => Text('Error: $e', style: TextStyle(color: context.colors.textMuted)),
            data: (all) => _buildFullList(context, _applyFilters(all)),
          ),
        ],
      ],
    );
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

  Widget _buildFullList(BuildContext context, List<Meeting> meetings) {
    final upcoming = meetings.where((m) => !m.isPast).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
    final past = meetings.where((m) => m.isPast).toList()..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (upcoming.isEmpty && past.isEmpty) {
      return _emptyHint(context, 'No meetings match these filters.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (upcoming.isNotEmpty) ...[
          _miniHeader(context, 'Upcoming (${upcoming.length})'),
          for (final m in upcoming)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: MeetingCard(meeting: m)),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _pastExpanded = !_pastExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(_pastExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: context.colors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Past meetings (${past.length})',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_pastExpanded)
            for (final m in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Opacity(opacity: 0.55, child: MeetingCard(meeting: m)),
              ),
        ],
      ],
    );
  }

  Widget _buildFilterRow(BuildContext context, List<Group> groups) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(context, 'All', _typeFilter == _TypeFilter.all, () => setState(() => _typeFilter = _TypeFilter.all)),
          const SizedBox(width: 8),
          _filterChip(context, 'Online', _typeFilter == _TypeFilter.online, () => setState(() => _typeFilter = _TypeFilter.online)),
          const SizedBox(width: 8),
          _filterChip(context, 'In-person', _typeFilter == _TypeFilter.inPerson, () => setState(() => _typeFilter = _TypeFilter.inPerson)),
          if (groups.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 20, color: context.colors.border),
            const SizedBox(width: 8),
            _filterChip(context, 'All teams', _groupFilterId == null, () => setState(() => _groupFilterId = null)),
            for (final g in groups) ...[
              const SizedBox(width: 8),
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

  // ---- Small shared building blocks --------------------------------------

  /// A titled section with an optional right-aligned action.
  Widget _sectionShell(BuildContext context, {required String title, Widget? action, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.textMain),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _miniHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.textMuted, letterSpacing: 0.4),
      ),
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
      ),
    );
  }

  Widget _disclosureRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMain),
              ),
            ),
            Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: context.colors.textMuted),
          ],
        ),
      ),
    );
  }

  // ---- New meeting / join actions ----------------------------------------

  void _showNewMeetingSheet(BuildContext context) {
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
              decoration: BoxDecoration(color: context.colors.border, borderRadius: BorderRadius.circular(2)),
            ),
            _newMenuItem(
              context,
              icon: Icons.videocam_rounded,
              iconBg: context.colors.primary,
              iconColor: Colors.white,
              title: 'Start now',
              subtitle: 'Begin an instant online meeting',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startInstantMeeting(context);
              },
            ),
            _newMenuItem(
              context,
              icon: Icons.event_rounded,
              iconBg: context.colors.primaryLight,
              iconColor: context.colors.primary,
              title: 'Schedule',
              subtitle: 'Pick a time, invite people or a team',
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
              icon: Icons.mic_rounded,
              iconBg: context.colors.primaryLight,
              iconColor: context.colors.primary,
              title: 'Record in-person',
              subtitle: 'Record a meeting happening in the room',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startQuickRecording(context);
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

  void _showJoinWithLink(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'Join with link',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a meeting link or code someone shared with you.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: context.colors.textMain),
              onSubmitted: (_) {
                Navigator.of(dialogContext).pop();
                _openFromLink(context, controller.text);
              },
              decoration: InputDecoration(
                hintText: 'https://…/pre-join/… or a code',
                hintStyle: TextStyle(color: context.colors.textLight),
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openFromLink(context, controller.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  /// Parse a pasted meeting link or bare code and route to the right screen.
  void _openFromLink(BuildContext context, String raw) {
    final input = raw.trim();
    if (input.isEmpty) return;

    final uri = Uri.tryParse(input);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segs = uri.pathSegments;
      for (final key in const ['pre-join', 'live', 'recording', 'join-group']) {
        final idx = segs.indexOf(key);
        if (idx != -1 && idx + 1 < segs.length) {
          final id = segs[idx + 1];
          if (key == 'join-group') {
            context.push('/join-group/$id');
          } else {
            context.push('/pre-join/$id');
          }
          return;
        }
      }
    }

    // No recognizable path segment — treat the last token as a meeting code.
    final token = input.split('/').last.split('?').first.trim();
    if (token.isNotEmpty) {
      context.push('/pre-join/$token');
    }
  }

  Future<void> _startInstantMeeting(BuildContext context) async {
    final user = ref.read(appUserProvider);
    final meetingId = _newMeetingId('meet');
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
      isInstant: true,
    );
    try {
      await ref.read(firestoreRepositoryProvider).createMeeting(meeting).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Joining an unknown meeting is intentionally rejected by the server,
      // so never navigate into a room that failed to be created.
      debugPrint('Failed to create instant meeting doc: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start meeting: $e')),
        );
      }
      return;
    }
    if (context.mounted) {
      context.push('/pre-join/$meetingId', extra: {'title': meeting.title});
    }
  }

  Future<void> _startQuickRecording(BuildContext context) async {
    final user = ref.read(appUserProvider);
    final now = DateTime.now();
    final meeting = Meeting(
      id: _newMeetingId('audio'),
      title: 'Quick Recording',
      startTime: now,
      endTime: now.add(const Duration(hours: 1)),
      type: MeetingType.room,
      participants: [user],
      isInstant: true,
    );

    try {
      // The token endpoint intentionally refuses unknown meeting IDs. Creating
      // the document first also gives the resulting summary a real owner.
      await ref.read(firestoreRepositoryProvider).createMeeting(meeting).timeout(const Duration(seconds: 10));
      if (context.mounted) {
        context.push('/recording/${meeting.id}', extra: {
          'title': meeting.title,
          'participants': meeting.participants,
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }
}

/// A compact, tappable row used in "Needs your attention".
class _AttentionTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onCheckTap;

  const _AttentionTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onCheckTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: Row(
          children: [
            if (onCheckTap != null)
              GestureDetector(
                onTap: onCheckTap,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(icon, size: 22, color: accent),
                ),
              )
            else ...[
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMain, height: 1.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.textLight),
          ],
        ),
      ),
    );
  }
}

/// Compact topic (thread) card for the dashboard's "Recent topics" list.
class _RecentTopicCard extends ConsumerWidget {
  final ContextThread thread;

  const _RecentTopicCard({required this.thread});

  String _relativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w ago';
    final months = (diff.inDays / 30).floor();
    return '${months}mo ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = thread.blocks.isNotEmpty ? thread.blocks.first.content : null;

    return GestureDetector(
      onTap: () => context.push('/thread/${thread.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    thread.meetingTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textMain),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _relativeTime(thread.createdAt),
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: context.colors.textMuted),
                ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
