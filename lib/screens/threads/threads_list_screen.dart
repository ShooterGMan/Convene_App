import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/data_providers.dart';

import '../../models/context_thread.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';

class ThreadsListScreen extends ConsumerStatefulWidget {
  const ThreadsListScreen({super.key});

  @override
  ConsumerState<ThreadsListScreen> createState() => _ThreadsListScreenState();
}

class _ThreadsListScreenState extends ConsumerState<ThreadsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(threadsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Topics',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    SizedBox(height: 16),
                    // Semantic Search Bar
                    Container(
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        boxShadow: AppShadows.card,
                        border: Border.all(color: _isSearching ? context.colors.primary : context.colors.border),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _isSearching = val.isNotEmpty;
                          });
                        },
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textMain,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ask Convene AI...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            color: context.colors.textLight,
                          ),
                          prefixIcon: Icon(
                            Icons.auto_awesome,
                            color: _isSearching ? context.colors.primary : context.colors.textMuted,
                            size: 20,
                          ),
                          suffixIcon: _isSearching
                              ? IconButton(
                                  icon: Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _isSearching = false);
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Thread cards
            threadsAsync.when(
              data: (threadsData) {
                final query = _searchController.text.trim().toLowerCase();
                final threads = threadsData.where((t) {
                  if (query.isEmpty) return true;
                  if (t.meetingTitle.toLowerCase().contains(query)) return true;
                  if (t.participants.any((p) => p.name.toLowerCase().contains(query))) return true;
                  if (t.blocks.any((b) => b.content.toLowerCase().contains(query))) return true;
                  return false;
                }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                
                if (threads.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80.0, horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.colors.primaryLight.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isSearching ? Icons.search_off_rounded : Icons.forum_outlined,
                              size: 48,
                              color: context.colors.primary,
                            ),
                          ),
                          SizedBox(height: 24),
                          Text(
                            _isSearching ? 'No matching topics' : 'No topics yet',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textMain,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching
                                ? 'No meeting summaries matched "$query". Try searching for another topic or attendee name.'
                                : 'Topics appear here automatically once your meetings are transcribed and summarized by Convene AI.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: context.colors.textMuted,
                              height: 1.5,
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
                        final thread = threads[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ThreadCard(thread: thread)
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
                      childCount: threads.length,
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

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _ThreadCard extends ConsumerWidget {
  final ContextThread thread;

  const _ThreadCard({required this.thread});

  String _relativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'} ago';
    }
    final months = (diff.inDays / 30).floor();
    return '$months month${months == 1 ? '' : 's'} ago';
  }

  String? _groupName(WidgetRef ref) {
    if (thread.groupId == null) return null;
    final groupsAsync = ref.watch(groupsProvider);
    return groupsAsync.maybeWhen(
      data: (groups) {
        try {
          return groups.firstWhere((g) => g.id == thread.groupId).name;
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );
  }

  int _totalReactions() {
    int total = 0;
    for (final block in thread.blocks) {
      for (final reaction in block.reactions) {
        total += reaction.count;
      }
    }
    return total;
  }

  String? _firstBlockPreview() {
    if (thread.blocks.isEmpty) return null;
    return thread.blocks.first.content;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = _groupName(ref);
    final preview = _firstBlockPreview();
    final reactionCount = _totalReactions();

    return GestureDetector(
      onTap: () => context.push('/thread/${thread.id}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row + group pill
            Row(
              children: [
                Expanded(
                  child: Text(
                    thread.meetingTitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (groupName != null) ...[
                  SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.colors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      groupName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 6),

            // Relative time
            Text(
              _relativeTime(thread.createdAt),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.textMuted,
              ),
            ),

            // Preview
            if (preview != null) ...[
              SizedBox(height: 10),
              Text(
                preview,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textMain,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            SizedBox(height: 14),

            // Bottom row: avatars + reactions
            Row(
              children: [
                _buildAvatarStack(context, thread.participants),
                const Spacer(),
                if (reactionCount > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_emotions_outlined,
                        size: 16,
                        color: context.colors.textMuted,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '$reactionCount',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack(BuildContext context, List<AppUser> users) {
    final display = users.take(3).toList();
    const double size = 28;
    const double overlap = 8;
    final extraCount = users.length - display.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
        ),
        if (extraCount > 0) ...[
          SizedBox(width: 6),
          Text(
            '+$extraCount',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textMuted,
            ),
          ),
        ],
      ],
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
