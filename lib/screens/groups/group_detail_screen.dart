import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/firestore_repository.dart';

import '../../models/group.dart';
import '../../models/context_thread.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/invite_member_dialog.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Group and threads will be read from ref in build()

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final threadsAsync = ref.watch(threadsProvider);

    return groupsAsync.when(
      data: (groups) {
        final group = groups.firstWhere(
          (g) => g.id == widget.groupId,
          orElse: () => Group(id: '', name: 'Not Found', members: [], threadIds: [], createdBy: AppUser(id: '', email: '', name: ''), createdAt: DateTime.now()),
        );

        if (group.id.isEmpty) {
          return Scaffold(body: Center(child: Text('Group not found')));
        }

        final threads = threadsAsync.maybeWhen(
          data: (ts) {
            final list = ts.where((t) => group.threadIds.contains(t.id)).toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          },
          orElse: () => <ContextThread>[],
        );

        return Scaffold(
          backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textMain),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              group.avatarEmoji ?? '👥',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                group.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Builder(builder: (context) {
            final selfId = ref.read(currentUserProvider)?.uid ?? '';
            final isAdmin = group.isAdmin(selfId);
            return PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.colors.textMain),
              onSelected: (value) async {
                if (value == 'edit') {
                  _editGroupName(context, ref, group);
                } else if (value == 'invite_link') {
                  _shareInviteLink(context, group);
                } else if (value == 'leave') {
                  _confirmLeaveGroup(context, ref, group);
                } else if (value == 'delete') {
                  _confirmDeleteGroup(context, ref, group);
                }
              },
              itemBuilder: (context) => [
                if (isAdmin) const PopupMenuItem(value: 'edit', child: Text('Edit Group')),
                const PopupMenuItem(value: 'invite_link', child: Text('Copy Invite Link')),
                const PopupMenuItem(value: 'leave', child: Text('Leave Group')),
                if (isAdmin)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Group', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            );
          }),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.colors.primary,
          unselectedLabelColor: context.colors.textMuted,
          indicatorColor: context.colors.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Threads'),
            Tab(text: 'Members'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ThreadsTab(threads: threads),
          _MembersTab(group: group),
          _AnalyticsTab(group: group, threads: threads),
        ],
      ),
    );
      },
      loading: () => Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }
}

Future<void> _editGroupName(BuildContext context, WidgetRef ref, Group group) async {
  final controller = TextEditingController(text: group.name);
  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Edit Group'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: 'Group name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text('Save'),
        ),
      ],
    ),
  );

  if (newName == null || newName.isEmpty || newName == group.name) return;

  try {
    await ref.read(firestoreRepositoryProvider).updateGroupName(group.id, newName);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename group: $e')),
      );
    }
  }
}

void _shareInviteLink(BuildContext context, Group group) {
  final link = 'https://meeting-app-844aa.web.app/join-group/${group.inviteCode}';
  Clipboard.setData(ClipboardData(text: link));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Invite link copied! Anyone who opens it can join this group.')),
  );
}

Future<void> _confirmDeleteGroup(BuildContext context, WidgetRef ref, Group group) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Group?'),
      content: Text(
        'This permanently deletes "${group.name}" for everyone. Past meeting summaries stay visible to '
        'the people who were in those meetings, but the group itself and its member list are gone. This can\'t be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('deleteGroup').call({'groupId': group.id});
    if (context.mounted) {
      context.go('/groups');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${group.name}".')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete group: $e')),
      );
    }
  }
}

Future<void> _confirmLeaveGroup(BuildContext context, WidgetRef ref, Group group) async {
  final selfId = ref.read(currentUserProvider)?.uid;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave Group?'),
      content: Text('You\'ll stop seeing meeting summaries from "${group.name}" unless someone invites you back.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirmed != true || selfId == null) return;

  try {
    await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('removeGroupMember').call({
      'groupId': group.id,
      'userId': selfId,
    });
    if (context.mounted) context.go('/groups');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }
}

Future<void> _setAdmin(BuildContext context, Group group, AppUser member, bool makeAdmin) async {
  try {
    await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('setGroupAdmin').call({
      'groupId': group.id,
      'userId': member.id,
      'makeAdmin': makeAdmin,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(makeAdmin ? 'Made ${member.name} an admin.' : 'Removed ${member.name} as admin.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update admin: $e')),
      );
    }
  }
}

Future<void> _confirmRemoveMember(BuildContext context, Group group, AppUser member) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove Member?'),
      content: Text('${member.name} will lose access to this group\'s meeting summaries.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('removeGroupMember').call({
      'groupId': group.id,
      'userId': member.id,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${member.name} from the group.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: $e')),
      );
    }
  }
}

// ─── THREADS TAB ─────────────────────────────────────────

class _ThreadsTab extends StatelessWidget {
  final List<ContextThread> threads;

  const _ThreadsTab({required this.threads});

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: context.colors.textLight),
            SizedBox(height: 12),
            Text(
              'No threads yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textMuted,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Meeting summaries will appear here',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.colors.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: threads.length,
      itemBuilder: (context, index) {
        final thread = threads[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _ThreadSummaryCard(thread: thread)
              .animate()
              .fadeIn(
                delay: Duration(milliseconds: 80 * index),
                duration: 350.ms,
              )
              .slideY(
                begin: 0.06,
                end: 0,
                delay: Duration(milliseconds: 80 * index),
                duration: 350.ms,
                curve: Curves.easeOut,
              ),
        );
      },
    );
  }
}

class _ThreadSummaryCard extends StatelessWidget {
  final ContextThread thread;

  const _ThreadSummaryCard({required this.thread});

  String _blockCountSummary() {
    int decisions = 0, actionItems = 0, insights = 0;
    for (final block in thread.blocks) {
      switch (block.type) {
        case SmartBlockType.summary:
          break;
        case SmartBlockType.decision:
          decisions++;
          break;
        case SmartBlockType.actionItem:
          actionItems++;
          break;
        case SmartBlockType.keyInsight:
          insights++;
          break;
      }
    }
    final parts = <String>[];
    if (decisions > 0) {
      parts.add('$decisions decision${decisions > 1 ? 's' : ''}');
    }
    if (actionItems > 0) {
      parts.add('$actionItems action item${actionItems > 1 ? 's' : ''}');
    }
    if (insights > 0) {
      parts.add('$insights insight${insights > 1 ? 's' : ''}');
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, y · h:mm a').format(thread.createdAt);

    return GestureDetector(
      onTap: () => context.push('/thread/${thread.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              thread.meetingTitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
              ),
            ),
            SizedBox(height: 4),
            Text(
              dateStr,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.textMuted,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _blockCountSummary(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.primary,
              ),
            ),
            SizedBox(height: 12),
            _buildAvatarStack(context, thread.participants),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack(BuildContext context, List<AppUser> users) {
    final display = users.take(4).toList();
    const double size = 30;
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

  Widget _miniInitials(BuildContext context, AppUser user) {
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

// ─── MEMBERS TAB ─────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final Group group;

  const _MembersTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfId = ref.watch(currentUserProvider)?.uid;
    final isSelfAdmin = selfId != null && group.isAdmin(selfId);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: group.members.length,
            itemBuilder: (context, index) {
              final member = group.members[index];
              final isAdmin = group.isAdmin(member.id);
              final isNew = group.isRecentMember(member.id);
              final isSelf = member.id == selfId;
              return _MemberRow(
                user: member,
                isAdmin: isAdmin,
                isNew: isNew,
                // Admins get a management menu on everyone except themselves.
                canManage: isSelfAdmin && !isSelf,
                onRemove: () => _confirmRemoveMember(context, group, member),
                onToggleAdmin: () => _setAdmin(context, group, member, !isAdmin),
              )
                  .animate()
                  .fadeIn(
                    delay: Duration(milliseconds: 60 * index),
                    duration: 300.ms,
                  )
                  .slideX(
                    begin: 0.05,
                    end: 0,
                    delay: Duration(milliseconds: 60 * index),
                    duration: 300.ms,
                    curve: Curves.easeOut,
                  );
            },
          ),
        ),
        // Invite / share buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareInviteLink(context, group),
                    icon: Icon(Icons.link_rounded, size: 20),
                    label: Text(
                      'Share Link',
                      style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.primary,
                      side: BorderSide(color: context.colors.primary, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => InviteMemberDialog(group: group),
                      );
                    },
                    icon: Icon(Icons.person_add_outlined, size: 20),
                    label: Text(
                      'Invite',
                      style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final AppUser user;
  final bool isAdmin;
  final bool isNew;
  final bool canManage;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleAdmin;

  const _MemberRow({
    required this.user,
    required this.isAdmin,
    this.isNew = false,
    this.canManage = false,
    this.onRemove,
    this.onToggleAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primaryLight,
                border: Border.all(color: context.colors.border, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: user.avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _initials(context),
                      errorWidget: (context, url, error) => _initials(context),
                    )
                  : _initials(context),
            ),
            SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMain,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    user.email,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Badges
            if (isNew) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'New',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ),
              SizedBox(width: 8),
            ],
            if (isAdmin)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.accentLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'Admin',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.accent,
                  ),
                ),
              ),
            if (canManage)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: context.colors.textMuted),
                onSelected: (v) {
                  if (v == 'toggle_admin') {
                    onToggleAdmin?.call();
                  } else if (v == 'remove') {
                    onRemove?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle_admin',
                    child: Text(isAdmin ? 'Remove as admin' : 'Make admin'),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove from group', style: TextStyle(color: context.colors.error)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _initials(BuildContext context) {
    return Center(
      child: Text(
        user.initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
        ),
      ),
    );
  }
}

// ─── ANALYTICS TAB ───────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  final Group group;
  final List<ContextThread> threads;

  const _AnalyticsTab({required this.group, required this.threads});

  @override
  Widget build(BuildContext context) {
    final allDecisions = <SmartBlock>[];
    final allActionItems = <SmartBlock>[];

    for (final t in threads) {
      allDecisions.addAll(t.blocks.where((b) => b.type == SmartBlockType.decision));
      allActionItems.addAll(t.blocks.where((b) => b.type == SmartBlockType.actionItem));
    }

    final totalTasks = allActionItems.length;
    final completedTasks = allActionItems.where((b) => b.isCompleted).length;
    final taskProgress = totalTasks > 0 ? (completedTasks / totalTasks) : 0.0;
    final taskPct = (taskProgress * 100).toInt();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 1. High-level metric tiles
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                context,
                icon: Icons.forum_rounded,
                label: 'Meetings',
                value: '${threads.length}',
                color: const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                context,
                icon: Icons.gavel_rounded,
                label: 'Decisions',
                value: '${allDecisions.length}',
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                context,
                icon: Icons.group_rounded,
                label: 'Members',
                value: '${group.members.length}',
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2. Action Items Progress Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.colors.border.withValues(alpha: 0.6)),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.task_alt_rounded, size: 18, color: context.colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Group Action Items',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textMain,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    totalTasks == 0 ? 'No tasks yet' : '$completedTasks of $totalTasks ($taskPct%)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: taskProgress,
                  minHeight: 8,
                  backgroundColor: context.colors.border.withValues(alpha: 0.3),
                  color: context.colors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 3. Recent Decisions List
        Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 18, color: context.colors.primary),
            const SizedBox(width: 8),
            Text(
              'KEY GROUP DECISIONS (${allDecisions.length})',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.colors.textMuted,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (allDecisions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
            ),
            child: Text(
              'No decisions recorded for this group yet.',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13),
            ),
          )
        else
          ...allDecisions.take(10).map((d) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 12, color: Color(0xFFF59E0B)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.content,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textMain,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.6)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.colors.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
