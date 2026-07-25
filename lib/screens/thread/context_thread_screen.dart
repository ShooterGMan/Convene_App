import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../repositories/firestore_repository.dart';
import '../../models/context_thread.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smart_block.dart';

class ContextThreadScreen extends ConsumerStatefulWidget {
  final String threadId;

  const ContextThreadScreen({
    super.key,
    required this.threadId,
  });

  @override
  ConsumerState<ContextThreadScreen> createState() => _ContextThreadScreenState();
}

class _ContextThreadScreenState extends ConsumerState<ContextThreadScreen> {
  ContextThread? _thread;
  List<SmartBlock> _blocks = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchThread();
  }

  Future<void> _fetchThread() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('threads').doc(widget.threadId).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        final thread = ContextThread.fromJson(data);
        if (mounted) {
          setState(() {
            _thread = thread;
            _blocks = List.from(thread.blocks);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = "Thread not found";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _copyThreadLink(BuildContext context) {
    final url = 'https://meeting-app-844aa.web.app/thread/${widget.threadId}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Future<void> _toggleComplete(int index) async {
    final previous = _blocks[index];
    setState(() {
      _blocks[index] = previous.copyWith(isCompleted: !previous.isCompleted);
    });
    try {
      await ref.read(firestoreRepositoryProvider).updateThreadBlocks(widget.threadId, _blocks);
    } catch (e) {
      if (mounted) {
        setState(() => _blocks[index] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _thread == null) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(child: Text(_error ?? "Failed to load thread", style: TextStyle(color: context.colors.textMain))),
      );
    }

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
                '${_thread!.meetingTitle} Context',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.link_rounded, size: 22),
                  tooltip: 'Copy Link',
                  onPressed: () => _copyThreadLink(context),
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
                // Timestamp + group pill
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.colors.textMuted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          DateFormat('MMM d, y · h:mm a').format(_thread!.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.colors.textMuted,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                        ),
                      ),
                      if (_thread!.groupId != null)
                        Consumer(
                          builder: (context, ref, _) {
                            final groupsAsync = ref.watch(groupsProvider);
                            final groupName = groupsAsync.maybeWhen(
                              data: (groups) {
                                try {
                                  return groups.firstWhere((g) => g.id == _thread!.groupId).name;
                                } catch (_) {
                                  return null;
                                }
                              },
                              orElse: () => null,
                            );
                            if (groupName == null) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.colors.primaryLight,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.groups_rounded, size: 14, color: context.colors.primary),
                                  SizedBox(width: 6),
                                  Text(
                                    groupName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: context.colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: -0.1, end: 0, duration: 300.ms),
                ),
                SizedBox(height: 20),

                // Analytics Card (Vibe + Talk-Time)
                if (_thread!.vibe != null)
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

                // Smart blocks
                ...List.generate(_blocks.length, (index) {
                  final block = _blocks[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SmartBlockWidget(
                      block: block,
                      onToggleComplete: block.type == SmartBlockType.actionItem
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
                  );
                }),

                // AI drafting indicator
                if (_thread!.isGenerating) ...[
                  SizedBox(height: 8),
                  _AIDraftingIndicator(),
                ],

                if (_thread!.meetingId != null) ...[
                  SizedBox(height: 8),
                  _TranscriptSection(meetingId: _thread!.meetingId!),
                ],

                SizedBox(height: 24),
                _CommentsSection(threadId: widget.threadId),
              ],
            ),
          ),

          // Bottom comment input
          _BottomCommentInput(
            threadId: widget.threadId,
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
    final metrics = _thread!.talkTimeMetrics ?? {};
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
                  '${_thread!.vibeEmoji ?? ""} ${_thread!.vibe ?? ""}',
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

// ─── Transcript Section ─────────────────────────────────────
/// Lazily loads and shows the raw transcript for this meeting, if one was
/// kept (transcripts are retained for 30 days, then auto-deleted).
class _TranscriptSection extends StatefulWidget {
  final String meetingId;

  const _TranscriptSection({required this.meetingId});

  @override
  State<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends State<_TranscriptSection> {
  bool _isExpanded = false;
  Future<DocumentSnapshot<Map<String, dynamic>>>? _future;

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      _future ??= FirebaseFirestore.instance.collection('transcripts').doc(widget.meetingId).get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.article_outlined, size: 18, color: context.colors.textMuted),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Transcript',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ));
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'Failed to load transcript.',
                      style: GoogleFonts.plusJakartaSans(color: context.colors.textMuted, fontSize: 13),
                    );
                  }
                  final data = snapshot.data?.data();
                  final transcript = data?['transcript'] as String?;
                  if (transcript == null || transcript.trim().isEmpty) {
                    return Text(
                      'No transcript was kept for this meeting (it may be older than 30 days, or none was captured).',
                      style: GoogleFonts.plusJakartaSans(color: context.colors.textMuted, fontSize: 13, height: 1.4),
                    );
                  }
                  return SelectableText(
                    transcript,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: context.colors.textMain,
                      height: 1.6,
                    ),
                  );
                },
              ),
            ),
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

// ─── Comments Section ───────────────────────────────────────
class _CommentsSection extends ConsumerWidget {
  final String threadId;

  const _CommentsSection({required this.threadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(firestoreRepositoryProvider);

    return StreamBuilder<List<ThreadComment>>(
      stream: repo.streamComments(threadId),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? [];
        if (comments.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMMENTS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.colors.textMuted,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 12),
            ...comments.map((comment) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CommentAvatar(
                        avatarUrl: comment.author.avatarUrl,
                        initials: comment.author.initials,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  comment.author.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.textMain,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM d, h:mm a').format(comment.timestamp),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: context.colors.textLight,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2),
                            Text(
                              comment.content,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: context.colors.textMain,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;

  const _CommentAvatar({required this.avatarUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => _initials(context),
              errorWidget: (context, url, error) => _initials(context),
            )
          : _initials(context),
    );
  }

  Widget _initials(BuildContext context) {
    return Container(
      color: context.colors.primaryLight,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── Bottom Comment Input ──────────────────────────────────
class _BottomCommentInput extends ConsumerWidget {
  final String threadId;
  final TextEditingController controller;
  final double bottomPadding;

  const _BottomCommentInput({
    required this.threadId,
    required this.controller,
    required this.bottomPadding,
  });

  void _submit(WidgetRef ref, AppUser currentUser) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final comment = ThreadComment(
      id: ref.read(firestoreProvider).collection('threads').doc(threadId).collection('comments').doc().id,
      author: currentUser,
      content: text,
      timestamp: DateTime.now(),
    );
    ref.read(firestoreRepositoryProvider).addComment(threadId, comment);
    controller.clear();
  }

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
            onTap: () => _submit(ref, currentUser),
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
