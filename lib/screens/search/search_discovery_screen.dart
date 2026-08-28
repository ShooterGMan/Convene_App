import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/context_thread.dart';
import '../../models/group.dart';
import '../../models/meeting.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';

enum SearchCategory { all, meetings, topics, actionItems, decisions }

class SearchResultItem {
  final String id;
  final String title;
  final String subtitle;
  final String typeLabel;
  final IconData icon;
  final Color badgeColor;
  final String route;
  final DateTime timestamp;
  final String? groupName;
  final String? assignee;
  final bool isCompleted;

  const SearchResultItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.typeLabel,
    required this.icon,
    required this.badgeColor,
    required this.route,
    required this.timestamp,
    this.groupName,
    this.assignee,
    this.isCompleted = false,
  });
}

class SearchDiscoveryScreen extends ConsumerStatefulWidget {
  const SearchDiscoveryScreen({super.key});

  @override
  ConsumerState<SearchDiscoveryScreen> createState() => _SearchDiscoveryScreenState();
}

class _SearchDiscoveryScreenState extends ConsumerState<SearchDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  SearchCategory _selectedCategory = SearchCategory.all;
  String? _selectedGroupId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SearchResultItem> _filterResults({
    required List<Meeting> meetings,
    required List<ContextThread> threads,
    required List<Group> groups,
    required String query,
  }) {
    final results = <SearchResultItem>[];
    final q = query.trim().toLowerCase();

    // Helper to get group name
    String? getGroupName(String? groupId) {
      if (groupId == null) return null;
      try {
        return groups.firstWhere((g) => g.id == groupId).name;
      } catch (_) {
        return null;
      }
    }

    // 1. Process Meetings
    if (_selectedCategory == SearchCategory.all || _selectedCategory == SearchCategory.meetings) {
      for (final m in meetings) {
        if (_selectedGroupId != null && m.groupId != _selectedGroupId) continue;

        final titleMatch = m.title.toLowerCase().contains(q);
        final locMatch = m.location?.toLowerCase().contains(q) ?? false;
        final partMatch = m.participants.any((p) => p.name.toLowerCase().contains(q));

        if (q.isEmpty || titleMatch || locMatch || partMatch) {
          final subtitle = m.location?.isNotEmpty == true
              ? '${m.typeLabel} · ${m.location!}'
              : '${m.typeLabel} · ${m.participants.length} participant${m.participants.length == 1 ? '' : 's'}';
          results.add(
            SearchResultItem(
              id: 'meeting_${m.id}',
              title: m.title,
              subtitle: subtitle,
              typeLabel: 'MEETING',
              icon: Icons.calendar_today_rounded,
              badgeColor: const Color(0xFF6366F1),
              route: m.isPast ? '/thread/${m.id}' : '/pre-join/${m.id}',
              timestamp: m.startTime,
              groupName: getGroupName(m.groupId),
            ),
          );
        }
      }
    }

    // 2. Process Topics & Smart Blocks
    for (final t in threads) {
      if (_selectedGroupId != null && t.groupId != _selectedGroupId) continue;

      final gName = getGroupName(t.groupId);

      // Topic summary level match
      if (_selectedCategory == SearchCategory.all || _selectedCategory == SearchCategory.topics) {
        final titleMatch = t.meetingTitle.toLowerCase().contains(q);
        final partMatch = t.participants.any((p) => p.name.toLowerCase().contains(q));
        final blockMatch = t.blocks.any((b) => b.content.toLowerCase().contains(q));

        if (q.isEmpty || titleMatch || partMatch || blockMatch) {
          final summaryBlock = t.blocks.where((b) => b.type == SmartBlockType.summary).firstOrNull;
          final previewText = summaryBlock?.content ?? '${t.blocks.length} topic block(s) recorded';

          results.add(
            SearchResultItem(
              id: 'thread_${t.id}',
              title: t.meetingTitle,
              subtitle: previewText,
              typeLabel: 'TOPIC',
              icon: Icons.auto_awesome_rounded,
              badgeColor: const Color(0xFF8B5CF6),
              route: '/thread/${t.id}',
              timestamp: t.createdAt,
              groupName: gName,
            ),
          );
        }
      }

      // Action items specific search
      if (_selectedCategory == SearchCategory.all || _selectedCategory == SearchCategory.actionItems) {
        for (final b in t.blocks.where((b) => b.type == SmartBlockType.actionItem)) {
          final contentMatch = b.content.toLowerCase().contains(q);
          final assigneeMatch = b.assignee?.toLowerCase().contains(q) ?? false;

          if (q.isNotEmpty && (contentMatch || assigneeMatch)) {
            results.add(
              SearchResultItem(
                id: 'action_${b.id}',
                title: b.content,
                subtitle: 'From "${t.meetingTitle}"',
                typeLabel: 'ACTION ITEM',
                icon: b.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                badgeColor: const Color(0xFF10B981),
                route: '/thread/${t.id}',
                timestamp: b.dueDate ?? t.createdAt,
                groupName: gName,
                assignee: b.assignee,
                isCompleted: b.isCompleted,
              ),
            );
          }
        }
      }

      // Decisions specific search
      if (_selectedCategory == SearchCategory.all || _selectedCategory == SearchCategory.decisions) {
        for (final b in t.blocks.where((b) => b.type == SmartBlockType.decision)) {
          final contentMatch = b.content.toLowerCase().contains(q);

          if (q.isNotEmpty && contentMatch) {
            results.add(
              SearchResultItem(
                id: 'decision_${b.id}',
                title: b.content,
                subtitle: 'Key Decision from "${t.meetingTitle}"',
                typeLabel: 'DECISION',
                icon: Icons.gavel_rounded,
                badgeColor: const Color(0xFFF59E0B),
                route: '/thread/${t.id}',
                timestamp: t.createdAt,
                groupName: gName,
              ),
            );
          }
        }
      }
    }

    // Sort newest first
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final meetingsAsync = ref.watch(meetingsProvider);
    final threadsAsync = ref.watch(threadsProvider);
    final groupsAsync = ref.watch(groupsProvider);

    final meetings = meetingsAsync.value ?? [];
    final threads = threadsAsync.value ?? [];
    final groups = groupsAsync.value ?? [];

    final query = _searchController.text;
    final results = _filterResults(
      meetings: meetings,
      threads: threads,
      groups: groups,
      query: query,
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Search & Discovery',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.colors.textMain,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar & Filter Controls
          Container(
            color: context.colors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text Input
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: context.colors.textMain, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search meetings, topics, action items...',
                      hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: context.colors.primary, size: 22),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('All', SearchCategory.all),
                      _buildCategoryChip('Meetings', SearchCategory.meetings),
                      _buildCategoryChip('Topics', SearchCategory.topics),
                      _buildCategoryChip('Action Items', SearchCategory.actionItems),
                      _buildCategoryChip('Decisions', SearchCategory.decisions),
                      if (groups.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: _selectedGroupId != null ? context.colors.primaryLight : context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: _selectedGroupId != null ? context.colors.primary : context.colors.border,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _selectedGroupId,
                              isDense: true,
                              hint: Text(
                                'Group',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textMuted,
                                ),
                              ),
                              dropdownColor: context.colors.surface,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All Groups', style: TextStyle(fontSize: 12)),
                                ),
                                ...groups.map((g) => DropdownMenuItem(
                                      value: g.id,
                                      child: Text(g.name, style: const TextStyle(fontSize: 12)),
                                    )),
                              ],
                              onChanged: (val) => setState(() => _selectedGroupId = val),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search Results Counter
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  query.isEmpty ? 'RECENT ITEMS' : 'SEARCH RESULTS (${results.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.colors.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                if (query.isNotEmpty)
                  Text(
                    'Matched across all records',
                    style: TextStyle(fontSize: 11, color: context.colors.textLight),
                  ),
              ],
            ),
          ),

          // Results List
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: context.colors.textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            query.isEmpty ? 'No items found' : 'No matches for "$query"',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textMain,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try searching for another keyword, decision, or attendee name.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: context.colors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SearchResultCard(item: item)
                            .animate()
                            .fadeIn(
                              duration: 300.ms,
                              delay: (30 * index).ms,
                            )
                            .slideY(begin: 0.05, end: 0),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, SearchCategory category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: context.colors.primaryLight,
        onSelected: (_) => setState(() => _selectedCategory = category),
        labelStyle: TextStyle(
          color: isSelected ? context.colors.primary : context.colors.textMain,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final SearchResultItem item;

  const _SearchResultCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
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
            // Top Row: Type Badge + Group / Time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 12, color: item.badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        item.typeLabel,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: item.badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.groupName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.colors.background,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        item.groupName!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  DateFormat('MMM d').format(item.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),

            // Subtitle / Preview Snippet
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textMuted,
                height: 1.4,
              ),
            ),

            if (item.assignee != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: context.colors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '@${item.assignee}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
