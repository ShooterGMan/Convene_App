import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../providers/auth_provider.dart';
import '../providers/data_providers.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

/// Bell icon with an unread-count badge, shown persistently above every tab
/// (see AppShell) so notifications - group invites, invite responses, being
/// added to a meeting - are visible no matter where the user currently is
/// in the app, not just on the screen the underlying data happens to live on.
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

class _NotificationPanel extends ConsumerWidget {
  const _NotificationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final uid = ref.watch(currentUserProvider)?.uid;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.textMain),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.colors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: notificationsAsync.when(
              data: (notifications) {
                if (notifications.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'No notifications yet',
                        style: GoogleFonts.plusJakartaSans(color: context.colors.textMuted),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    return ListTile(
                      leading: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: n.isRead ? Colors.transparent : context.colors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        n.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                          fontSize: 14,
                          color: context.colors.textMain,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.body, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted)),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('MMM d, h:mm a').format(n.createdAt),
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: context.colors.textLight),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (uid != null && !n.isRead) {
                          ref.read(firestoreRepositoryProvider).markNotificationRead(uid, n.id);
                        }
                        Navigator.of(context).pop();
                        if (n.route != null) context.push(n.route!);
                      },
                    );
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
}
