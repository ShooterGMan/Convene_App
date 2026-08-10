import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_notification.dart';
import '../providers/data_providers.dart';
import '../theme/app_theme.dart';

/// Custom bottom navigation bar matching the Stitch design.
///
/// Four tabs: Upcoming, Threads, Groups, Settings.
/// Active tab uses [context.colors.primary], inactive uses [context.colors.textMuted].
/// White surface with rounded top corners (32px) and a subtle top shadow.
class ConveneBottomNavBar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ConveneBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingInvitesCount = ref.watch(pendingInvitesProvider).maybeWhen(
          data: (invites) => invites.length,
          orElse: () => 0,
        );
    final notifications = ref.watch(notificationsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <AppNotification>[],
        );
    final unreadGroupNotifications = notifications
        .where((n) => !n.isRead && n.type != 'group_invite' && (n.route?.startsWith('/group') ?? false))
        .length;
    final unreadMeetingNotifications = notifications.where((n) => !n.isRead && n.type == 'meeting_added').length;

    final groupsBadgeCount = pendingInvitesCount + unreadGroupNotifications;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
        boxShadow: AppShadows.bottomNav,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavTab(
                icon: Icons.calendar_today,
                activeIcon: Icons.calendar_today,
                label: 'UPCOMING',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
                badgeCount: unreadMeetingNotifications,
              ),
              _NavTab(
                icon: Icons.forum_outlined,
                activeIcon: Icons.forum_rounded,
                label: 'TOPICS',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavTab(
                icon: Icons.people_outline,
                activeIcon: Icons.people,
                label: 'GROUPS',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
                badgeCount: groupsBadgeCount,
              ),
              _NavTab(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'SETTINGS',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? context.colors.primary : context.colors.textMuted;
    final displayIcon = isActive ? activeIcon : icon;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(displayIcon, size: 24, color: color),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.colors.surface, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
