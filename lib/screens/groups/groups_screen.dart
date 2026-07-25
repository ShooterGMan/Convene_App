import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/data_providers.dart';

import '../../models/group.dart';
import '../../models/group_invite.dart';
import '../../theme/app_theme.dart';
import '../../widgets/create_group_sheet.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Groups',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    _CreateGroupButton(),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: _PendingInvitesSection()),

            // Group cards
            groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.colors.primaryLight.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.groups_rounded, size: 48, color: context.colors.primary),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Create your first group',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textMain,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Groups are where meeting summaries live. Everyone in a group automatically sees the AI recap for every meeting held under it.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: context.colors.textMuted,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => const CreateGroupSheet(),
                              );
                            },
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Create Group'),
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
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final group = groups[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _GroupCard(group: group)
                              .animate()
                              .fadeIn(
                                delay: Duration(milliseconds: 80 * index),
                                duration: 400.ms,
                              )
                              .slideY(
                                begin: 0.08,
                                end: 0,
                                delay: Duration(milliseconds: 80 * index),
                                duration: 400.ms,
                                curve: Curves.easeOut,
                              ),
                        );
                      },
                      childCount: groups.length,
                    ),
                  ),
                );
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
                  child: Center(child: Text('Error: $e')),
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _CreateGroupButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const CreateGroupSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: AppShadows.diffused,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Create Group',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PENDING INVITES ────────────────────────────────────
class _PendingInvitesSection extends ConsumerWidget {
  const _PendingInvitesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitesAsync = ref.watch(pendingInvitesProvider);

    return invitesAsync.maybeWhen(
      data: (invites) {
        if (invites.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invites.length == 1 ? '1 Pending Invite' : '${invites.length} Pending Invites',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: 10),
              ...invites.map((invite) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InviteCard(invite: invite),
                  )),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms);
      },
      error: (e, st) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: GestureDetector(
          // Firestore's realtime listener terminates permanently on error and
          // won't retry itself - invalidating the provider forces a fresh
          // subscription instead of requiring a full app restart.
          onTap: () => ref.invalidate(pendingInvitesProvider),
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 14, color: context.colors.error),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Couldn\'t load invites: $e (tap to retry)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.error),
                ),
              ),
            ],
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  final GroupInvite invite;

  const _InviteCard({required this.invite});

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _isResponding = false;

  Future<void> _respond(bool accept) async {
    setState(() => _isResponding = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('respondToGroupInvite').call({
        'groupId': widget.invite.groupId,
        'accept': accept,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'Joined ${widget.invite.groupName}!' : 'Invite declined.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResponding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to respond: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.primaryLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(invite.groupAvatarEmoji ?? '👥', style: TextStyle(fontSize: 24)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.groupName,
                  style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textMain),
                ),
                Text(
                  'Invited by ${invite.invitedBy.name}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted),
                ),
              ],
            ),
          ),
          if (_isResponding)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            IconButton(
              icon: Icon(Icons.close_rounded, color: context.colors.textMuted),
              tooltip: 'Decline',
              onPressed: () => _respond(false),
            ),
            IconButton(
              icon: Icon(Icons.check_circle_rounded, color: context.colors.primary),
              tooltip: 'Accept',
              onPressed: () => _respond(true),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final Group group;

  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(threadsProvider);
    final threads = threadsAsync.maybeWhen(
      data: (allThreads) => allThreads.where((t) => group.threadIds.contains(t.id)).toList(),
      orElse: () => [],
    );

    return GestureDetector(
      onTap: () => context.push('/group/${group.id}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Center(
                child: Text(
                  group.avatarEmoji ?? '👥',
                  style: TextStyle(fontSize: 28),
                ),
              ),
            ),
            SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    group.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                    ),
                  ),
                  if (group.description != null) ...[
                    SizedBox(height: 4),
                    Text(
                      group.description!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textMuted,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: 12),
                  // Bottom row: members + thread count
                  Row(
                    children: [
                      // Member avatar stack
                      _buildAvatarStack(context, group.members),
                      SizedBox(width: 8),
                      Text(
                        '${group.memberCount} members',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      // Thread count pill
                      if (threads.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.colors.primaryLight,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '${threads.length} thread${threads.length == 1 ? '' : 's'}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack(BuildContext context, List members) {
    final display = members.take(4).toList();
    const double size = 28;
    const double overlap = 8;

    return SizedBox(
      width: size + (display.length - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: List.generate(display.length, (i) {
          final user = display[i];
          return Positioned(
            left: i * (size - overlap),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.surface, width: 2),
                color: context.colors.primaryLight,
              ),
              clipBehavior: Clip.antiAlias,
              child: user.avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _miniInitials(context, user),
                      errorWidget: (context, url, error) => _miniInitials(context, user),
                    )
                  : _miniInitials(context, user),
            ),
          );
        }),
      ),
    );
  }

  Widget _miniInitials(BuildContext context, dynamic user) {
    return Center(
      child: Text(
        user.initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
        ),
      ),
    );
  }
}
