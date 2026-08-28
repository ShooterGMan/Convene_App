import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../models/meeting.dart';
import '../providers/auth_provider.dart';
import '../providers/data_providers.dart';
import '../repositories/firestore_repository.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';
import 'avatar_stack.dart';

/// A card displaying meeting details, matching the Stitch Screen 1 design.
///
/// Shows title, time range, countdown badge (if within 60 min),
/// participant avatars, and meeting type badge.
class MeetingCard extends ConsumerStatefulWidget {
  final Meeting meeting;
  final VoidCallback? onTap;

  const MeetingCard({
    super.key,
    required this.meeting,
    this.onTap,
  });

  @override
  ConsumerState<MeetingCard> createState() => _MeetingCardState();
}

class _MeetingCardState extends ConsumerState<MeetingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _scaleController.forward();
  void _onTapUp(TapUpDetails _) => _scaleController.reverse();
  void _onTapCancel() => _scaleController.reverse();

  /// Format a time of day from DateTime, e.g. '10:00 AM'
  String _formatTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  /// Returns the countdown label, e.g. 'IN 15M', or null if not within 60 min.
  String? _countdownLabel() {
    final mins = widget.meeting.minutesUntil;
    if (mins == null || mins > 60) return null;
    if (mins <= 0) return null;
    return 'IN ${mins}M';
  }

  /// Whether this meeting is "soon" (within 60 min and not yet started).
  bool get _isUpcomingSoon {
    final mins = widget.meeting.minutesUntil;
    return mins != null && mins <= 60 && mins > 0;
  }

  /// Get the proper IconData for the meeting type.
  IconData _typeIconData() {
    switch (widget.meeting.type) {
      case MeetingType.meet:
        return Icons.videocam_rounded;
      case MeetingType.room:
        return Icons.domain_rounded;
      case MeetingType.audio:
        return Icons.call_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final countdown = _countdownLabel();
    final isSoon = _isUpcomingSoon || meeting.isLive;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: isSoon ? 1.0 : 0.7,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + countdown row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        meeting.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textMain,
                        ),
                      ),
                    ),
                    if (countdown != null) ...[
                      SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          countdown,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                SizedBox(height: 8),

                // Time range row
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: context.colors.textMuted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '${_formatTime(meeting.startTime)} – ${_formatTime(meeting.endTime)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),

                if (meeting.summaryError != null && meeting.threadId == null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: context.colors.error),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Summary failed to generate for this meeting. Take your own notes if needed.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (meeting.summaryStatus == 'processing' && meeting.threadId == null) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.primary,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Generating your meeting summary…',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (meeting.agenda.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.colors.background,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.format_list_bulleted_rounded, size: 14, color: context.colors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Agenda (${meeting.agenda.length}): ${meeting.agenda.first}${meeting.agenda.length > 1 ? ' +${meeting.agenda.length - 1} more' : ''}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Avatars + type badge row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AvatarStack(users: meeting.participants),
                    _MeetingTypeBadge(
                      icon: _typeIconData(),
                      label: meeting.typeLabel,
                    ),
                  ],
                ),

                // RSVP: only makes sense for group meetings that haven't
                // happened yet - attendance polling for something already
                // over is meaningless.
                if (meeting.groupId != null && !meeting.isPast) ...[
                  SizedBox(height: 14),
                  _RsvpRow(meeting: meeting),
                ],

                if (isSoon) ...[
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (meeting.type == MeetingType.meet) {
                          // Online Meeting: Route to Pre-Join Room
                          context.push('/pre-join/${meeting.id}', extra: {
                            'title': meeting.title,
                            'participants': meeting.participants,
                            'groupId': meeting.groupId,
                          });
                        } else {
                          // Offline Meeting: Route to Recording Screen
                          context.push('/recording/${meeting.id}', extra: {
                            'title': meeting.title,
                            'participants': meeting.participants,
                            'groupId': meeting.groupId,
                          });
                        }
                      },
                      icon: Icon(
                        meeting.type == MeetingType.meet ? Icons.video_call : Icons.mic, 
                        size: 18,
                      ),
                      label: Text(
                        meeting.type == MeetingType.meet ? 'Join Online Room' : 'Record Session',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        textStyle: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                
                if (!meeting.isPast) ...[
                  SizedBox(height: 12),
                  Row(
                    children: [
                      if (meeting.type == MeetingType.meet) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final inviteLink = 'https://meeting-app-844aa.web.app/pre-join/${meeting.id}';
                              Clipboard.setData(ClipboardData(text: inviteLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invite Link Copied!')),
                              );
                            },
                            icon: Icon(Icons.copy, size: 16),
                            label: Text('Copy Link'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.primary,
                              side: BorderSide(color: context.colors.primary.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              textStyle: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            CalendarService.showAddToCalendarSheet(context, meeting: meeting);
                          },
                          icon: Icon(Icons.calendar_month_rounded, size: 16),
                          label: Text('Add to Calendar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.textMain,
                            side: BorderSide(color: context.colors.textMuted.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                            textStyle: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

/// Yes/No/Maybe attendance row with live tallies. Tapping your own status
/// again clears it (no self-deletion of others' entries is possible - the
/// Firestore rules only allow writing your own key in the rsvps map).
class _RsvpRow extends ConsumerWidget {
  final Meeting meeting;

  const _RsvpRow({required this.meeting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    final myStatus = uid == null ? null : meeting.rsvpFor(uid);

    Future<void> setStatus(RsvpStatus status) async {
      if (uid == null) return;
      try {
        await ref.read(firestoreRepositoryProvider).setMeetingRsvp(meeting.id, uid, status);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to RSVP: $e')),
          );
        }
      }
    }

    final totalResponses = meeting.rsvps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Attending?',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textMuted),
            ),
            const Spacer(),
            _RsvpChip(
              label: 'Yes',
              count: meeting.yesCount,
              isSelected: myStatus == RsvpStatus.yes,
              color: Colors.green,
              onTap: () => setStatus(RsvpStatus.yes),
            ),
            SizedBox(width: 6),
            _RsvpChip(
              label: 'Maybe',
              count: meeting.maybeCount,
              isSelected: myStatus == RsvpStatus.maybe,
              color: Colors.orange,
              onTap: () => setStatus(RsvpStatus.maybe),
            ),
            SizedBox(width: 6),
            _RsvpChip(
              label: 'No',
              count: meeting.noCount,
              isSelected: myStatus == RsvpStatus.no,
              color: Colors.redAccent,
              onTap: () => setStatus(RsvpStatus.no),
            ),
          ],
        ),
        if (totalResponses > 0) ...[
          SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showBreakdown(context, ref),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt_rounded, size: 13, color: context.colors.primary),
                SizedBox(width: 5),
                Text(
                  'See who\'s responded ($totalResponses)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.primary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showBreakdown(BuildContext context, WidgetRef ref) {
    // Resolve responder UIDs to names using the meeting's own participants
    // plus (for group meetings) the group's member list, since group members
    // can RSVP without being explicit participants.
    final nameById = <String, String>{};
    for (final p in meeting.participants) {
      nameById[p.id] = p.name;
    }
    final groups = ref.read(groupsProvider).maybeWhen(data: (g) => g, orElse: () => const <Group>[]);
    if (meeting.groupId != null) {
      for (final g in groups) {
        if (g.id == meeting.groupId) {
          for (final m in g.members) {
            nameById.putIfAbsent(m.id, () => m.name);
          }
        }
      }
    }

    List<String> namesFor(bool Function(String) pred) => meeting.rsvps.entries
        .where((e) => pred(e.value))
        .map((e) => nameById[e.key] ?? 'Someone')
        .toList()
      ..sort();

    final going = namesFor((v) => v == 'yes');
    final maybe = namesFor((v) => v == 'maybe');
    final cant = namesFor((v) => v == 'no');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance · ${meeting.title}',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: context.colors.textMain),
            ),
            SizedBox(height: 16),
            _RsvpGroup(label: 'Going', color: Colors.green, names: going),
            _RsvpGroup(label: 'Maybe', color: Colors.orange, names: maybe),
            _RsvpGroup(label: "Can't make it", color: Colors.redAccent, names: cant),
          ],
        ),
      ),
    );
  }
}

class _RsvpGroup extends StatelessWidget {
  final String label;
  final Color color;
  final List<String> names;

  const _RsvpGroup({required this.label, required this.color, required this.names});

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              SizedBox(width: 8),
              Text(
                '$label (${names.length})',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: context.colors.textMain),
              ),
            ],
          ),
          SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              names.join(', '),
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _RsvpChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _RsvpChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : context.colors.background,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: isSelected ? color : context.colors.border),
        ),
        child: Text(
          count > 0 ? '$label ($count)' : label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? color : context.colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Small badge showing the meeting type icon and label.
class _MeetingTypeBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MeetingTypeBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.textMuted),
          SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
