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

class VoiceSampleRecorderSheet extends ConsumerStatefulWidget {
  const VoiceSampleRecorderSheet({super.key});

  @override
  ConsumerState<VoiceSampleRecorderSheet> createState() => _VoiceSampleRecorderSheetState();
}

class _VoiceSampleRecorderSheetState extends ConsumerState<VoiceSampleRecorderSheet> {
  bool _isRecording = false;
  bool _isUploading = false;
  int _secondsLeft = 5;
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

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _secondsLeft = 5;
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

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 48000,
          bitRate: 64000,
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
          const SnackBar(content: Text('Voice ID saved successfully! 🎙️')),
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
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Text(
            'Record Voice Sample (Voice ID)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textMain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say your name and a short phrase (e.g. "Hi, I\'m Ghan and this is my voice sample"). Conveniently helps Convene AI attribute quotes to you in room meetings.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: context.colors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
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
              'Saving your Voice ID...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textMain,
              ),
            ),
          ] else if (_isRecording) ...[
            // Recording animation & timer
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.3, 1.3), duration: 800.ms),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 40),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '00:0$_secondsLeft',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Speak now...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textMuted,
              ),
            ),
          ] else ...[
            // Tap to record button
            GestureDetector(
              onTap: _startRecording,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.diffused,
                ),
                child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 42),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap to start 5-second recording',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textMain,
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
