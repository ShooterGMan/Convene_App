import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meeting.dart';
import '../providers/data_providers.dart';
import '../theme/app_theme.dart';

/// A prominent banner surfacing the single most-imminent meeting - either one
/// that's live right now or starting within the next 15 minutes - with a
/// one-tap Join. This is the app's "starting soon" nudge; there's no push
/// system, so it only shows while the app is open, but it's actionable right
/// where the user lands. Re-evaluates on a timer so the countdown stays live.
class LiveSoonBanner extends ConsumerStatefulWidget {
  const LiveSoonBanner({super.key});

  @override
  ConsumerState<LiveSoonBanner> createState() => _LiveSoonBannerState();
}

class _LiveSoonBannerState extends ConsumerState<LiveSoonBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh once a minute so "starts in N min" and the live/soon cutoff
    // stay accurate without depending on a new Firestore emission.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Meeting? _pickImminent(List<Meeting> meetings) {
    final candidates = meetings.where((m) {
      if (m.isLive) return true;
      final mins = m.minutesUntil;
      return mins != null && mins >= 0 && mins <= 15;
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    // Prefer a live meeting, otherwise the soonest upcoming one.
    final live = candidates.where((m) => m.isLive).toList();
    if (live.isNotEmpty) return live.first;
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final meetings = ref.watch(meetingsProvider).maybeWhen(
          data: (m) => m,
          orElse: () => const <Meeting>[],
        );
    final meeting = _pickImminent(meetings);
    if (meeting == null) return const SizedBox.shrink();

    final isLive = meeting.isLive;
    final mins = meeting.minutesUntil ?? 0;
    final label = isLive ? 'LIVE NOW' : (mins <= 0 ? 'STARTING NOW' : 'STARTS IN $mins MIN');

    void join() {
      if (meeting.type == MeetingType.meet) {
        context.push('/pre-join/${meeting.id}', extra: {
          'title': meeting.title,
          'participants': meeting.participants,
          'groupId': meeting.groupId,
        });
      } else {
        context.push('/recording/${meeting.id}', extra: {
          'title': meeting.title,
          'participants': meeting.participants,
          'groupId': meeting.groupId,
        });
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.colors.primary, context.colors.primary.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          if (isLive)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms).then().fadeOut(duration: 600.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  meeting.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton(
            onPressed: join,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: context.colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
            child: Text(
              meeting.type == MeetingType.meet ? 'Join' : 'Record',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }
}
