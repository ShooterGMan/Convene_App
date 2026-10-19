import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/background_meeting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/co_located_sheet.dart';
import '../../widgets/recording_consent.dart';
import '../../widgets/waveform_visualizer.dart';

/// Manages in-person recording for either the Primary Host Phone or a Satellite Table Mic.
/// Eliminates comb-filtering by uploading isolated spatial zone tracks instead of mixing waveforms.
class InPersonMultiMicController {
  final AudioRecorder _recorder = AudioRecorder();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  StreamSubscription<DocumentSnapshot>? _meetingStatusSub;
  String? _localFilePath;
  DateTime? _startedAt;
  bool _isStopping = false;

  AudioRecorder get recorder => _recorder;

  /// Returns recommended number of phones based on present attendee count
  static int getRecommendedPhoneCount(int attendeeCount) {
    if (attendeeCount <= 5) return 1;
    if (attendeeCount <= 9) return 2;
    return 3;
  }

  /// Starts recording as either the Primary Host Phone or a Satellite Table Mic
  Future<void> startRecording({
    required String meetingId,
    required String groupId,
    required String currentUserId,
    required String currentUserName,
    required bool isHostPhone,
    List<String>? presentUserIds,
    required VoidCallback onAutoStoppedByHost,
  }) async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission required');
    }

    final dir = Directory.systemTemp;
    _localFilePath =
        '${dir.path}/mic_${meetingId}_${currentUserId}_${DateTime.now().millisecondsSinceEpoch}.ogg';

    // CRITICAL FAR-FIELD CONFIG:
    // echoCancel & noiseSuppress MUST be false so distant speakers at a table/whiteboard aren't muted by OS DSP
    const config = RecordConfig(
      encoder: AudioEncoder.opus,
      sampleRate: 24000,
      bitRate: 64000,
      numChannels: 1,
      autoGain: true,
      echoCancel: false,
      noiseSuppress: false,
    );

    _startedAt = DateTime.now();
    await _recorder.start(config, path: _localFilePath!);

    final meetingRef = _firestore.collection('meetings').doc(meetingId);

    if (isHostPhone) {
      await meetingRef.set({
        'type': 'in_person',
        'groupId': groupId,
        'hostUserId': currentUserId,
        'status': 'recording',
        'presentParticipantIds': presentUserIds ?? [currentUserId],
        'activeMics': {
          currentUserId: {
            'userName': currentUserName,
            'role': 'primary',
            'status': 'recording',
            'startedAt': FieldValue.serverTimestamp(),
          }
        },
        'uploadedAudioPaths': [],
        'startedAt': FieldValue.serverTimestamp(),
        'lastActivityAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await meetingRef.set({
        'presentParticipantIds': FieldValue.arrayUnion([currentUserId]),
        'activeMics': {
          currentUserId: {
            'userName': currentUserName,
            'role': 'satellite',
            'status': 'recording',
            'startedAt': FieldValue.serverTimestamp(),
          }
        },
        'lastActivityAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Listen for Host stopping the meeting so Satellite phones auto-stop & upload
    _meetingStatusSub = meetingRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;

      if (data['status'] == 'stopping_mics' && !_isStopping) {
        await stopAndUploadMic(
          meetingId: meetingId,
          groupId: groupId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          isHostInitiatingStop: false,
        );
        onAutoStoppedByHost();
      }
    });
  }

  /// Updates the list of group members physically present in the room
  Future<void> updatePresentParticipants({
    required String meetingId,
    required List<String> presentUserIds,
  }) async {
    await _firestore.collection('meetings').doc(meetingId).update({
      'presentParticipantIds': presentUserIds,
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stops local recording, uploads .ogg to GCS, and triggers AI processing once all active mics finish uploading
  Future<void> stopAndUploadMic({
    required String meetingId,
    required String groupId,
    required String currentUserId,
    required String currentUserName,
    required bool isHostInitiatingStop,
  }) async {
    if (_isStopping) return;
    _isStopping = true;

    await _meetingStatusSub?.cancel();
    final meetingRef = _firestore.collection('meetings').doc(meetingId);

    if (isHostInitiatingStop) {
      await meetingRef.update({
        'status': 'stopping_mics',
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    }

    final recordedPath = await _recorder.stop();
    if (recordedPath == null) return;

    final file = File(recordedPath);
    if (!await file.exists()) return;

    final durationSeconds = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : 0;

    // Guard against accidental < 15 second recordings
    if (durationSeconds < 15 && isHostInitiatingStop) {
      try {
        await file.delete();
      } catch (_) {}
      await meetingRef.update({
        'status': 'cancelled_too_short',
        'summaryStatus': 'cancelled_too_short',
        'summaryError': 'Meeting was under 15 seconds. No summary generated.',
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final gcsPath = 'in-person-audio/$groupId/$meetingId/mic_$currentUserId.ogg';
    final storageRef = _storage.ref().child(gcsPath);

    await storageRef.putFile(
      file,
      SettableMetadata(
        contentType: 'audio/ogg',
        customMetadata: {
          'meetingId': meetingId,
          'micOwnerId': currentUserId,
          'micOwnerName': currentUserName,
          'durationSeconds': durationSeconds.toString(),
        },
      ),
    );

    await meetingRef.set({
      'activeMics': {
        currentUserId: {
          'userName': currentUserName,
          'status': 'uploaded',
          'gcsPath': gcsPath,
          'durationSeconds': durationSeconds,
        }
      },
      'uploadedAudioPaths': FieldValue.arrayUnion([
        {
          'userId': currentUserId,
          'userName': currentUserName,
          'gcsPath': gcsPath,
        }
      ]),
      'lastActivityAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    // Check if all active mics have uploaded; if so, mark ready_for_ai
    final latestDoc = await meetingRef.get();
    final activeMics =
        (latestDoc.data()?['activeMics'] as Map<String, dynamic>?) ?? {};
    final allUploaded = activeMics.values.every(
      (mic) => (mic as Map<String, dynamic>)['status'] == 'uploaded',
    );

    if (allUploaded) {
      await meetingRef.update({
        'status': 'ready_for_ai',
        'summaryStatus': 'processing',
        'endedAt': FieldValue.serverTimestamp(),
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> discardRecording({
    required String meetingId,
    required bool isHost,
  }) async {
    await _meetingStatusSub?.cancel();
    final recordedPath = await _recorder.stop();
    if (recordedPath != null) {
      try {
        final f = File(recordedPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (isHost) {
      try {
        await _firestore.collection('meetings').doc(meetingId).update({
          'status': 'cancelled',
          'summaryStatus': 'cancelled',
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _meetingStatusSub?.cancel();
    await _recorder.dispose();
  }
}

class MultiPhoneRecommendationBanner extends StatelessWidget {
  final int selectedAttendeeCount;
  final int connectedMicCount;

  const MultiPhoneRecommendationBanner({
    super.key,
    required this.selectedAttendeeCount,
    required this.connectedMicCount,
  });

  @override
  Widget build(BuildContext context) {
    final recommendedMics = InPersonMultiMicController.getRecommendedPhoneCount(
      selectedAttendeeCount,
    );

    if (connectedMicCount >= recommendedMics) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                connectedMicCount == 1
                    ? '1 Phone Active — Optimal for up to 5 people in a small room.'
                    : '$connectedMicCount Phones Active — Multi-zone room coverage enabled!',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final neededMore = recommendedMics - connectedMicCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.surround_sound, color: Colors.amber.shade800, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Large Meeting ($selectedAttendeeCount People): Add $neededMore More Phone${neededMore > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'For $selectedAttendeeCount people in a larger room, ask $neededMore teammate${neededMore > 1 ? 's' : ''} at the other end of the table or near the whiteboard to open Convexa and tap "Join as Table Mic" for crystal-clear transcripts.',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// In-person meeting studio recording screen supporting multi-phone spatial table mics,
/// attendee presence selection, and shared-mic co-location.
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
  final InPersonMultiMicController _multiMicController = InPersonMultiMicController();
  StreamSubscription? _amplitudeSub;
  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();

  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isConnecting = true;
  bool _isEnding = false;
  bool _isPaused = false;
  String? _connectError;
  double _currentAmplitude = 0.0;
  bool _isSatelliteMode = false;

  final Set<String> _presentUserIds = {};
  final List<Map<String, String>> _keyMoments = [];
  final TextEditingController _notesController = TextEditingController();
  bool _showNotes = false;
  String _endingStep = 'Finalizing audio capture...';
  bool _consented = false;

  @override
  void initState() {
    super.initState();
    _presentUserIds.addAll(widget.participants.map((u) => u.id));
  }

  void _onConsent() {
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable error: $e');
    }
    setState(() => _consented = true);
    _initRecording();
  }

  Future<void> _initRecording() async {
    final currentUserId = ref.read(currentUserProvider)?.uid ?? 'guest';
    final currentUserName = ref.read(appUserProvider).name;
    final resolvedGroupId = widget.groupId ?? 'direct';

    try {
      if (!kIsWeb) {
        try {
          await [
            Permission.microphone,
            Permission.bluetoothConnect,
          ].request();
        } catch (_) {}
      }

      // Check if another host already started this meeting
      final meetingDoc = await FirebaseFirestore.instance.collection('meetings').doc(widget.meetingId).get();
      final data = meetingDoc.data();
      final existingHost = data?['hostUserId'] as String?;
      final isAlreadyRecording = data?['status'] == 'recording';

      final isHost = !isAlreadyRecording || existingHost == null || existingHost == currentUserId;
      _isSatelliteMode = !isHost;

      if (_presentUserIds.isEmpty) {
        _presentUserIds.add(currentUserId);
      }

      await _multiMicController.startRecording(
        meetingId: widget.meetingId,
        groupId: resolvedGroupId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        isHostPhone: isHost,
        presentUserIds: _presentUserIds.toList(),
        onAutoStoppedByHost: () {
          if (mounted) {
            setState(() {
              _isEnding = true;
              _endingStep = 'Host ended session. Audio uploaded!';
            });
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) context.go('/upcoming');
            });
          }
        },
      );

      // Connect VU meter & amplitude stream
      _amplitudeSub = _multiMicController.recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (_isPaused) return;
        final raw = amp.current;
        final normalized = ((raw + 50) / 50).clamp(0.08, 1.0);
        if (mounted) setState(() => _currentAmplitude = normalized);
        if (!_amplitudeController.isClosed) _amplitudeController.add(normalized);
      });

      if (!mounted) return;
      setState(() => _isConnecting = false);

      BackgroundMeetingService.start(
        title: _isSatelliteMode ? 'Table Mic Active' : 'Recording Studio Active',
        text: '${widget.meetingTitle} is capturing far-field audio',
      );

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isEnding && !_isPaused && mounted) {
          setState(() => _elapsedSeconds++);
        }
      });
    } catch (e) {
      debugPrint('[REC] Start error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectError = e.toString();
        });
      }
    }
  }

  Future<void> _togglePauseResume() async {
    try {
      if (_isPaused) {
        await _multiMicController.recorder.resume();
        setState(() => _isPaused = false);
      } else {
        await _multiMicController.recorder.pause();
        setState(() => _isPaused = true);
      }
    } catch (e) {
      debugPrint('Pause/Resume error: $e');
    }
  }

  void _addKeyMoment() {
    final timeStr = _formattedTime;
    setState(() {
      _keyMoments.add({'time': timeStr, 'title': 'Key Moment at $timeStr'});
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📌 Key moment bookmarked at $timeStr'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String get _formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _endSession() async {
    setState(() {
      _isEnding = true;
      _endingStep = 'Stopping all table microphones...';
    });
    _timer?.cancel();
    _amplitudeSub?.cancel();

    final currentUserId = ref.read(currentUserProvider)?.uid ?? 'guest';
    final currentUserName = ref.read(appUserProvider).name;
    final resolvedGroupId = widget.groupId ?? 'direct';

    try {
      await _multiMicController.stopAndUploadMic(
        meetingId: widget.meetingId,
        groupId: resolvedGroupId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        isHostInitiatingStop: !_isSatelliteMode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting recorded! Gemini AI summary is generating...'),
            duration: Duration(seconds: 4),
          ),
        );
        context.go('/upcoming');
      }
    } catch (e) {
      debugPrint('[REC] End session error: $e');
      if (mounted) {
        setState(() => _isEnding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    }
  }

  Future<void> _discardRecording() async {
    setState(() => _isEnding = true);
    _timer?.cancel();
    _amplitudeSub?.cancel();
    try {
      await _multiMicController.discardRecording(
        meetingId: widget.meetingId,
        isHost: !_isSatelliteMode,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording discarded.')),
        );
        context.go('/upcoming');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEnding = false);
        context.go('/upcoming');
      }
    }
  }

  void _showLeaveConfirmationDialog() {
    if (_isEnding) return;
    if (_isSatelliteMode) {
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: const Text('Disconnect Table Mic?'),
          content: const Text('Do you want to stop sending audio from this device and return?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(dCtx).pop();
                _endSession();
              },
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: const Text('Leave Recording Session?'),
          content: const Text('Audio is currently recording. Do you want to end and summarize, discard, or stay?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dCtx).pop();
                _discardRecording();
              },
              child: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(dCtx).pop();
                _endSession();
              },
              child: const Text('End & Summarize'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    BackgroundMeetingService.stop();
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeController.close();
    _notesController.dispose();
    _multiMicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_consented) {
      return OfflineRecordingConsentGate(
        onConsent: _onConsent,
        onCancel: () => context.canPop() ? context.pop() : context.go('/upcoming'),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showLeaveConfirmationDialog();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.colors.textMain, size: 20),
            onPressed: _showLeaveConfirmationDialog,
          ),
        title: Column(
          children: [
            Text(
              widget.meetingTitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _isPaused ? const Color(0xFFF59E0B) : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isSatelliteMode
                      ? 'SATELLITE TABLE MIC'
                      : _isPaused
                          ? 'PAUSED'
                          : 'PRIMARY ROOM MIC',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _isPaused ? const Color(0xFFF59E0B) : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _showNotes ? Icons.edit_note_rounded : Icons.notes_rounded,
              color: _showNotes ? context.colors.primary : context.colors.textMuted,
            ),
            tooltip: 'Live Notes',
            onPressed: () => setState(() => _showNotes = !_showNotes),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _connectError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text('Recording Error: $_connectError', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _initRecording, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            : _isConnecting
                ? const Center(child: CircularProgressIndicator())
                : _isEnding
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            Text(
                              _endingStep,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textMain,
                              ),
                            ),
                          ],
                        ),
                      )
                    : StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('meetings')
                            .doc(widget.meetingId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final mData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                          final activeMics = (mData['activeMics'] as Map<String, dynamic>?) ?? {};
                          final connectedMicCount = activeMics.isNotEmpty ? activeMics.length : 1;

                          return Column(
                            children: [
                              // Attendees and Shared Mic Roster Bar
                              _buildAttendeesHeader(mData),

                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  child: Column(
                                    children: [
                                      // Multi-Phone Recommendation Banner
                                      MultiPhoneRecommendationBanner(
                                        selectedAttendeeCount: _presentUserIds.length,
                                        connectedMicCount: connectedMicCount,
                                      ),
                                      const SizedBox(height: 16),

                                      // Connected Mics Status Pill
                                      if (connectedMicCount > 1) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.surround_sound, size: 14, color: Colors.blue),
                                              const SizedBox(width: 6),
                                              Text(
                                                '$connectedMicCount Synchronized Spatial Zone Mics Active',
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                      ],

                                      // Recording Timer Display
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: context.colors.surface,
                                          borderRadius: BorderRadius.circular(AppRadius.lg),
                                          border: Border.all(
                                            color: _isPaused
                                                ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                                : context.colors.primary.withValues(alpha: 0.2),
                                          ),
                                          boxShadow: AppShadows.card,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              _formattedTime,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 50,
                                                fontWeight: FontWeight.w800,
                                                color: _isPaused
                                                    ? context.colors.textMuted
                                                    : context.colors.textMain,
                                                letterSpacing: 2,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.mic_rounded,
                                                  size: 14,
                                                  color: _isPaused
                                                      ? context.colors.textMuted
                                                      : context.colors.primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _isPaused
                                                      ? 'Recording Paused'
                                                      : 'Opus 24kHz HD • Raw Formants (Whiteboard DSP)',
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
                                      ),
                                      const SizedBox(height: 20),

                                      // Waveform Visualizer & VU Meter
                                      Container(
                                        height: 130,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: context.colors.surface,
                                          borderRadius: BorderRadius.circular(AppRadius.md),
                                          border: Border.all(color: context.colors.border),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'AUDIO WAVEFORM & LEVELS',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: context.colors.textMuted,
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: _currentAmplitude > 0.18
                                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                        : context.colors.background,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    _currentAmplitude > 0.18 ? 'SPEECH DETECTED' : 'ROOM AMBIENT',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                      color: _currentAmplitude > 0.18
                                                          ? const Color(0xFF10B981)
                                                          : context.colors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Expanded(
                                              child: WaveformVisualizer(
                                                height: 70,
                                                amplitudeStream: _amplitudeController.stream,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Quick action buttons
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _addKeyMoment,
                                              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                                              label: const Text('Bookmark'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: context.colors.surface,
                                                foregroundColor: context.colors.textMain,
                                                elevation: 0,
                                                side: BorderSide(color: context.colors.border),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                CoLocatedParticipantsSheet.show(
                                                  context: context,
                                                  meetingId: widget.meetingId,
                                                  groupId: widget.groupId,
                                                );
                                              },
                                              icon: const Icon(Icons.group_add_rounded, size: 18),
                                              label: const Text('Shared Mic'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: context.colors.surface,
                                                foregroundColor: context.colors.primary,
                                                elevation: 0,
                                                side: BorderSide(color: context.colors.primary.withValues(alpha: 0.3)),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (_showNotes) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: context.colors.surface,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: context.colors.border),
                                          ),
                                          child: TextField(
                                            controller: _notesController,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                              hintText: 'Type live meeting notes or observations...',
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              // Bottom Controls
                              _buildBottomControlDeck(),
                            ],
                          );
                        },
                      ),
      ),
    ),
  );
}

  Widget _buildAttendeesHeader(Map<String, dynamic> meetingData) {
    final coLocatedMap = (meetingData['coLocatedMap'] as Map<String, dynamic>?) ?? {};
    final currentUserId = ref.watch(currentUserProvider)?.uid;
    final myCoGuests = (coLocatedMap[currentUserId] as List<dynamic>?)?.cast<String>() ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'ROOM ATTENDEES:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.colors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),

            ...widget.participants.map((p) {
              final isPresent = _presentUserIds.contains(p.id);

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  selected: isPresent,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _presentUserIds.add(p.id);
                      } else {
                        _presentUserIds.remove(p.id);
                      }
                    });
                    _multiMicController.updatePresentParticipants(
                      meetingId: widget.meetingId,
                      presentUserIds: _presentUserIds.toList(),
                    );
                  },
                  avatar: CircleAvatar(
                    radius: 10,
                    backgroundColor: isPresent ? context.colors.primary : Colors.grey.shade400,
                    child: Text(
                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isPresent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),

            // Co-Located indicator pill
            if (myCoGuests.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 12, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'Sharing mic (${myCoGuests.length})',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControlDeck() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          if (!_isSatelliteMode) ...[
            IconButton.filledTonal(
              onPressed: _togglePauseResume,
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(14),
                backgroundColor: _isPaused
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                    : context.colors.background,
              ),
              icon: Icon(
                _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: _isPaused ? const Color(0xFFF59E0B) : context.colors.textMain,
                size: 22,
              ),
              tooltip: _isPaused ? 'Resume' : 'Pause',
            ),
            const SizedBox(width: 12),
          ],

          Expanded(
            child: ElevatedButton.icon(
              onPressed: _endSession,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              label: Text(
                _isSatelliteMode ? 'Disconnect Table Mic' : 'End & Summarize Meeting',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSatelliteMode ? Colors.amber.shade800 : Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
