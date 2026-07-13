import 'dart:async';
import 'dart:ui';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/user.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/waveform_visualizer.dart';
import '../../services/audio_recorder_service.dart';
import '../../services/gemini_service.dart';
import '../thread/context_thread_screen.dart';

class ActiveRecordingScreen extends ConsumerStatefulWidget {
  final String meetingTitle;
  final String meetingId;
  final List<AppUser> participants;

  const ActiveRecordingScreen({
    super.key,
    required this.meetingTitle,
    required this.meetingId,
    required this.participants,
  });

  @override
  ConsumerState<ActiveRecordingScreen> createState() => _ActiveRecordingScreenState();
}

class _ActiveRecordingScreenState extends ConsumerState<ActiveRecordingScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isEnding = false;
  bool _markedImportant = false;

  @override
  void initState() {
    super.initState();
    _startRecording();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isEnding && mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  Future<void> _startRecording() async {
    try {
      final audioService = ref.read(audioRecorderServiceProvider);
      await audioService.startRecording(widget.meetingId);
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    ref.read(audioRecorderServiceProvider).dispose();
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
      final audioService = ref.read(audioRecorderServiceProvider);
      final geminiService = ref.read(geminiServiceProvider);
      
      final filePath = await audioService.stopRecording();
      if (filePath == null) {
        throw Exception("No audio file recorded");
      }

      // Process with Gemini
      final thread = await geminiService.processMeetingAudio(filePath, widget.meetingTitle, widget.participants);

      // Save to Firestore
      await ref.read(firestoreRepositoryProvider).createThread(thread);

      // Clean up local audio file
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete raw audio: $e');
      }

      if (mounted) {
        // Push Replacement to avoid coming back to recording
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ContextThreadScreen(threadId: thread.id),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to process session: $e');
      if (mounted) {
        setState(() => _isEnding = false); // revert state on failure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    }
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
          if (_isEnding)
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

                    // Waveform visualizer
                    WaveformVisualizer(
                      height: 128,
                      amplitudeStream: ref.watch(audioRecorderServiceProvider).amplitudeStream,
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 300.ms),

                    const Spacer(flex: 2),

                    // Mark Important button
                    GestureDetector(
                      onTap: () {
                        setState(() => _markedImportant = !_markedImportant);
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
