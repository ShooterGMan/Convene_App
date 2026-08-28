import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/background_meeting_service.dart';
import '../../theme/app_theme.dart';

/// Android requires an active foreground service (of type "mediaProjection")
/// running BEFORE screen capture starts, or it fails outright - flutter_webrtc
/// doesn't provide one, so the app starts/stops a minimal native one around
/// the screen-share toggle. No-op on every other platform.
const _screenShareChannel = MethodChannel('com.convene.convene/screen_share');
bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Mobile web browsers (Chrome/Brave/Firefox/Safari on phones) don't implement
/// getDisplayMedia, so screen sharing is impossible there - it only works in a
/// desktop browser or the native app. We hide the button in that case rather
/// than show one that silently fails.
bool get _screenShareSupported {
  if (!kIsWeb) return true; // native apps handle it via MediaProjection/ReplayKit
  return defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS;
}

Future<void> _setAndroidScreenShareForegroundService(bool active) async {
  if (!_isAndroid) return;
  try {
    await _screenShareChannel.invokeMethod(active ? 'start' : 'stop');
  } catch (e) {
    debugPrint('Screen share foreground service call failed: $e');
  }
}

class LiveMeetingScreen extends StatefulWidget {
  final String meetingId;
  final String groupId;
  final bool isMicMuted;
  final bool isCameraMuted;
  final String displayName;

  const LiveMeetingScreen({
    super.key,
    required this.meetingId,
    required this.groupId,
    this.isMicMuted = false,
    this.isCameraMuted = false,
    this.displayName = '',
  });

  @override
  State<LiveMeetingScreen> createState() => _LiveMeetingScreenState();
}

class _LiveMeetingScreenState extends State<LiveMeetingScreen> {
  late Room _room;
  EventsListener<RoomEvent>? _listener;
  bool _isConnecting = true;
  String? _errorMessage;

  // UI States
  bool _isChatVisible = false;
  int _unreadChatCount = 0;
  bool _isSpeakerView = false;
  bool _isHandRaised = false;
  final List<String> _raisedHandQueue = [];
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  // Reactions
  String? _currentReaction;

  // Live Captions & Subtitles
  bool _showSubtitles = true;
  String? _currentCaption;
  String? _currentCaptionSpeaker;
  Timer? _captionTimer;
  String? _liveHighlightBadge;
  Timer? _highlightTimer;

  // Elapsed-time timer (no hard cutoff - just a running counter)
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  String get _formattedElapsed {
    final duration = Duration(seconds: _elapsedSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '${hours.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
  }

  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable failed: $e');
    }
    _connectToRoom();
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _connectToRoom() async {
    _room = Room();
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final result = await functions.httpsCallable('getLivekitToken').call({
        'meetingId': widget.meetingId,
        'groupId': widget.groupId,
        'displayName': widget.displayName,
      });

      final String token = result.data['token'];
      
      const String livekitUrl = "wss://convene-app-a9liwgoq.livekit.cloud";

      _listener = _room.createListener();
      _listener!
        ..on<DataReceivedEvent>((event) {
          final text = utf8.decode(event.data);
          if (mounted) {
            if (text.startsWith('REACTION:')) {
              final emoji = text.substring(9);
              _showReaction(emoji);
            } else if (text.startsWith('HAND_RAISE:')) {
              final identity = text.substring(11);
              if (!_raisedHandQueue.contains(identity)) {
                setState(() => _raisedHandQueue.add(identity));
              }
            } else if (text.startsWith('HAND_LOWER:')) {
              final identity = text.substring(11);
              setState(() => _raisedHandQueue.remove(identity));
            } else if (text.startsWith('CAPTION:')) {
              final parts = text.substring(8).split(':');
              final speaker = parts.first;
              final captionText = parts.skip(1).join(':');
              _captionTimer?.cancel();
              setState(() {
                _currentCaptionSpeaker = speaker;
                _currentCaption = captionText;
              });
              _captionTimer = Timer(const Duration(seconds: 4), () {
                if (mounted) setState(() => _currentCaption = null);
              });
            } else if (text.startsWith('HIGHLIGHT:')) {
              final highlight = text.substring(10);
              _highlightTimer?.cancel();
              setState(() {
                _liveHighlightBadge = highlight;
              });
              _highlightTimer = Timer(const Duration(seconds: 5), () {
                if (mounted) setState(() => _liveHighlightBadge = null);
              });
            } else {
              setState(() {
                _messages.add({
                  'sender': event.participant?.name.isNotEmpty == true
                      ? event.participant!.name
                      : (event.participant?.identity ?? 'Unknown'),
                  'text': text,
                  'time': DateTime.now(),
                });
                if (!_isChatVisible) {
                  _unreadChatCount++;
                }
              });
            }
          }
        })
        ..on<ActiveSpeakersChangedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackMutedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnmutedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackPublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackUnpublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<RoomReconnectingEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<RoomReconnectedEvent>((_) {
          if (mounted) setState(() {});
        });
      
      if (!kIsWeb) {
        try {
          await [
            Permission.microphone,
            Permission.camera,
            Permission.bluetoothConnect,
          ].request();
        } catch (e) {
          debugPrint('Mobile permission request error: $e');
        }
      }

      await _room.connect(livekitUrl, token);
      
      if (!widget.isCameraMuted) {
        try {
          await _room.localParticipant?.setCameraEnabled(true);
        } catch (e) {
          debugPrint('Camera enable error on Android: $e');
        }
      }
      if (!widget.isMicMuted) {
        try {
          await _room.localParticipant?.setMicrophoneEnabled(true);
        } catch (e) {
          debugPrint('Microphone enable error on Android: $e');
        }
      }

      setState(() {
        _isConnecting = false;
      });
      _startElapsedTimer();
      try {
        BackgroundMeetingService.start(
          title: 'Meeting Active',
          text: widget.displayName.isNotEmpty ? 'Active meeting as ${widget.displayName}' : 'Your meeting is active in the background',
        );
      } catch (e) {
        debugPrint('Background service start ignored: $e');
      }
    } catch (e) {
      debugPrint("Backend connection failed: $e");
      
      setState(() {
        _isConnecting = false;
        _errorMessage = e.toString(); 
      });
    }
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable failed: $e');
    }
    _chatController.dispose();
    _elapsedTimer?.cancel();
    _listener?.dispose();
    _room.disconnect();
    _room.dispose();
    // Stop background meeting foreground service.
    BackgroundMeetingService.stop();
    _setAndroidScreenShareForegroundService(false);
    super.dispose();
  }

  void _toggleHandRaise() {
    final myIdentity = _room.localParticipant?.identity;
    if (myIdentity == null) return;

    setState(() {
      _isHandRaised = !_isHandRaised;
      if (_isHandRaised) {
        if (!_raisedHandQueue.contains(myIdentity)) _raisedHandQueue.add(myIdentity);
      } else {
        _raisedHandQueue.remove(myIdentity);
      }
    });

    final msg = _isHandRaised ? 'HAND_RAISE:$myIdentity' : 'HAND_LOWER:$myIdentity';
    _room.localParticipant?.publishData(utf8.encode(msg));
  }

  void _lowerParticipantHand(String identity) {
    setState(() => _raisedHandQueue.remove(identity));
    if (identity == _room.localParticipant?.identity) {
      setState(() => _isHandRaised = false);
    }
    _room.localParticipant?.publishData(utf8.encode('HAND_LOWER:$identity'));
  }

  void _showReaction(String emoji) {
    setState(() {
      _currentReaction = emoji;
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _currentReaction = null);
    });
  }

  /// Leaves the room. Transcription and summarization happen entirely server-side
  /// (a LiveKit egress bot records the whole room and a Cloud Function summarizes it
  /// once the room is empty), so the client has nothing to send - it just leaves.
  /// If this is the last participant, proactively (but not blockingly) stop the
  /// egress so the summary doesn't wait on LiveKit's default empty-room timeout.
  /// The stop-egress network call can take a few seconds (or longer on a bad
  /// connection), and there's nothing for the user to wait for - the room
  /// disconnect itself happens locally in dispose() - so leaving must not
  /// block on it, or "End Meeting" feels stuck/unresponsive.
  void _leaveMeeting() {
    final isLastParticipant = _room.remoteParticipants.isEmpty;

    // Only interrupt with a confirmation when leaving actually ends the
    // recording for everyone (i.e. you're the last one here). If others are
    // still in the room, leaving is low-stakes - just go.
    if (!isLastParticipant) {
      _performLeave(stopRecording: false);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Leave and end recording?'),
        content: const Text(
          "You're the last person here. Leaving stops the recording and starts "
          'generating the AI summary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _performLeave(stopRecording: true);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _performLeave({required bool stopRecording}) {
    if (stopRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meeting ended. AI summary is generating in the background...'),
          duration: Duration(seconds: 4),
        ),
      );
      _stopEgressInBackground();
    }

    // Someone who opened a direct meeting link has no back-stack to pop to,
    // so pop() would silently do nothing and "hang up" looks broken. Fall
    // back to navigating home in that case.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/upcoming');
    }
  }

  void _copyInviteLink() {
    final link = 'https://meeting-app-844aa.web.app/pre-join/${widget.meetingId}';
    Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite link copied! Share it so others can join.')),
      );
    }
  }

  void _sendReaction(String emoji) {
    // Show locally immediately so the sender always sees their own reaction
    // even if the network publish is momentarily unavailable.
    _showReaction(emoji);
    final lp = _room.localParticipant;
    if (lp != null) {
      lp.publishData(utf8.encode('REACTION:$emoji'), reliable: true);
    }
  }

  Future<void> _stopEgressInBackground() async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('stopMeetingEgress').call({
        'meetingId': widget.meetingId,
      });
    } catch (e) {
      debugPrint("Failed to stop egress: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Failed to connect: $_errorMessage')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        // Leaving happens only through the deliberate Leave button in the
        // control bar (which handles egress/confirmation), so suppress the
        // implicit back arrow that would bypass it.
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            // Small persistent recording indicator in plain language.
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 700.ms)
                .then()
                .fadeOut(duration: 700.ms),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Recording for summary',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textMain),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formattedElapsed,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;

          return Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    VideoGrid(room: _room, isSpeakerView: _isSpeakerView, onCopyInvite: _copyInviteLink),

                    // Reactions Overlay
                    if (_currentReaction != null)
                      Positioned(
                        top: MediaQuery.of(context).size.height / 3,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value < 0.8 ? value : (1 - value) * 5,
                                child: Transform.scale(
                                  scale: 1 + value,
                                  child: Text(
                                    _currentReaction!,
                                    style: const TextStyle(fontSize: 100),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // Live Highlight Toast Overlay
                    if (_liveHighlightBadge != null)
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Center(child: _LiveHighlightToast(highlightText: _liveHighlightBadge!)),
                      ),

                    // Live Captions & Subtitles Overlay
                    if (_showSubtitles && _currentCaption != null)
                      Positioned(
                        bottom: 90,
                        left: 16,
                        right: 16,
                        child: _LiveCaptionsOverlay(
                          speaker: _currentCaptionSpeaker ?? 'Speaker',
                          caption: _currentCaption!,
                        ),
                      ),

                    // Floating Glassmorphic Controls Overlay
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildControls(isDesktop),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop && _isChatVisible)
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: Colors.grey.shade800)),
                    color: Colors.grey.shade900,
                  ),
                  child: _buildChatPanel(),
                ),
            ],
          );
        }
      ),
    );
  }

  /// Compact floating control bar: only the essentials (mic, camera, share,
  /// More, Leave). Everything secondary - chat, participants, reactions,
  /// layout, invite link, recording status - lives behind the More menu so the
  /// bar stays calm and never overflows on a narrow phone.
  Widget _buildControls(bool isDesktop) {
    final lp = _room.localParticipant;
    if (lp == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _controlButton(
                icon: lp.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                tooltip: lp.isMicrophoneEnabled() ? 'Mute' : 'Unmute',
                background: lp.isMicrophoneEnabled() ? null : Colors.red.shade600,
                onTap: () async {
                  await lp.setMicrophoneEnabled(!lp.isMicrophoneEnabled());
                  setState(() {});
                },
              ),
              const SizedBox(width: 10),
              _controlButton(
                icon: lp.isCameraEnabled() ? Icons.videocam : Icons.videocam_off,
                tooltip: lp.isCameraEnabled() ? 'Stop camera' : 'Start camera',
                background: lp.isCameraEnabled() ? null : Colors.red.shade600,
                onTap: () async {
                  await lp.setCameraEnabled(!lp.isCameraEnabled());
                  setState(() {});
                },
              ),
              const SizedBox(width: 10),
              _controlButton(
                icon: Icons.front_hand_rounded,
                tooltip: _isHandRaised ? 'Lower hand' : 'Raise hand',
                background: _isHandRaised ? Colors.amber.shade700 : null,
                onTap: _toggleHandRaise,
              ),
              if (_screenShareSupported) ...[
                const SizedBox(width: 10),
                _controlButton(
                  icon: lp.isScreenShareEnabled() ? Icons.stop_screen_share : Icons.screen_share,
                  tooltip: 'Share screen',
                  background: lp.isScreenShareEnabled() ? Colors.blue : null,
                  onTap: () async {
                    final turningOn = !lp.isScreenShareEnabled();
                    // Must be running before capture starts, so start it first;
                    // safe to stop only after capture has actually turned off.
                    if (turningOn) await _setAndroidScreenShareForegroundService(true);
                    try {
                      await lp.setScreenShareEnabled(turningOn);
                    } finally {
                      if (!turningOn) await _setAndroidScreenShareForegroundService(false);
                    }
                    setState(() {});
                  },
                ),
              ],
              const SizedBox(width: 10),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _controlButton(
                    icon: Icons.more_horiz,
                    tooltip: 'More',
                    onTap: () => _showMoreMenu(isDesktop),
                  ),
                  if (_unreadChatCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            '$_unreadChatCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              _buildLeaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color? background,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: background ?? Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
  }

  /// Leave is clearly distinct (red, labelled) but modestly sized - not an
  /// alarming full-width button.
  Widget _buildLeaveButton() {
    return Tooltip(
      message: 'Leave meeting',
      child: GestureDetector(
        onTap: _leaveMeeting,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_end, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Leave', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  /// Secondary actions live here so the control bar stays minimal.
  void _showMoreMenu(bool isDesktop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              // Recording status, spelled out plainly.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recording for summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('Audio is transcribed to build your AI summary.',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(
                      _formattedElapsed,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 28),
              _moreTile(sheetCtx, Icons.person_add, 'Copy invite link', _copyInviteLink),
              _moreTile(
                sheetCtx,
                Icons.forum_rounded,
                'Chat & people',
                () {
                  setState(() => _unreadChatCount = 0);
                  if (isDesktop) {
                    setState(() => _isChatVisible = true);
                  } else {
                    _showMobileChatSheet();
                  }
                },
                badgeCount: _unreadChatCount,
              ),
              _moreTile(
                sheetCtx,
                _showSubtitles ? Icons.closed_caption_rounded : Icons.closed_caption_disabled_rounded,
                _showSubtitles ? 'Hide live captions' : 'Show live captions',
                () {
                  setState(() => _showSubtitles = !_showSubtitles);
                  setSheetState(() {});
                },
              ),
              _moreTile(
                sheetCtx,
                _isSpeakerView ? Icons.grid_view_rounded : Icons.person_rounded,
                _isSpeakerView ? 'Grid view' : 'Speaker view',
                () => setState(() => _isSpeakerView = !_isSpeakerView),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final emoji in const ['👍', '❤️', '👏', '😂', '🎉', '🙌'])
                      _sheetReaction(sheetCtx, emoji),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreTile(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    VoidCallback onTap, {
    int badgeCount = 0,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      trailing: badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$badgeCount new',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );
  }

  Widget _sheetReaction(BuildContext sheetCtx, String emoji) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        _sendReaction(emoji);
      },
      child: Text(emoji, style: const TextStyle(fontSize: 30)),
    );
  }

  void _showMobileChatSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _buildChatPanel(),
          ),
        );
      },
    );
  }

  Widget _buildChatPanel() {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Meeting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    // Mobile shows the panel as a modal sheet (pop it); desktop
                    // shows it as an inline side panel (hide via state).
                    if (MediaQuery.of(context).size.width < 800) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _isChatVisible = false);
                    }
                  },
                ),
              ],
            ),
          ),
          const TabBar(
            indicatorColor: Colors.blue,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Chat'),
              Tab(text: 'People'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Chat Tab
                Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text('No messages yet.', style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isMe = msg['sender'] == 'You';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe ? Colors.blue.shade700 : Colors.grey.shade800,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Text(msg['sender'], style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text(msg['text'], style: const TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: const TextStyle(color: Colors.grey),
                                filled: true,
                                fillColor: Colors.black45,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.blue),
                            onPressed: _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // Participants Tab
                _buildParticipantsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsList() {
    final participants = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_raisedHandQueue.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade900.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade600.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.front_hand_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'HAND RAISE QUEUE (${_raisedHandQueue.length})',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._raisedHandQueue.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final id = entry.value;
                  final p = participants.firstWhere(
                    (user) => user.identity == id,
                    orElse: () => _room.localParticipant!,
                  );
                  final name = p is LocalParticipant ? 'You' : (p.name.isNotEmpty ? p.name : p.identity);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: () => _lowerParticipantHand(id),
                          child: const Text('Lower', style: TextStyle(color: Colors.amber, fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        ...participants.map((p) {
          final isMe = p is LocalParticipant;
          final isSpeaking = p.isSpeaking;
          final hasHandRaised = _raisedHandQueue.contains(p.identity);

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: isSpeaking ? Colors.blue : Colors.grey.shade700,
                  child: Text(
                    p.identity.isNotEmpty ? p.identity[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (hasHandRaised)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                      child: const Icon(Icons.front_hand_rounded, size: 10, color: Colors.black),
                    ),
                  ),
              ],
            ),
            title: Text(
              isMe ? 'You' : (p.name.isNotEmpty ? p.name : p.identity),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
                  color: p.isMicrophoneEnabled() ? (isSpeaking ? Colors.blue : Colors.white) : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Icon(
                  p.isCameraEnabled() ? Icons.videocam : Icons.videocam_off,
                  color: p.isCameraEnabled() ? Colors.white : Colors.red,
                  size: 20,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    // reliable:true so chat messages aren't silently dropped on a lossy
    // connection (the default data channel is best-effort/unreliable).
    final data = utf8.encode(text);
    await _room.localParticipant?.publishData(data, reliable: true);

    setState(() {
      _messages.add({
        'sender': 'You',
        'text': text,
        'time': DateTime.now(),
      });
      _chatController.clear();
    });
  }

}

String _getParticipantInitials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return clean[0].toUpperCase();
}

LinearGradient _getAvatarGradient(String name) {
  final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
  final colorsList = [
    [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
    [const Color(0xFF0EA5E9), const Color(0xFF2563EB)],
    [const Color(0xFF10B981), const Color(0xFF059669)],
    [const Color(0xFFF59E0B), const Color(0xFFD97706)],
    [const Color(0xFFEC4899), const Color(0xFFD946EF)],
    [const Color(0xFF14B8A6), const Color(0xFF0D9488)],
  ];
  final pair = colorsList[hash % colorsList.length];
  return LinearGradient(colors: pair, begin: Alignment.topLeft, end: Alignment.bottomRight);
}

class VideoGrid extends StatefulWidget {
  final Room room;
  final bool isSpeakerView;
  final VoidCallback? onCopyInvite;

  const VideoGrid({
    super.key,
    required this.room,
    required this.isSpeakerView,
    this.onCopyInvite,
  });

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  List<Participant> _participants = [];
  Participant? _activeSpeaker;
  String? _pinnedIdentity;

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_updateParticipants);
    _updateParticipants();
  }

  @override
  void dispose() {
    widget.room.removeListener(_updateParticipants);
    super.dispose();
  }

  void _updateParticipants() {
    final participants = <Participant>[
      if (widget.room.localParticipant != null) widget.room.localParticipant!,
      ...widget.room.remoteParticipants.values,
    ];

    if (widget.room.activeSpeakers.isNotEmpty) {
      _activeSpeaker = widget.room.activeSpeakers.first;
    } else if (_activeSpeaker == null && participants.isNotEmpty) {
      _activeSpeaker = participants.first;
    }

    if (_activeSpeaker != null && !participants.any((p) => p.identity == _activeSpeaker!.identity)) {
      _activeSpeaker = participants.isNotEmpty ? participants.first : null;
    }

    setState(() {
      _participants = participants;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_participants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70),
            SizedBox(height: 16),
            Text('Connecting to meeting…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        // Auto-detect screen sharing participant
        final screenSharingParticipant = _participants.where((p) {
          return p.videoTrackPublications.any((pub) => pub.source == TrackSource.screenShareVideo);
        }).firstOrNull;

        if (widget.isSpeakerView) {
          final pinned = _pinnedIdentity == null
              ? null
              : _participants.where((p) => p.identity == _pinnedIdentity).firstOrNull;
          if (_pinnedIdentity != null && pinned == null) _pinnedIdentity = null;

          final mainParticipant = pinned ?? screenSharingParticipant ?? _activeSpeaker ?? _participants.first;
          final others = _participants.where((p) => p.identity != mainParticipant.identity).toList();
          final isPinned = pinned != null;

          if (isDesktop) {
            // Web / Desktop Landscape: Large main speaker on left, vertical sidebar on right
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 6, 95),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: VideoWidget(participant: mainParticipant, isMainSpeaker: true),
                        ),
                        if (isPinned)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => setState(() => _pinnedIdentity = null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin, size: 14, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text('Pinned · Tap to unpin', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (others.isNotEmpty)
                  SizedBox(
                    width: 230,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(6, 12, 12, 95),
                      itemCount: others.length,
                      itemBuilder: (context, index) {
                        final p = others[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: GestureDetector(
                              onTap: () => setState(() => _pinnedIdentity = p.identity),
                              child: VideoWidget(participant: p),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          } else {
            // Mobile Portrait: Large main speaker on top, horizontal bottom strip
            return Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: VideoWidget(participant: mainParticipant, isMainSpeaker: true),
                        ),
                        if (isPinned)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: GestureDetector(
                              onTap: () => setState(() => _pinnedIdentity = null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin, size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('Pinned', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (others.isNotEmpty)
                  SizedBox(
                    height: 115,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 85),
                      scrollDirection: Axis.horizontal,
                      itemCount: others.length,
                      itemBuilder: (context, index) {
                        final p = others[index];
                        return AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onTap: () => setState(() => _pinnedIdentity = p.identity),
                              child: VideoWidget(participant: p),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  const SizedBox(height: 85),
              ],
            );
          }
        }

        // ── Grid View ──
        int crossAxisCount;
        double childAspectRatio;

        if (isDesktop) {
          if (_participants.length <= 2) {
            crossAxisCount = _participants.length;
            childAspectRatio = 16 / 9;
          } else if (_participants.length <= 4) {
            crossAxisCount = 2;
            childAspectRatio = 16 / 9;
          } else if (_participants.length <= 9) {
            crossAxisCount = 3;
            childAspectRatio = 16 / 9;
          } else {
            crossAxisCount = 4;
            childAspectRatio = 16 / 9;
          }
        } else {
          // Mobile Grid View
          if (_participants.length == 1) {
            crossAxisCount = 1;
            childAspectRatio = 0.9;
          } else if (_participants.length == 2) {
            crossAxisCount = 1;
            childAspectRatio = 1.35;
          } else {
            crossAxisCount = 2;
            childAspectRatio = 1.15;
          }
        }

        final grid = GridView.builder(
          padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 95),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _participants.length,
          itemBuilder: (context, index) {
            return VideoWidget(participant: _participants[index]);
          },
        );

        if (_participants.length == 1) {
          return Stack(
            children: [
              Positioned.fill(child: grid),
              Positioned(
                bottom: 95,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "You're the only one here",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (widget.onCopyInvite != null) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: widget.onCopyInvite,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_rounded, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Copy Link', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return grid;
      },
    );
  }
}

class VideoWidget extends StatefulWidget {
  final Participant participant;
  final bool isMainSpeaker;

  const VideoWidget({
    super.key,
    required this.participant,
    this.isMainSpeaker = false,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  EventsListener<ParticipantEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    _listener!
      ..on<SpeakingChangedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackPublishedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnpublishedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackMutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnmutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackSubscribedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnsubscribedEvent>((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var videoTrack = widget.participant.videoTrackPublications
        .where((p) => p.source == TrackSource.screenShareVideo)
        .firstOrNull?.track as VideoTrack?;

    final isScreenShare = videoTrack != null;
    final isSpeaking = widget.participant.isSpeaking;

    videoTrack ??= widget.participant.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .firstOrNull?.track as VideoTrack?;

    videoTrack ??= widget.participant.videoTrackPublications.firstOrNull?.track as VideoTrack?;

    final displayName = widget.participant.name.isNotEmpty
        ? widget.participant.name
        : (widget.participant.identity.isNotEmpty ? widget.participant.identity : 'Guest');

    final primaryAccent = context.colors.primary;
    final initials = _getParticipantInitials(displayName);
    final avatarGradient = _getAvatarGradient(displayName);

    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.md),
      color: const Color(0xFF161A22),
      border: isSpeaking
          ? Border.all(color: primaryAccent, width: 2.5)
          : Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
      boxShadow: isSpeaking
          ? [
              BoxShadow(
                color: primaryAccent.withValues(alpha: 0.5),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ]
          : [],
    );

    if (videoTrack != null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        clipBehavior: Clip.antiAlias,
        decoration: boxDecoration,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoTrackRenderer(videoTrack),
            if (isScreenShare)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.screen_share_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Screen Share', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Builder(
                builder: (context) {
                  final isHandRaised = context.findAncestorStateOfType<_LiveMeetingScreenState>()?._raisedHandQueue.contains(widget.participant.identity) ?? false;
                  if (!isHandRaised) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.front_hand_rounded, color: Colors.black, size: 12),
                        SizedBox(width: 4),
                        Text('Hand Raised', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.participant.isMicrophoneEnabled()) ...[
                      const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 13),
                      const SizedBox(width: 4),
                    ] else if (isSpeaking) ...[
                      Icon(Icons.graphic_eq_rounded, color: primaryAccent, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      displayName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // ── Camera OFF Avatar View ──
      final avatarSize = widget.isMainSpeaker ? 72.0 : 48.0;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: boxDecoration,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: avatarGradient,
                      boxShadow: isSpeaking
                          ? [
                              BoxShadow(
                                color: primaryAccent.withValues(alpha: 0.6),
                                blurRadius: 16,
                                spreadRadius: 4,
                              )
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                              )
                            ],
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: widget.isMainSpeaker ? 26 : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displayName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Builder(
                builder: (context) {
                  final isHandRaised = context.findAncestorStateOfType<_LiveMeetingScreenState>()?._raisedHandQueue.contains(widget.participant.identity) ?? false;
                  if (!isHandRaised) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.front_hand_rounded, color: Colors.black, size: 12),
                        SizedBox(width: 4),
                        Text('Hand Raised', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.participant.isMicrophoneEnabled()) ...[
                      const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 13),
                      const SizedBox(width: 4),
                    ] else if (isSpeaking) ...[
                      Icon(Icons.graphic_eq_rounded, color: primaryAccent, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      displayName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _LiveCaptionsOverlay extends StatelessWidget {
  final String speaker;
  final String caption;

  const _LiveCaptionsOverlay({required this.speaker, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.closed_caption_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$speaker: ',
                    style: GoogleFonts.plusJakartaSans(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: caption,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0, duration: 250.ms);
  }
}

class _LiveHighlightToast extends StatelessWidget {
  final String highlightText;

  const _LiveHighlightToast({required this.highlightText});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            highlightText,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1));
  }
}
