import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../providers/auth_provider.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

/// Records a 10–12 second dual-distance dynamic voice sample for Voice ID.
/// Preserves natural vocal tract formants by disabling destructive OS echo cancellation
/// and aggressive noise suppression filters (crucial for whiteboard and distance invariance).
class VoiceSampleRecorderSheet extends ConsumerStatefulWidget {
  const VoiceSampleRecorderSheet({super.key});

  @override
  ConsumerState<VoiceSampleRecorderSheet> createState() => _VoiceSampleRecorderSheetState();
}

class _VoiceSampleRecorderSheetState extends ConsumerState<VoiceSampleRecorderSheet> {
  static const int _totalRecordingSeconds = 10;
  bool _isRecording = false;
  bool _isUploading = false;
  int _secondsLeft = _totalRecordingSeconds;
  Timer? _countdownTimer;
  String? _errorMessage;

  AudioRecorder? _audioRecorder;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _audioRecorder?.dispose();
    super.dispose();
  }

  bool get _isPhaseOne => _secondsLeft > 5;

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _secondsLeft = _totalRecordingSeconds;
      _errorMessage = null;
    });

    try {
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
        filePath = '${Directory.systemTemp.path}/voiceprint_${DateTime.now().millisecondsSinceEpoch}.ogg';
      }

      // CRITICAL FAR-FIELD & FORMANT CONFIG:
      // echoCancel: false and noiseSuppress: false preserve raw vocal tract formants
      // across varying speaker distances (near desk vs distant whiteboard).
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 24000,
          bitRate: 64000,
          numChannels: 1,
          autoGain: true,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: filePath,
      );

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsLeft > 1) {
          if (mounted) setState(() => _secondsLeft--);
        } else {
          timer.cancel();
          _finishRecordingAndUpload();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _finishRecordingAndUpload() async {
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isUploading = true;
      });
    }

    try {
      final recorder = _audioRecorder;
      if (recorder == null) throw Exception("Recorder not initialized.");

      final recordedPath = await recorder.stop();
      if (recordedPath == null || recordedPath.isEmpty) {
        throw Exception("No audio was captured. Please try again.");
      }

      Uint8List audioBytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(recordedPath));
        audioBytes = response.bodyBytes;
      } else {
        final file = File(recordedPath);
        if (!await file.exists()) throw Exception("Recording file not found.");
        audioBytes = await file.readAsBytes();
        try {
          await file.delete();
        } catch (_) {}
      }

      if (audioBytes.isEmpty) {
        throw Exception("Recorded audio sample was empty. Please try again.");
      }

      const mimeType = 'audio/ogg';
      final base64Audio = base64Encode(audioBytes);
      final uid = ref.read(currentUserProvider)?.uid;
      if (uid == null) throw Exception("User not signed in.");

      // Upload via Cloud Function
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('saveVoiceprint')
          .call({
        'audioBase64': base64Audio,
        'mimeType': mimeType,
      });

      // Update Firestore client state
      await ref.read(firestoreRepositoryProvider).updateUserVoiceprintStatus(uid, true);
      ref.invalidate(appUserProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dual-distance Voice ID saved successfully! 🎙️'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userDisplayName = ref.watch(appUserProvider).name;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.spatial_audio_off_rounded, color: context.colors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                '10s Dual-Distance Voice ID',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Record your voice at two distances so Convexa attributes your quotes even when you walk to a whiteboard or speak across a conference table.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: context.colors.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],

          if (_isUploading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Saving calibrated Voice ID...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textMain,
              ),
            ),
          ] else if (_isRecording) ...[
            // Phase indicator badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _isPhaseOne
                    ? Colors.blue.withValues(alpha: 0.15)
                    : Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isPhaseOne ? Colors.blue : Colors.amber.shade700,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPhaseOne ? Icons.mic : Icons.surround_sound,
                    size: 16,
                    color: _isPhaseOne ? Colors.blue : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isPhaseOne
                        ? 'PHASE 1: DESK VOICE (Normal distance)'
                        : 'PHASE 2: PROJECTING (Arm\'s length / whiteboard)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _isPhaseOne ? Colors.blue.shade800 : Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Script prompt container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  Text(
                    _isPhaseOne ? 'Read out loud normally:' : 'Hold phone at arm\'s length & project:',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isPhaseOne
                        ? '"Hi, my name is $userDisplayName, and this is my normal speaking voice at a desk."'
                        : '"And this is $userDisplayName speaking louder from across a meeting room or whiteboard."',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMain,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Animated recording orb with countdown
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: (_isPhaseOne ? context.colors.primary : Colors.amber.shade700)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.3, 1.3), duration: 700.ms),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _isPhaseOne ? context.colors.primary : Colors.amber.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '00:${_secondsLeft.toString().padLeft(2, '0')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _isPhaseOne ? context.colors.primary : Colors.amber.shade800,
              ),
            ),
          ] else ...[
            // Prompt Card before recording starts
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HOW IT WORKS (10 SECONDS TOTAL):',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textMuted,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          'First 5s: Hold phone normally and say your desk intro.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2. ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          'Next 5s: Extend arm and project louder as if at a whiteboard.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tap to record button
            GestureDetector(
              onTap: _startRecording,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.diffused,
                ),
                child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to record 10s sample',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: context.colors.textMain,
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
