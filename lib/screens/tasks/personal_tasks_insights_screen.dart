import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/context_thread.dart';
import '../../models/meeting.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';

enum TaskStatusFilter { all, todo, completed }

/// Unified Action Items Hub & Personal Productivity Insights Dashboard.
class PersonalTasksInsightsScreen extends ConsumerStatefulWidget {
  const PersonalTasksInsightsScreen({super.key});

  @override
  ConsumerState<PersonalTasksInsightsScreen> createState() =>
      _PersonalTasksInsightsScreenState();
}

class _PersonalTasksInsightsScreenState
    extends ConsumerState<PersonalTasksInsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  TaskStatusFilter _statusFilter = TaskStatusFilter.all;
  SmartBlockPriority? _selectedPriority;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleTaskCompletion(
    ContextThread thread,
    SmartBlock targetBlock,
    bool newValue,
  ) async {
    final updatedBlocks = thread.blocks.map((b) {
      if (b.id == targetBlock.id) {
        return b.copyWith(isCompleted: newValue);
      }
      return b;
    }).toList();

    try {
      await ref
          .read(firestoreRepositoryProvider)
          .updateThreadBlocks(thread.id, updatedBlocks);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider);
    final threads = ref.watch(threadsProvider).maybeWhen(
          data: (t) => t,
          orElse: () => const <ContextThread>[],
        );
    final meetings = ref.watch(meetingsProvider).maybeWhen(
          data: (m) => m,
          orElse: () => const <Meeting>[],
        );
    final groups = ref.watch(groupsProvider).maybeWhen(
          data: (g) => g,
          orElse: () => const [],
        );

    final myFirstName = user.name.split(' ').first.toLowerCase();

    // Extract all action items across all visible threads
    final allActionItems = <({ContextThread thread, SmartBlock block})>[];
    for (final thread in threads) {
      for (final block in thread.blocks) {
        if (block.type == SmartBlockType.actionItem) {
          allActionItems.add((thread: thread, block: block));
        }
      }
    }

    // Filter tasks for current user view
    final filteredTasks = allActionItems.where((item) {
      final b = item.block;
      final content = b.content.toLowerCase();
      final assignee = (b.assignee ?? '').toLowerCase();

      // Search filter
      if (_searchQuery.isNotEmpty &&
          !content.contains(_searchQuery) &&
          !assignee.contains(_searchQuery) &&
          !item.thread.meetingTitle.toLowerCase().contains(_searchQuery)) {
        return false;
      }

      // Status filter
      if (_statusFilter == TaskStatusFilter.todo && b.isCompleted) return false;
      if (_statusFilter == TaskStatusFilter.completed && !b.isCompleted) return false;

      // Priority filter
      if (_selectedPriority != null && b.priority != _selectedPriority) return false;

      return true;
    }).toList();

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.colors.textMain),
          onPressed: () => context.canPop() ? context.pop() : context.go('/upcoming'),
        ),
        title: Text(
          'Tasks & Productivity',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.colors.textMain,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.colors.primary,
          unselectedLabelColor: context.colors.textMuted,
          indicatorColor: context.colors.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          tabs: [
            Tab(text: 'Action Items (${allActionItems.length})'),
            const Tab(text: 'Productivity Insights'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── TAB 1: Action Items Hub ───
          _buildActionItemsTab(context, filteredTasks),

          // ─── TAB 2: Productivity Insights ───
          _buildProductivityInsightsTab(
            context,
            allActionItems: allActionItems,
            meetings: meetings,
            groups: groups,
            myFirstName: myFirstName,
          ),
        ],
      ),
    );
  }

  Widget _buildActionItemsTab(
    BuildContext context,
    List<({ContextThread thread, SmartBlock block})> tasks,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Search & Filter header
        TextField(
          controller: _searchController,
          style: TextStyle(color: context.colors.textMain, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search tasks, topics or assignees...',
            hintStyle: TextStyle(color: context.colors.textLight, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: context.colors.textMuted),
            filled: true,
            fillColor: context.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: context.colors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),

        // Status & Priority Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildStatusChip('All', TaskStatusFilter.all),
              const SizedBox(width: 6),
              _buildStatusChip('To Do', TaskStatusFilter.todo),
              const SizedBox(width: 6),
              _buildStatusChip('Completed', TaskStatusFilter.completed),
              const SizedBox(width: 12),
              Container(height: 20, width: 1, color: context.colors.border),
              const SizedBox(width: 12),
              _buildPriorityChip('High Priority', SmartBlockPriority.high, Colors.redAccent),
              const SizedBox(width: 6),
              _buildPriorityChip('Medium', SmartBlockPriority.medium, Colors.orangeAccent),
              const SizedBox(width: 6),
              _buildPriorityChip('Low', SmartBlockPriority.low, Colors.blueAccent),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.colors.border.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Icon(Icons.task_alt_rounded, size: 40, color: context.colors.primary),
                const SizedBox(height: 12),
                Text(
                  'No action items found',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All caught up or no tasks matching this filter.',
                  style: TextStyle(fontSize: 13, color: context.colors.textMuted),
                ),
              ],
            ),
          )
        else
          ...tasks.map((item) {
            final t = item.thread;
            final b = item.block;
            final isOverdue = b.dueDate != null &&
                b.dueDate!.isBefore(DateTime.now()) &&
                !b.isCompleted;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: b.isCompleted
                      ? context.colors.border.withValues(alpha: 0.4)
                      : isOverdue
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : context.colors.border.withValues(alpha: 0.8),
                  width: isOverdue ? 1.5 : 1,
                ),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkbox
                      GestureDetector(
                        onTap: () => _toggleTaskCompletion(t, b, !b.isCompleted),
                        child: Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(top: 2, right: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: b.isCompleted ? const Color(0xFF10B981) : Colors.transparent,
                            border: Border.all(
                              color: b.isCompleted
                                  ? const Color(0xFF10B981)
                                  : context.colors.textLight,
                              width: 2,
                            ),
                          ),
                          child: b.isCompleted
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          b.content,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: b.isCompleted
                                ? context.colors.textLight
                                : context.colors.textMain,
                            decoration: b.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      _buildPriorityBadge(b.priority),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Meeting reference tag
                      GestureDetector(
                        onTap: () => context.push('/thread/${t.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.colors.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.forum_rounded, size: 12, color: context.colors.primary),
                              const SizedBox(width: 4),
                              Text(
                                t.meetingTitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Assignee pill
                      if (b.assignee != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person_rounded, size: 12, color: context.colors.textMuted),
                              const SizedBox(width: 3),
                              Text(
                                b.assignee!,
                                style: TextStyle(fontSize: 11, color: context.colors.textMain, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Due date
                      if (b.dueDate != null)
                        Text(
                          'Due ${DateFormat('MMM d').format(b.dueDate!)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isOverdue ? Colors.redAccent : context.colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildProductivityInsightsTab(
    BuildContext context, {
    required List<({ContextThread thread, SmartBlock block})> allActionItems,
    required List<Meeting> meetings,
    required List<dynamic> groups,
    required String myFirstName,
  }) {
    final myTasks = allActionItems.where((item) {
      final a = (item.block.assignee ?? '').toLowerCase();
      return a == myFirstName || a.contains(myFirstName);
    }).toList();

    final totalMyTasks = myTasks.length;
    final completedMyTasks = myTasks.where((item) => item.block.isCompleted).length;
    final completionPct = totalMyTasks > 0 ? ((completedMyTasks / totalMyTasks) * 100).toInt() : 100;

    // Calculate weekly meeting time
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final thisWeekMeetings = meetings.where((m) => m.startTime.isAfter(weekStart)).toList();

    double totalMinutesThisWeek = 0;
    for (final m in thisWeekMeetings) {
      totalMinutesThisWeek += m.endTime.difference(m.startTime).inMinutes;
    }
    final totalHoursThisWeek = (totalMinutesThisWeek / 60).toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Text(
          'Personal Velocity & Impact',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.colors.textMain,
          ),
        ),
        const SizedBox(height: 16),

        // 3 Key Insight Tiles
        Row(
          children: [
            Expanded(
              child: _buildInsightCard(
                context,
                icon: Icons.access_time_filled_rounded,
                label: 'Meeting Hours',
                value: '${totalHoursThisWeek}h',
                sublabel: 'This week',
                color: const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInsightCard(
                context,
                icon: Icons.task_alt_rounded,
                label: 'Task Velocity',
                value: '$completionPct%',
                sublabel: '$completedMyTasks of $totalMyTasks done',
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Progress Bar Card
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
                  Text(
                    'Assigned Tasks Completion',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                    ),
                  ),
                  Text(
                    '$completionPct%',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalMyTasks > 0 ? (completedMyTasks / totalMyTasks) : 1.0,
                  minHeight: 10,
                  backgroundColor: context.colors.border.withValues(alpha: 0.3),
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Cross-Group Tasks Summary
        Text(
          'TASKS ACROSS GROUPS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.colors.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),

        ...groups.map((group) {
          final groupThreads = allActionItems.where((i) => i.thread.groupId == group.id).toList();
          final total = groupThreads.length;
          final completed = groupThreads.where((i) => i.block.isCompleted).length;
          final pct = total > 0 ? (completed / total) : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
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
                    Text(
                      group.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    Text(
                      '$completed / $total completed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: context.colors.border.withValues(alpha: 0.3),
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStatusChip(String label, TaskStatusFilter filter) {
    final isSelected = _statusFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: context.colors.primaryLight,
      onSelected: (_) => setState(() => _statusFilter = filter),
      labelStyle: TextStyle(
        color: isSelected ? context.colors.primary : context.colors.textMain,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  Widget _buildPriorityChip(String label, SmartBlockPriority priority, Color color) {
    final isSelected = _selectedPriority == priority;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.15),
      onSelected: (val) => setState(() => _selectedPriority = val ? priority : null),
      labelStyle: TextStyle(
        color: isSelected ? color : context.colors.textMain,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  Widget _buildPriorityBadge(SmartBlockPriority priority) {
    Color badgeColor;
    String label;
    switch (priority) {
      case SmartBlockPriority.high:
        badgeColor = Colors.redAccent;
        label = 'HIGH';
        break;
      case SmartBlockPriority.medium:
        badgeColor = Colors.orangeAccent;
        label = 'MED';
        break;
      case SmartBlockPriority.low:
        badgeColor = Colors.blueAccent;
        label = 'LOW';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
      ),
    );
  }

  Widget _buildInsightCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String sublabel,
    required Color color,
  }) {
    return Container(
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
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.colors.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textMain,
            ),
          ),
          Text(
            sublabel,
            style: TextStyle(fontSize: 11, color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}
