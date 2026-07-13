import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

import '../../data/mock_data.dart';
import '../../models/context_thread.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smart_block.dart';
import '../../widgets/reaction_bar.dart';

class ContextThreadScreen extends StatefulWidget {
  final String threadId;

  const ContextThreadScreen({
    super.key,
    required this.threadId,
  });

  @override
  State<ContextThreadScreen> createState() => _ContextThreadScreenState();
}

class _ContextThreadScreenState extends State<ContextThreadScreen> {
  late ContextThread _thread;
  late List<SmartBlock> _blocks;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _thread = MockThreads.threads.firstWhere(
      (t) => t.id == widget.threadId,
      orElse: () => MockThreads.threads.first,
    );
    _blocks = List.from(_thread.blocks);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleComplete(int index) {
    setState(() {
      final block = _blocks[index];
      _blocks[index] = block.copyWith(isCompleted: !block.isCompleted);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: context.colors.background,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: AppBar(
              backgroundColor: context.colors.surface.withValues(alpha: 0.9),
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                '${_thread.meetingTitle} Context',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                left: 20,
                right: 20,
                bottom: 24,
              ),
              children: [
                // Timestamp pill
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.textMuted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      'Today, 10:45 AM',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.colors.textMuted,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: -0.1, end: 0, duration: 300.ms),
                ),
                SizedBox(height: 20),

                // Analytics Card (Vibe + Talk-Time)
                if (_thread.vibe != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildAnalyticsCard(),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

                // Pending Tasks section
                if (_hasPendingTasks())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildPendingTasks(),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

                // Smart blocks with reaction bars
                ...List.generate(_blocks.length, (index) {
                  final block = _blocks[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartBlockWidget(
                          block: block,
                          onToggleComplete: block.type ==
                                  SmartBlockType.actionItem
                              ? () => _toggleComplete(index)
                              : null,
                        )
                            .animate()
                            .fadeIn(
                              duration: 400.ms,
                              delay: (100 * index).ms,
                            )
                            .slideY(
                              begin: 0.08,
                              end: 0,
                              duration: 400.ms,
                              delay: (100 * index).ms,
                              curve: Curves.easeOut,
                            ),
                        if (block.reactions.isNotEmpty) ...[
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ReactionBar(
                              reactions: block.reactions,
                              onReactionTap: (reactionIndex) {
                                // Handle reaction toggle
                              },
                            ),
                          )
                              .animate()
                              .fadeIn(
                                duration: 300.ms,
                                delay: (100 * index + 200).ms,
                              ),
                        ],
                      ],
                    ),
                  );
                }),

                // AI drafting indicator
                if (_thread.isGenerating) ...[
                  SizedBox(height: 8),
                  _AIDraftingIndicator(),
                ],
              ],
            ),
          ),

          // Bottom comment input
          _BottomCommentInput(
            controller: _commentController,
            bottomPadding: bottomPadding,
          ),
        ],
      ),
    );
  }

  bool _hasPendingTasks() {
    return _blocks.any((b) => b.type == SmartBlockType.actionItem && !b.isCompleted);
  }

  Widget _buildAnalyticsCard() {
    final metrics = _thread.talkTimeMetrics ?? {};
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Meeting Vibe',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '${_thread.vibeEmoji ?? ""} ${_thread.vibe ?? ""}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Talk-Time Breakdown',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12),
          // Stacked Bar Chart for talk time
          if (metrics.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: metrics.entries.toList().asMap().entries.map((entry) {
                    final index = entry.key;
                    final value = entry.value.value;
                    // Provide some arbitrary distinct colors for demo
                    final colors = [context.colors.primary, Color(0xFFFACC15), Color(0xFF60A5FA), Color(0xFF34D399)];
                    final color = colors[index % colors.length];
                    return Expanded(
                      flex: (value * 100).toInt(),
                      child: Container(color: color),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingTasks() {
    final pendingBlocks = _blocks.where((b) => b.type == SmartBlockType.actionItem && !b.isCompleted).toList();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.primaryLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 18, color: context.colors.primary),
              SizedBox(width: 8),
              Text(
                'PENDING TASKS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...pendingBlocks.map((block) {
            final indexInBlocks = _blocks.indexOf(block);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _toggleComplete(indexInBlocks),
                    child: Icon(
                      Icons.circle_outlined,
                      size: 20,
                      color: context.colors.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      block.content,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textMain,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── AI Drafting Indicator ─────────────────────────────────
class _AIDraftingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Bouncing dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .moveY(
                      begin: 0,
                      end: -8,
                      duration: 500.ms,
                      delay: (index * 150).ms,
                      curve: Curves.easeInOut,
                    ),
              );
            }),
          ),
          SizedBox(width: 12),
          Text(
            'AI is drafting...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Comment Input ──────────────────────────────────
class _BottomCommentInput extends ConsumerWidget {
  final TextEditingController controller;
  final double bottomPadding;

  const _BottomCommentInput({
    required this.controller,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(appUserProvider);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottomPadding + 12,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // User avatar
          _buildAvatar(context, currentUser.avatarUrl, currentUser.initials),
          SizedBox(width: 12),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.colors.border, width: 1),
              ),
              child: TextField(
                controller: controller,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textLight,
                      ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          // Send button
          GestureDetector(
            onTap: () {
              if (controller.text.trim().isNotEmpty) {
                controller.clear();
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String? avatarUrl, String initials) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null
          ? CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => _initialsAvatar(context, initials),
              errorWidget: (context, url, error) => _initialsAvatar(context, initials),
            )
          : _initialsAvatar(context, initials),
    );
  }

  Widget _initialsAvatar(BuildContext context, String initials) {
    return Container(
      color: context.colors.primaryLight,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
