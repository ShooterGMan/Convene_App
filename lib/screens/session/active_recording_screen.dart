import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/user.dart';
import '../../repositories/firestore_repository.dart';
import '../../services/background_meeting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recording_consent.dart';
import '../../widgets/waveform_visualizer.dart';
import '../thread/context_thread_screen.dart';

/// Records an in-person / solo session by directly capturing microphone audio
/// on the device. When the session ends, the audio is uploaded directly to the
/// backend for instant Gemini summarization with zero cloud egress lag or frame drop.
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
  AudioRecorder? _audioRecorder;
  StreamSubscription? _amplitudeSub;
  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();

  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isConnecting = true;
  bool _isEnding = false;
  bool _markedImportant = false;
  String? _connectError;

  StreamSubscription? _meetingSub;
  Timer? _summaryTimeoutTimer;

  // Recording captures people physically in the room, so we don't start recording
  // until the recorder has confirmed everyone present agreed.
  bool _consented = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
  }

  void _onConsent() {
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable error: $e');
    }
    setState(() => _consented = true);
    _startRecording();
  }

  Future<void> _startRecording() async {
    debugPrint('[REC] starting in-person audio recording session for ${widget.meetingId}');
    try {
      if (!kIsWeb) {
        try {
          await [
            Permission.microphone,
            Permission.bluetoothConnect,
          ].request();
        } catch (e) {
          debugPrint('[REC] Permission request error: $e');
        }
      }

      final recorder = _audioRecorder;
      if (recorder == null) throw Exception("Recorder not initialized.");

      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        throw Exception("Microphone permission denied. Please allow microphone access.");
      }

      final String filePath;
      if (kIsWeb) {
        filePath = '';
      } else {
        filePath = '${Directory.systemTemp.path}/in_person_${widget.meetingId}_${DateTime.now().millisecondsSinceEpoch}.ogg';
      }

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 48000,
          bitRate: 64000,
        ),
        path: filePath,
      );

      // Listen to live amplitude changes and stream to the waveform visualizer
      _amplitudeSub = recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        // amp.current is typically in dBFS (e.g. -60 dB to 0 dB)
        final normalized = ((amp.current + 60) / 60).clamp(0.08, 1.0);
        if (!_amplitudeController.isClosed) {
          _amplitudeController.add(normalized);
        }
      });

      if (!mounted) return;
      setState(() => _isConnecting = false);

      BackgroundMeetingService.start(
        title: 'Recording Session Active',
        text: '${widget.meetingTitle} is recording in the background',
      );

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
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable error: $e');
    }
    BackgroundMeetingService.stop();
    _timer?.cancel();
    _meetingSub?.cancel();
    _summaryTimeoutTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeController.close();
    _audioRecorder?.dispose();
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
    _amplitudeSub?.cancel();

    try {
      final recorder = _audioRecorder;
      if (recorder == null) throw Exception("Recorder not initialized.");

      final recordedPath = await recorder.stop();
      if (recordedPath == null || recordedPath.isEmpty) {
        if (mounted) {
          setState(() => _isEnding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session ended before audio was captured - nothing to summarize.')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      Uint8List audioBytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(recordedPath));
        audioBytes = response.bodyBytes;
      } else {
        final file = File(recordedPath);
        if (!await file.exists()) throw Exception("Recorded audio file not found.");
        audioBytes = await file.readAsBytes();
        try {
          await file.delete();
        } catch (_) {}
      }

      if (audioBytes.isEmpty) {
        if (mounted) {
          setState(() => _isEnding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recorded audio was empty - nothing to summarize.')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      const mimeType = 'audio/ogg';
      final base64Audio = base64Encode(audioBytes);

      // Start watching meeting doc in Firestore for summary ready / threadId
      _watchForSummary();

      // Upload directly to Cloud Function for immediate AI processing
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await functions.httpsCallable('uploadMeetingAudio').call({
        'meetingId': widget.meetingId,
        'audioBase64': base64Audio,
        'mimeType': mimeType,
      });
    } catch (e) {
      debugPrint('[REC] Failed to end session / upload audio: $e');
      if (mounted) {
        setState(() => _isEnding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    }
  }

  void _watchForSummary() {
    final repo = ref.read(firestoreRepositoryProvider);
    _meetingSub = repo.streamMeeting(widget.meetingId).listen((meeting) {
      if (!mounted || meeting == null) return;

      if (meeting.threadId != null && meeting.threadId!.isNotEmpty) {
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
          SnackBar(content: Text('Summary generation failed: ${meeting.summaryError}')),
        );
        Navigator.of(context).pop();
      }
    });

    _summaryTimeoutTimer = Timer(const Duration(minutes: 2), () {
      if (mounted && _isEnding) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still generating your summary - it will appear in your Topics shortly.'),
          ),
        );
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding;

    // Gate the whole recording flow behind explicit consent before anything
    // connects or records.
    if (!_consented) {
      return OfflineRecordingConsentGate(
        onConsent: _onConsent,
        onCancel: () => context.canPop() ? context.pop() : context.go('/upcoming'),
      );
    }

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
              _startRecording();
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

                    // Live real-time audio waveform visualizer
                    WaveformVisualizer(
                      height: 128,
                      amplitudeStream: _amplitudeController.stream,
                    )
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
