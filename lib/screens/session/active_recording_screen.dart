import 'dart:async';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/waveform_visualizer.dart';
import '../thread/context_thread_screen.dart';

/// Records an in-person / solo session by joining an audio-only LiveKit room.
/// A server-side egress bot (see functions/src/webhook.ts) records the room and
/// generates the summary automatically once the session ends - this screen never
/// touches the audio itself, it just joins, waits, and watches Firestore for the
/// resulting thread.
class ActiveRecordingScreen extends ConsumerStatefulWidget {
  final String meetingTitle;
  final String meetingId;
  final List<AppUser> participants;
  final String? groupId;

  const ActiveRecordingScreen({
    super.key,
    required this.meetingTitle,
    required this.meetingId,
    required this.participants,
    this.groupId,
  });

  @override
  ConsumerState<ActiveRecordingScreen> createState() => _ActiveRecordingScreenState();
}

class _ActiveRecordingScreenState extends ConsumerState<ActiveRecordingScreen> {
  final Room _room = Room();
  EventsListener<RoomEvent>? _roomListener;
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isConnecting = true;
  bool _isEnding = false;
  bool _markedImportant = false;
  String? _connectError;

  StreamSubscription? _meetingSub;
  Timer? _summaryTimeoutTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[REC] initState meetingId=${widget.meetingId}');
    _connect();
  }

  Future<void> _connect() async {
    debugPrint('[REC] requesting LiveKit token...');
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('getLivekitToken').call({
        'meetingId': widget.meetingId,
        'groupId': widget.groupId,
        'displayName': ref.read(appUserProvider).name,
      });
      final String token = result.data['token'];
      const String livekitUrl = "wss://convene-app-a9liwgoq.livekit.cloud";
      debugPrint('[REC] token received, connecting to $livekitUrl room=${widget.meetingId}');

      _roomListener = _room.createListener();
      _roomListener!
        ..on<RoomConnectedEvent>((e) => debugPrint('[REC] RoomConnectedEvent'))
        ..on<RoomDisconnectedEvent>((e) => debugPrint('[REC] RoomDisconnectedEvent reason=${e.reason}'))
        ..on<RoomReconnectingEvent>((e) => debugPrint('[REC] RoomReconnectingEvent'))
        ..on<RoomReconnectedEvent>((e) => debugPrint('[REC] RoomReconnectedEvent'))
        ..on<LocalTrackPublishedEvent>((e) => debugPrint('[REC] LocalTrackPublishedEvent sid=${e.publication.sid} kind=${e.publication.kind} muted=${e.publication.muted}'))
        ..on<LocalTrackUnpublishedEvent>((e) => debugPrint('[REC] LocalTrackUnpublishedEvent sid=${e.publication.sid}'))
        ..on<ParticipantConnectedEvent>((e) => debugPrint('[REC] ParticipantConnectedEvent ${e.participant.identity}'))
        ..on<ParticipantDisconnectedEvent>((e) => debugPrint('[REC] ParticipantDisconnectedEvent ${e.participant.identity}'));

      await _room.connect(livekitUrl, token);
      debugPrint('[REC] connect() returned. room.connectionState=${_room.connectionState}');

      await _room.localParticipant?.setMicrophoneEnabled(true);
      debugPrint('[REC] setMicrophoneEnabled(true) returned.');

      final localTracks = _room.localParticipant?.trackPublications.values.toList() ?? [];
      debugPrint('[REC] local track publications count=${localTracks.length}');
      for (final pub in localTracks) {
        debugPrint('[REC]   track sid=${pub.sid} kind=${pub.kind} source=${pub.source} muted=${pub.muted} subscribed=${pub.subscribed}');
      }

      if (!mounted) {
        debugPrint('[REC] WARNING: widget unmounted immediately after connect - navigated away already?');
        return;
      }
      setState(() => _isConnecting = false);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isEnding && mounted) {
          setState(() => _elapsedSeconds++);
        }
      });
    } catch (e) {
      debugPrint('[REC] Failed to start recording session: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[REC] dispose() called - room.connectionState=${_room.connectionState}');
    _timer?.cancel();
    _meetingSub?.cancel();
    _summaryTimeoutTimer?.cancel();
    _roomListener?.dispose();
    _room.disconnect();
    _room.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _endSession() async {
    setState(() => _isEnding = true);
    _timer?.cancel();

    try {
      // We're always the sole participant here, so it's safe to finalize the
      // egress immediately instead of waiting on LiveKit's empty-room timeout.
      final result = await FirebaseFunctions.instance.httpsCallable('stopMeetingEgress').call({
        'meetingId': widget.meetingId,
      });
      await _room.disconnect();

      final stoppedCount = result.data['stopped'] as int? ?? 0;
      if (stoppedCount == 0) {
        // No recording was ever running for this session (e.g. it ended almost
        // instantly) - there's nothing to summarize, so don't leave the user
        // waiting on a summary that will never arrive.
        if (mounted) {
          setState(() => _isEnding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session ended before any audio was captured - nothing to summarize.')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      _watchForSummary();
    } catch (e) {
      debugPrint('Failed to end session: $e');
      if (mounted) {
        setState(() => _isEnding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to end session: $e')),
        );
      }
    }
  }

  void _watchForSummary() {
    final repo = ref.read(firestoreRepositoryProvider);
    _meetingSub = repo.streamMeeting(widget.meetingId).listen((meeting) {
      if (!mounted || meeting == null) return;

      if (meeting.threadId != null) {
        _summaryTimeoutTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ContextThreadScreen(threadId: meeting.threadId!),
          ),
        );
        return;
      }

      if (meeting.summaryError != null) {
        _summaryTimeoutTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Summary generation failed for this session.')),
        );
        Navigator.of(context).pop();
      }
    });

    // Summarization normally takes well under a minute; if it's still not
    // ready after two, let the user leave instead of staring at a spinner -
    // the thread will still show up in their group once it finishes.
    _summaryTimeoutTimer = Timer(const Duration(minutes: 2), () {
      if (mounted && _isEnding) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still generating your summary - it will appear in the group shortly.'),
          ),
        );
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background mock content (faint)
          _MockBackgroundContent(),

          // Glassmorphism overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),

          // Main content
          if (_connectError != null)
            _ConnectErrorOverlay(error: _connectError!, onRetry: () {
              setState(() {
                _connectError = null;
                _isConnecting = true;
              });
              _connect();
            })
          else if (_isConnecting)
            const Center(child: CircularProgressIndicator())
          else if (_isEnding)
            _GeneratingOverlay()
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SizedBox(height: 16),

                    // Recording indicator pill
                    _RecordingPill(meetingTitle: widget.meetingTitle)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: -0.2, end: 0, duration: 400.ms),

                    const Spacer(flex: 2),

                    // Timer display
                    Text(
                      _formattedTime,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        color: context.colors.textMain,
                        letterSpacing: 2,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 100.ms)
                        .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1.0, 1.0),
                          duration: 500.ms,
                          delay: 100.ms,
                          curve: Curves.easeOut,
                        ),

                    SizedBox(height: 8),
                    Text(
                      'Active Session',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textMuted,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 200.ms),

                    SizedBox(height: 40),

                    // Waveform visualizer (decorative - actual audio is handled
                    // server-side by the egress bot, not on this device)
                    WaveformVisualizer(height: 128)
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 300.ms),

                    const Spacer(flex: 2),

                    // Mark Important button
                    GestureDetector(
                      onTap: () async {
                        final newValue = !_markedImportant;
                        setState(() => _markedImportant = newValue);
                        try {
                          await ref
                              .read(firestoreRepositoryProvider)
                              .setMeetingImportant(widget.meetingId, newValue);
                        } catch (e) {
                          if (mounted) setState(() => _markedImportant = !newValue);
                        }
                      },
                      child: AnimatedContainer(
                        duration: 200.ms,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: _markedImportant
                              ? context.colors.primaryLight
                              : context.colors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          boxShadow: AppShadows.diffused,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _markedImportant
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              color: context.colors.primary,
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              _markedImportant
                                  ? 'Marked Important'
                                  : 'Mark Important',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.colors.textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 400.ms)
                        .slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 400.ms,
                          delay: 400.ms,
                        ),

                    SizedBox(height: 32),

                    // End Session button
                    Column(
                      children: [
                        GestureDetector(
                          onTap: _endSession,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: context.colors.textMain,
                              borderRadius:
                                  BorderRadius.circular(16),
                              boxShadow: AppShadows.elevated,
                            ),
                            child: Center(
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: context.colors.error,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'End Session',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 500.ms),

                    SizedBox(height: safePadding.bottom + 24),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Recording Pill ────────────────────────────────────────
class _RecordingPill extends StatelessWidget {
  final String meetingTitle;

  const _RecordingPill({required this.meetingTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing red dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: context.colors.error,
              shape: BoxShape.circle,
            ),
          )
              .animate(
                onPlay: (controller) => controller.repeat(reverse: true),
              )
              .scaleXY(
                begin: 1.0,
                end: 0.6,
                duration: 800.ms,
                curve: Curves.easeInOut,
              )
              .then()
              .scaleXY(
                begin: 0.6,
                end: 1.0,
                duration: 800.ms,
                curve: Curves.easeInOut,
              ),
          SizedBox(width: 10),
          Text(
            'RECORDING: ${meetingTitle.toUpperCase()}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textMain,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Generating Overlay ────────────────────────────────────
class _GeneratingOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: context.colors.primary,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
              ),
          SizedBox(height: 24),
          Text(
            'Generating Context Thread...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.colors.textMain,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 200.ms),
          SizedBox(height: 8),
          Text(
            'AI is summarizing your meeting',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.textMuted,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 300.ms),
        ],
      ),
    );
  }
}

// ─── Connect Error Overlay ─────────────────────────────────
class _ConnectErrorOverlay extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ConnectErrorOverlay({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: context.colors.error, size: 40),
            SizedBox(height: 16),
            Text(
              'Failed to start recording session',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              error,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: context.colors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ─── Mock Background Content ───────────────────────────────
class _MockBackgroundContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 60),
            // Fake app bar
            Container(
              height: 20,
              width: 160,
              decoration: BoxDecoration(
                color: context.colors.textMain.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 32),
            // Fake cards
            ...List.generate(4, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  height: 80 + (index * 10.0),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: AppShadows.card,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 100 + (index * 30.0),
                        decoration: BoxDecoration(
                          color: context.colors.textMain.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        height: 10,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: context.colors.textMain.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
