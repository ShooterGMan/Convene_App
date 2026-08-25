import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // "What changed since you last viewed" tracking.
  DateTime? _lastViewed;
  int _newCommentsSinceView = 0;
  int _editedSinceView = 0;
  bool _summaryNewSinceView = false;
  bool _changesDismissed = false;

  // "Was this summary accurate?" — asked once per topic, then remembered.
  bool _feedbackGiven = false;

  bool get _hasChanges =>
      !_changesDismissed && (_summaryNewSinceView || _newCommentsSinceView > 0 || _editedSinceView > 0);

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _clearRelatedNotifications() {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    final notifications = ref.read(notificationsProvider).value ?? [];
    final repo = ref.read(firestoreRepositoryProvider);

    for (final n in notifications) {
      if (!n.isRead &&
          (n.relatedId == widget.threadId ||
              n.route == '/thread/${widget.threadId}' ||
              (_thread != null && (n.relatedId == _thread!.id || n.relatedId == _thread!.meetingId)))) {
        repo.markNotificationRead(uid, n.id).catchError((_) {});
      }
    }
  }

  Future<void> _init() async {
    try {
      // 1. Instant cache lookup from threadsProvider so card taps open immediately
      final threadsAsync = ref.read(threadsProvider);
      final cachedList = threadsAsync.value ?? [];
      ContextThread? cachedThread;
      for (final t in cachedList) {
        if (t.id == widget.threadId || t.meetingId == widget.threadId) {
          cachedThread = t;
          break;
        }
      }

      if (cachedThread != null && mounted) {
        setState(() {
          _thread = cachedThread;
          _blocks = List.from(cachedThread!.blocks);
          _isLoading = false;
        });
      }

      _clearRelatedNotifications();

      final key = 'topic_seen_${widget.threadId}';
      final prefs = await SharedPreferences.getInstance();
      final storedMs = prefs.getInt(key);
      _lastViewed = storedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(storedMs);
      final feedbackGiven = prefs.getBool('topic_feedback_${widget.threadId}') ?? false;
      if (mounted) setState(() => _feedbackGiven = feedbackGiven);

      await _fetchThread();
      _clearRelatedNotifications();
      await _computeWhatChanged();

      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("Thread init error: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _computeWhatChanged() async {
    if (_lastViewed == null || _thread == null) return;
    final since = _lastViewed!;

    int newComments = 0;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('threads')
          .doc(widget.threadId)
          .collection('comments')
          .get();
      for (final d in snap.docs) {
        final ts = d.data()['timestamp'];
        final t = ts is Timestamp ? ts.toDate() : (ts is String ? DateTime.tryParse(ts) : null);
        if (t != null && t.isAfter(since)) newComments++;
      }
    } catch (_) {
      // Non-fatal: the banner just won't count comments.
    }

    final edited = _blocks.where((b) => b.editedAt != null && b.editedAt!.isAfter(since)).length;
    final summaryNew = _thread!.createdAt.isAfter(since);

    if (mounted) {
      setState(() {
        _newCommentsSinceView = newComments;
        _editedSinceView = edited;
        _summaryNewSinceView = summaryNew;
      });
    }
  }

  Future<void> _fetchThread() async {
    try {
      // 1. Try directly fetching doc by threadId
      var doc = await FirebaseFirestore.instance.collection('threads').doc(widget.threadId).get();

      // 2. If not found by doc ID, try searching by meetingId == widget.threadId
      if (!doc.exists) {
        final querySnap = await FirebaseFirestore.instance
            .collection('threads')
            .where('meetingId', isEqualTo: widget.threadId)
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          doc = querySnap.docs.first;
        }
      }

      // 3. Fallback: check meetings collection for threadId mapping
      if (!doc.exists) {
        final meetingSnap = await FirebaseFirestore.instance.collection('meetings').doc(widget.threadId).get();
        if (meetingSnap.exists && meetingSnap.data() != null) {
          final realThreadId = meetingSnap.data()!['threadId'] as String?;
          if (realThreadId != null && realThreadId.isNotEmpty) {
            doc = await FirebaseFirestore.instance.collection('threads').doc(realThreadId).get();
          }
        }
      }

      if (doc.exists && doc.data() != null) {
        final data = Map<String, dynamic>.from(doc.data()!);
        data['id'] = doc.id;
        final thread = ContextThread.fromJson(data, docId: doc.id);
        if (mounted) {
          setState(() {
            _thread = thread;
            _blocks = List.from(thread.blocks);
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        if (mounted && _thread == null) {
          setState(() {
            _error = "Topic summary not found";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch thread error: $e");
      if (mounted && _thread == null) {
        setState(() {
          _error = "Failed to load topic: $e";
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

  /// Lightweight "correct the AI" workflow: edit a block's text and stamp it
  /// with who changed it and when, so the record shows an "edited by" marker
  /// rather than silently diverging from what was said.
  Future<void> _editBlock(int index) async {
    final block = _blocks[index];
    final controller = TextEditingController(text: block.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'Correct ${block.typeLabel.toLowerCase()}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: TextStyle(color: context.colors.textMain),
          decoration: InputDecoration(
            filled: true,
            fillColor: context.colors.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || newText == block.content) return;

    final me = ref.read(appUserProvider).name;
    final previous = _blocks[index];
    setState(() {
      _blocks[index] = previous.copyWith(content: newText, editedBy: me, editedAt: DateTime.now());
    });
    try {
      await ref.read(firestoreRepositoryProvider).updateThreadBlocks(widget.threadId, _blocks);
    } catch (e) {
      if (mounted) {
        setState(() => _blocks[index] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save edit: $e')),
        );
      }
    }
  }

  Future<void> _assignBlock(int index) async {
    final block = _blocks[index];
    final participants = _thread?.participants ?? [];
    final controller = TextEditingController(text: block.assignee ?? '');
    
    final selectedName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'Assign Action Item',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (participants.isNotEmpty) ...[
              Text(
                'Select a participant or enter a custom name:',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: participants.map((user) {
                  final firstName = user.name.split(' ').first;
                  return ChoiceChip(
                    label: Text('@$firstName'),
                    selected: controller.text.toLowerCase() == firstName.toLowerCase(),
                    onSelected: (_) => Navigator.of(dialogCtx).pop(firstName),
                    selectedColor: context.colors.primaryLight,
                    labelStyle: TextStyle(
                      color: controller.text.toLowerCase() == firstName.toLowerCase()
                          ? context.colors.primary
                          : context.colors.textMain,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              style: TextStyle(color: context.colors.textMain),
              decoration: InputDecoration(
                hintText: 'Or type name (e.g. Alex)',
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (selectedName == null) return;
    final assigneeName = selectedName.isEmpty ? null : selectedName.replaceAll('@', '');
    final previous = _blocks[index];

    setState(() {
      _blocks[index] = previous.copyWith(assignee: assigneeName);
    });

    try {
      await ref.read(firestoreRepositoryProvider).updateThreadBlocks(widget.threadId, _blocks);
    } catch (e) {
      if (mounted) {
        setState(() => _blocks[index] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update assignee: $e')),
        );
      }
    }
  }

  /// Distinct generic "Speaker N" labels the AI used because it couldn't match
  /// a voice to a name. These are what the owner can correct.
  List<String> _detectSpeakerLabels() {
    final re = RegExp(r'Speaker\s+\w+');
    final found = <String>{};
    for (final b in _blocks) {
      for (final m in re.allMatches(b.content)) {
        found.add(m.group(0)!);
      }
    }
    final list = found.toList()..sort();
    return list;
  }

  /// Lets the meeting owner map each detected "Speaker N" to a real name; the
  /// mapping is applied across every block and stamped as an edit.
  Future<void> _showFixSpeakers() async {
    final labels = _detectSpeakerLabels();
    if (labels.isEmpty) return;
    final controllers = {for (final l in labels) l: TextEditingController()};

    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text('Fix speaker names', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Replace each detected label with the real name. Leave blank to keep it.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
              ),
              SizedBox(height: 16),
              for (final label in labels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(label, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain)),
                      ),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: context.colors.textLight),
                      SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controllers[label],
                          textCapitalization: TextCapitalization.words,
                          style: TextStyle(color: context.colors.textMain),
                          decoration: InputDecoration(
                            hintText: 'Real name',
                            isDense: true,
                            filled: true,
                            fillColor: context.colors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: Text('Cancel', style: TextStyle(color: context.colors.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (apply != true) return;

    final mapping = <String, String>{};
    controllers.forEach((label, ctrl) {
      final name = ctrl.text.trim();
      if (name.isNotEmpty && name != label) mapping[label] = name;
    });
    if (mapping.isEmpty) return;

    final me = ref.read(appUserProvider).name;
    final now = DateTime.now();
    final previous = List<SmartBlock>.from(_blocks);
    setState(() {
      _blocks = _blocks.map((b) {
        var content = b.content;
        mapping.forEach((from, to) => content = content.replaceAll(from, to));
        return content == b.content ? b : b.copyWith(content: content, editedBy: me, editedAt: now);
      }).toList();
    });
    try {
      await ref.read(firestoreRepositoryProvider).updateThreadBlocks(widget.threadId, _blocks);
    } catch (e) {
      if (mounted) {
        setState(() => _blocks = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to rename speakers: $e')));
      }
    }
  }

  Future<void> _submitSummaryFeedback(bool accurate) async {
    String? message;
    if (!accurate) {
      final controller = TextEditingController();
      message = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: context.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          title: Text('What was missing or wrong?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            style: TextStyle(color: context.colors.textMain),
            decoration: InputDecoration(
              hintText: 'Optional — helps us improve the AI summaries',
              filled: true,
              fillColor: context.colors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(''), child: Text('Skip', style: TextStyle(color: context.colors.textMuted))),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      // Dialog dismissed entirely (barrier tap) — don't record anything.
      if (message == null) return;
    }

    final me = ref.read(currentUserProvider)?.uid;
    if (me != null) {
      try {
        await ref.read(firestoreRepositoryProvider).submitFeedback(
              userId: me,
              kind: 'summary',
              threadId: widget.threadId,
              accurate: accurate,
              message: message,
            );
      } catch (e) {
        debugPrint('Failed to submit feedback: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('topic_feedback_${widget.threadId}', true);
    if (mounted) {
      setState(() => _feedbackGiven = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for the feedback!')),
      );
    }
  }

  Widget _buildFeedbackPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Was this summary accurate?',
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textMain),
            ),
          ),
          TextButton.icon(
            onPressed: () => _submitSummaryFeedback(true),
            icon: Icon(Icons.thumb_up_outlined, size: 16, color: context.colors.primary),
            label: Text('Yes', style: TextStyle(color: context.colors.primary)),
          ),
          TextButton.icon(
            onPressed: () => _submitSummaryFeedback(false),
            icon: Icon(Icons.thumb_down_outlined, size: 16, color: context.colors.textMuted),
            label: Text('No', style: TextStyle(color: context.colors.textMuted)),
          ),
        ],
      ),
    );
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
                _thread!.meetingTitle,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              actions: [
                if (_detectSpeakerLabels().isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.record_voice_over_outlined, size: 22),
                    tooltip: 'Fix speaker names',
                    onPressed: _showFixSpeakers,
                  ),
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

                // "What changed since you last viewed this?" banner.
                if (_hasChanges) ...[
                  _buildWhatChanged(),
                  SizedBox(height: 16),
                ],

                // Topic overview: status, decisions, your actions at a glance.
                _buildTopicOverview()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.08, end: 0),
                SizedBox(height: 24),

                // Analytics Card (Vibe + Talk-Time)
                if (_thread!.vibe != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildAnalyticsCard(),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

                // Audio / Video Recording Playback Section
                if (_thread!.recordingUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildAudioPlaybackSection(),
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
                      onEdit: () => _editBlock(index),
                      onAssign: block.type == SmartBlockType.actionItem
                          ? () => _assignBlock(index)
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

                if (!_feedbackGiven && !_thread!.isGenerating && _blocks.isNotEmpty) ...[
                  SizedBox(height: 24),
                  _buildFeedbackPrompt(),
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

  Widget _buildWhatChanged() {
    final parts = <String>[];
    if (_summaryNewSinceView) parts.add('a new summary');
    if (_editedSinceView > 0) parts.add('$_editedSinceView correction${_editedSinceView == 1 ? '' : 's'}');
    if (_newCommentsSinceView > 0) parts.add('$_newCommentsSinceView new comment${_newCommentsSinceView == 1 ? '' : 's'}');
    final summary = parts.isEmpty ? 'There are updates.' : 'Since your last visit: ${parts.join(', ')}.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.primaryLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.fiber_new_rounded, size: 20, color: context.colors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What changed',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: context.colors.primary),
                ),
                SizedBox(height: 2),
                Text(
                  summary,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMain, height: 1.4),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _changesDismissed = true),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.close_rounded, size: 18, color: context.colors.textMuted),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  /// One-sentence status distilled from the summary block. For a multi-session
  /// topic the newest session's summary is the most relevant "current status".
  String? _statusSentence() {
    final summaryBlock = _blocks.where((b) => b.type == SmartBlockType.summary).lastOrNull ??
        (_blocks.isNotEmpty ? _blocks.first : null);
    final text = summaryBlock?.content.trim();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'[.!?]').firstMatch(text);
    if (match != null && match.end < text.length) {
      return text.substring(0, match.end);
    }
    return text;
  }

  Widget _buildTopicOverview() {
    final myFirstName = ref.read(appUserProvider).name.split(' ').first;
    final status = _statusSentence();
    final decisions = _blocks.where((b) => b.type == SmartBlockType.decision).toList();
    final keyPoints = _blocks.where((b) => b.type == SmartBlockType.keyInsight).toList();
    final myActions = _blocks
        .where((b) => b.type == SmartBlockType.actionItem && b.assignee == myFirstName && !b.isCompleted)
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
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
              Icon(Icons.auto_awesome_rounded, size: 18, color: context.colors.primary),
              SizedBox(width: 8),
              Text(
                'Topic overview',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: context.colors.textMain),
              ),
            ],
          ),
          SizedBox(height: 4),
          // Source meeting + date, so every point below is traceable.
          Text(
            'From ${_thread!.meetingTitle} · ${DateFormat('MMM d, y').format(_thread!.createdAt)}',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted),
          ),
          if (status != null) ...[
            SizedBox(height: 14),
            Text(
              status,
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textMain, height: 1.4),
            ),
          ],
          if (decisions.isNotEmpty) _overviewSection('Decisions', decisions.map((b) => b.content).toList(), Icons.lightbulb_outline_rounded),
          if (myActions.isNotEmpty) _overviewSection('Your action items', myActions.map((b) => b.content).toList(), Icons.check_circle_outline_rounded),
          if (keyPoints.isNotEmpty) _overviewSection('Key points', keyPoints.map((b) => b.content).toList(), Icons.sticky_note_2_outlined),
          if (status == null && decisions.isEmpty && myActions.isEmpty && keyPoints.isEmpty) ...[
            SizedBox(height: 12),
            Text(
              'This summary is still being generated.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _overviewSection(String label, List<String> items, IconData icon) {
    final show = items.take(3).toList();
    final extra = items.length - show.length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.colors.textMuted),
              SizedBox(width: 6),
              Text(
                '${label.toUpperCase()} (${items.length})',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: context.colors.textMuted, letterSpacing: 0.6),
              ),
            ],
          ),
          SizedBox(height: 8),
          for (final item in show)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(width: 5, height: 5, decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle)),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: context.colors.textMain, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(left: 15, top: 2),
              child: Text(
                '+$extra more below',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textMuted),
              ),
            ),
        ],
      ),
    );
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

  Widget _buildAudioPlaybackSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 20, color: context.colors.primary),
              SizedBox(width: 8),
              Text(
                'MEETING AUDIO RECORDING',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primary,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'Cloud Sync',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: context.colors.primary,
                child: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Playing cloud recording from ${_thread!.recordingUrl}')),
                    );
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio Track & AI Transcript Stream',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: 0.35,
                      backgroundColor: context.colors.border.withValues(alpha: 0.3),
                      color: context.colors.primary,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                '04:12',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textMuted,
                ),
              ),
            ],
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
                'PENDING TASKS (${pendingBlocks.length})',
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
                crossAxisAlignment: CrossAxisAlignment.center,
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
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _assignBlock(indexInBlocks),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        block.assignee != null ? '@${block.assignee}' : 'Assign',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: block.assignee != null ? context.colors.primary : context.colors.textMuted,
                        ),
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
