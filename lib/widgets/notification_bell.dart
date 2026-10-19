import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../models/meeting.dart';
import '../providers/auth_provider.dart';
import '../providers/data_providers.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

enum NotificationFilter { all, unread, invites }

/// Bell icon with an unread-count badge and interactive notifications panel.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <AppNotification>[],
        );
    final unreadCount = notifications.where((n) => !n.isRead).length;

    return GestureDetector(
      onTap: () => _showPanel(context, ref),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.surface,
          shape: BoxShape.circle,
          boxShadow: AppShadows.card,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(Icons.notifications_outlined, size: 22, color: context.colors.textMain),
            ),
            if (unreadCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPanel(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationPanel(),
    );
  }
}

class _NotificationPanel extends ConsumerStatefulWidget {
  const _NotificationPanel();

  @override
  ConsumerState<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends ConsumerState<_NotificationPanel> {
  NotificationFilter _selectedFilter = NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final uid = ref.watch(currentUserProvider)?.uid;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMain,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.done_all_rounded, size: 20, color: context.colors.primary),
                      tooltip: 'Mark all as read',
                      onPressed: () {
                        if (uid != null) {
                          final notifications = notificationsAsync.value ?? [];
                          final repo = ref.read(firestoreRepositoryProvider);
                          for (final n in notifications) {
                            if (!n.isRead) repo.markNotificationRead(uid, n.id);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('All notifications marked as read')),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: context.colors.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Chips Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('All', NotificationFilter.all),
                _buildFilterChip('Unread', NotificationFilter.unread),
                _buildFilterChip('Invites', NotificationFilter.invites),
              ],
            ),
          ),
          const SizedBox(height: 6),

          Flexible(
            child: notificationsAsync.when(
              data: (allNotifications) {
                final filtered = allNotifications.where((n) {
                  switch (_selectedFilter) {
                    case NotificationFilter.unread:
                      return !n.isRead;
                    case NotificationFilter.invites:
                      return n.type == 'group_invite' ||
                          n.type == 'meeting_invite' ||
                          n.title.toLowerCase().contains('invite') ||
                          n.body.toLowerCase().contains('invite');
                    case NotificationFilter.all:
                      return true;
                  }
                }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 40,
                            color: context.colors.textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedFilter == NotificationFilter.unread
                                ? 'No unread notifications'
                                : 'No notifications in this filter',
                            style: GoogleFonts.plusJakartaSans(
                              color: context.colors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = filtered[index];
                    return _NotificationCard(notification: n, uid: uid)
                        .animate()
                        .fadeIn(duration: 300.ms, delay: (20 * index).ms)
                        .slideY(begin: 0.05, end: 0);
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, NotificationFilter filter) {
    final isSelected = _selectedFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: context.colors.primaryLight,
        onSelected: (_) => setState(() => _selectedFilter = filter),
        labelStyle: TextStyle(
          color: isSelected ? context.colors.primary : context.colors.textMain,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final AppNotification notification;
  final String? uid;

  const _NotificationCard({required this.notification, required this.uid});

  bool get _isMeetingInvite =>
      notification.type == 'meeting_invite' ||
      notification.title.toLowerCase().contains('meeting invite') ||
      (notification.route != null && notification.route!.startsWith('/pre-join/'));

  bool get _isGroupInvite =>
      notification.type == 'group_invite' ||
      notification.title.toLowerCase().contains('group invite');

  String? get _extractedMeetingId {
    if (notification.relatedId != null && notification.relatedId!.isNotEmpty) {
      return notification.relatedId;
    }
    if (notification.route != null && notification.route!.contains('/pre-join/')) {
      return notification.route!.split('/pre-join/').last.split('?').first;
    }
    return null;
  }

  String? get _extractedGroupId {
    if (notification.relatedId != null && notification.relatedId!.isNotEmpty) {
      return notification.relatedId;
    }
    if (notification.route != null && notification.route!.contains('/group/')) {
      return notification.route!.split('/group/').last.split('?').first;
    }
    return null;
  }

  Future<void> _respondMeetingRsvp(BuildContext context, WidgetRef ref, RsvpStatus status) async {
    if (uid == null) return;
    final meetingId = _extractedMeetingId;
    if (meetingId == null) return;

    try {
      await ref.read(firestoreRepositoryProvider).setMeetingRsvp(meetingId, uid!, status);
      await ref.read(firestoreRepositoryProvider).markNotificationRead(uid!, notification.id);
      if (context.mounted) {
        String statusLabel;
        switch (status) {
          case RsvpStatus.yes:
            statusLabel = 'Going';
            break;
          case RsvpStatus.maybe:
            statusLabel = 'Maybe';
            break;
          case RsvpStatus.no:
            statusLabel = 'Can\'t go';
            break;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP updated to "$statusLabel"')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update RSVP: $e')),
        );
      }
    }
  }

  Future<void> _respondGroupInvite(BuildContext context, WidgetRef ref, bool accept) async {
    if (uid == null) return;
    final groupId = _extractedGroupId;
    if (groupId == null) return;

    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('respondToGroupInvite')
          .call({
        'groupId': groupId,
        'accept': accept,
      });
      await ref.read(firestoreRepositoryProvider).markNotificationRead(uid!, notification.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'Joined group!' : 'Invite declined')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error responding to invite: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final meetingId = _extractedMeetingId;
    final meetings = ref.watch(meetingsProvider).value ?? [];
    final meeting = meetingId != null
        ? meetings.cast<Meeting?>().firstWhere((m) => m?.id == meetingId, orElse: () => null)
        : null;

    final isMeetingPast = meeting?.isPast ?? false;

    return InkWell(
      onTap: () {
        if (uid != null && !n.isRead) {
          ref.read(firestoreRepositoryProvider).markNotificationRead(uid!, n.id);
        }
        Navigator.of(context).pop();

        if (isMeetingPast) {
          if (meeting?.threadId != null) {
            context.push('/thread/${meeting!.threadId}');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This meeting has already concluded.')),
            );
          }
        } else if (n.route != null) {
          context.push(n.route!);
        }
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: n.isRead ? context.colors.surface : context.colors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: n.isRead
                ? context.colors.border.withValues(alpha: 0.5)
                : context.colors.primary.withValues(alpha: 0.4),
            width: n.isRead ? 1 : 1.5,
          ),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: n.isRead ? Colors.transparent : context.colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                                fontSize: 14,
                                color: context.colors.textMain,
                              ),
                            ),
                          ),
                          if (_isMeetingInvite && isMeetingPast) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.colors.background,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: context.colors.border),
                              ),
                              child: Text(
                                'MISSED / ENDED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: context.colors.textMuted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, h:mm a').format(n.createdAt),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: context.colors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Inline RSVP Handling for Meeting Invites
            if (_isMeetingInvite && meetingId != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              if (isMeetingPast)
                // When meeting has passed: show Missed/Concluded status and View Summary option
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 14, color: context.colors.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Invite expired · Meeting ended',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (meeting?.threadId != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push('/thread/${meeting!.threadId}');
                        },
                        icon: const Icon(Icons.description_outlined, size: 14),
                        label: const Text('View Summary', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          foregroundColor: context.colors.primary,
                        ),
                      ),
                  ],
                )
              else
                // When meeting is upcoming/live: show Active Quick RSVP options
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Quick RSVP: ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.colors.textMuted),
                      ),
                      const SizedBox(width: 6),
                      _buildRsvpChip(
                        context,
                        label: 'Going',
                        icon: Icons.check,
                        color: const Color(0xFF10B981),
                        onTap: () => _respondMeetingRsvp(context, ref, RsvpStatus.yes),
                      ),
                      const SizedBox(width: 6),
                      _buildRsvpChip(
                        context,
                        label: 'Maybe',
                        icon: Icons.help_outline,
                        color: const Color(0xFFF59E0B),
                        onTap: () => _respondMeetingRsvp(context, ref, RsvpStatus.maybe),
                      ),
                      const SizedBox(width: 6),
                      _buildRsvpChip(
                        context,
                        label: 'Decline',
                        icon: Icons.close,
                        color: Colors.redAccent,
                        onTap: () => _respondMeetingRsvp(context, ref, RsvpStatus.no),
                      ),
                    ],
                  ),
                ),
            ],

            // Inline Quick Response for Group Invites
            if (_isGroupInvite && _extractedGroupId != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _respondGroupInvite(context, ref, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      side: BorderSide(color: context.colors.border),
                    ),
                    child: const Text('Decline', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _respondGroupInvite(context, ref, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRsvpChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
