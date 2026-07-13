import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/firestore_repository.dart';

import '../../models/group.dart';
import '../../theme/app_theme.dart';

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

            // Group cards
            groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Text(
                          'No groups found',
                          style: GoogleFonts.plusJakartaSans(color: context.colors.textMuted),
                        ),
                      ),
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

class _CreateGroupButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final repo = ref.read(firestoreRepositoryProvider);
        final selfUser = ref.read(appUserProvider);
        final newGroup = Group(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}',
          name: 'New Test Group',
          description: 'A dynamically created group',
          avatarEmoji: '🚀',
          members: [selfUser],
          threadIds: [],
          createdBy: selfUser,
          createdAt: DateTime.now(),
        );
        await repo.createGroup(newGroup);
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Created ${newGroup.name}')),
           );
        }
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
