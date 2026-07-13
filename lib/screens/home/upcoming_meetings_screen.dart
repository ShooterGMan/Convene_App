import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';

import '../../models/context_thread.dart';
import '../../models/meeting.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meeting_card.dart';
import '../../widgets/schedule_meeting_sheet.dart';

/// The home/dashboard screen showing upcoming meetings grouped by date.
///
/// Matches Stitch Screen 1 with greeting header, sync status pill,
/// date section headers, and a scrollable list of meeting cards.
class UpcomingMeetingsScreen extends ConsumerWidget {
  const UpcomingMeetingsScreen({super.key});

  /// Group meetings by calendar date.
  Map<DateTime, List<Meeting>> _groupByDate(List<Meeting> meetings) {
    final Map<DateTime, List<Meeting>> grouped = {};
    for (final meeting in meetings) {
      final dateKey = DateTime(
        meeting.startTime.year,
        meeting.startTime.month,
        meeting.startTime.day,
      );
      grouped.putIfAbsent(dateKey, () => []).add(meeting);
    }
    // Sort each group by start time
    for (final list in grouped.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Produce a human-friendly date header like 'Today, Jun 24' or 'Tomorrow, Jun 25'.
  String _dateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final formattedDate = DateFormat('MMM d').format(date);

    if (date == today) {
      return 'Today, $formattedDate';
    } else if (date == tomorrow) {
      return 'Tomorrow, $formattedDate';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  /// Get a time-of-day-aware greeting.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfUser = ref.watch(appUserProvider);
    final meetingsAsync = ref.watch(meetingsProvider);
    final threadsAsync = ref.watch(threadsProvider);

    // Build a flat list of widgets: headers interspersed with cards.
    final List<Widget> sliverChildren = meetingsAsync.when(
      data: (meetings) {
        final groupedMeetings = _groupByDate(meetings);
        if (groupedMeetings.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.colors.primaryLight.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_available, size: 48, color: context.colors.primary),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'No upcoming meetings',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your schedule is clear! Take a breather or schedule your next big sync.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: context.colors.textMuted,
                      height: 1.5,
                    ),
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
            )
          ];
        }
        
        final List<Widget> children = [];
        int cardIndex = 0;

        for (final entry in groupedMeetings.entries) {
          // Date header
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 24, bottom: 12),
              child: Text(
                _dateHeader(entry.key),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            )
                .animate()
                .fadeIn(
                  delay: (cardIndex * 80).ms,
                  duration: 400.ms,
                ),
          );

          // Meeting cards
          for (final meeting in entry.value) {
            final delay = (cardIndex * 80).ms;
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MeetingCard(meeting: meeting)
                    .animate()
                    .fadeIn(
                      delay: delay,
                      duration: 500.ms,
                    )
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 500.ms,
                      delay: delay,
                      curve: Curves.easeOut,
                    ),
              ),
            );
            cardIndex++;
          }
        }
        return children;
      },
      loading: () => [
        Padding(
          padding: const EdgeInsets.all(48.0),
          child: Center(
            child: CircularProgressIndicator(color: context.colors.primary),
          ),
        )
      ],
      error: (e, st) => [
        Padding(
          padding: const EdgeInsets.all(48.0),
          child: Center(
            child: Text('Error loading meetings: $e',
                style: TextStyle(color: context.colors.textMuted)),
          ),
        )
      ],
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const ScheduleMeetingSheet(),
          );
        },
        backgroundColor: context.colors.primary,
        icon: Icon(Icons.add, color: Colors.white),
        label: Text(
          'Schedule',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ).animate().scale(delay: 600.ms, duration: 400.ms, curve: Curves.easeOutBack),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // Header area
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    Text(
                      '${_greeting()}, ${selfUser.name.split(' ').first}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                        height: 1.2,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideX(
                          begin: -0.03,
                          end: 0,
                          duration: 500.ms,
                          curve: Curves.easeOut,
                        ),

                    SizedBox(height: 12),

                    // Sync status pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.border.withValues(alpha: 0.5),
                        borderRadius:
                            BorderRadius.circular(AppRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            size: 14,
                            color: context.colors.textMuted,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Synced just now',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 400.ms),

                    SizedBox(height: 32),

                    // My Tasks Section
                    Text(
                      'My Tasks',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                    SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // My Tasks List
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
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

            // Meeting list
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate(sliverChildren),
              ),
            ),
          ],
        ),
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
            if (block.type == SmartBlockType.actionItem && 
               (block.assignee == myFirstName || block.assignee == 'Sarah' || block.assignee == 'Anon') && 
               !block.isCompleted) {
              final delay = (index * 100).ms;
              cards.add(
                Container(
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
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.colors.textMuted,
                              ),
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
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textMain,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
              child: Text(
                'No pending tasks!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: context.colors.textMuted,
                ),
              ),
            )
          ];
        }
        return cards;
      },
      loading: () => [Center(child: CircularProgressIndicator(color: context.colors.primary))],
      error: (e, st) => [Center(child: Text('Error: $e'))],
    );
  }
}
