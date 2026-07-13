import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/meeting.dart';
import '../theme/app_theme.dart';
import 'avatar_stack.dart';

/// A card displaying meeting details, matching the Stitch Screen 1 design.
///
/// Shows title, time range, countdown badge (if within 60 min),
/// participant avatars, and meeting type badge.
class MeetingCard extends StatefulWidget {
  final Meeting meeting;
  final VoidCallback? onTap;

  const MeetingCard({
    super.key,
    required this.meeting,
    this.onTap,
  });

  @override
  State<MeetingCard> createState() => _MeetingCardState();
}

class _MeetingCardState extends State<MeetingCard>
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

                SizedBox(height: 16),

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

                if (isSoon) ...[
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.push('/recording/${meeting.id}', extra: {
                          'title': meeting.title,
                          'participants': meeting.participants,
                        });
                      },
                      icon: Icon(Icons.mic, size: 18),
                      label: Text('Start Session'),
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

                if (meeting.meetUrl != null) ...[
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(meeting.meetUrl!);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: Icon(Icons.video_call, size: 18),
                      label: Text('Join Google Meet'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.primary,
                        side: BorderSide(color: context.colors.primary.withValues(alpha: 0.5)),
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
