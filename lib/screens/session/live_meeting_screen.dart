import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
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
  bool _isSpeakerView = false;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  // Reactions
  String? _currentReaction;

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
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('getLivekitToken').call({
        'meetingId': widget.meetingId,
        'groupId': widget.groupId,
        'displayName': widget.displayName,
      });

      final String token = result.data['token'];
      
      const String livekitUrl = "wss://convene-app-a9liwgoq.livekit.cloud";

      _listener = _room.createListener();
      _listener!.on<DataReceivedEvent>((event) {
        final text = utf8.decode(event.data);
        if (mounted) {
          if (text.startsWith('REACTION:')) {
            final emoji = text.substring(9);
            _showReaction(emoji);
          } else {
            setState(() {
              _messages.add({
                'sender': event.participant?.name.isNotEmpty == true ? event.participant!.name : (event.participant?.identity ?? 'Unknown'),
                'text': text,
              });
            });
          }
        }
      });
      
      await _room.connect(livekitUrl, token);
      
      if (!widget.isCameraMuted) {
        await _room.localParticipant?.setCameraEnabled(true);
      }
      if (!widget.isMicMuted) {
        await _room.localParticipant?.setMicrophoneEnabled(true);
      }

      setState(() {
        _isConnecting = false;
      });
      _startElapsedTimer();
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
    _chatController.dispose();
    _elapsedTimer?.cancel();
    _listener?.dispose();
    _room.disconnect();
    _room.dispose();
    // Safety net in case screen share was left on when the meeting ended.
    _setAndroidScreenShareForegroundService(false);
    super.dispose();
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

    if (isLastParticipant) {
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

  Future<void> _stopEgressInBackground() async {
    try {
      await FirebaseFunctions.instance.httpsCallable('stopMeetingEgress').call({
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
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact "recording" indicator - a pulsing red dot + elapsed
            // time. The old full-width "AI Recording Meeting" pill overflowed
            // into the action buttons on narrow phones.
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 700.ms)
                .then()
                .fadeOut(duration: 700.ms),
            const SizedBox(width: 8),
            Text(
              _formattedElapsed,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.auto_awesome, size: 15, color: context.colors.primary),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Invite Others',
            onPressed: () {
              final link = 'https://meeting-app-844aa.web.app/pre-join/${widget.meetingId}';
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Meeting link copied! Share it with others to join.'))
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.call_end),
            color: Colors.red,
            tooltip: 'End Meeting',
            onPressed: _leaveMeeting,
          )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;

          return Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    VideoGrid(room: _room, isSpeakerView: _isSpeakerView),

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

  Widget _buildControls(bool isDesktop) {
    final localParticipant = _room.localParticipant;
    if (localParticipant == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
          IconButton(
            icon: Icon(
              localParticipant.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
              color: Colors.white,
            ),
            onPressed: () async {
              final enabled = localParticipant.isMicrophoneEnabled();
              await localParticipant.setMicrophoneEnabled(!enabled);
              setState(() {});
            },
          ),
          IconButton(
            icon: Icon(
              localParticipant.isCameraEnabled() ? Icons.videocam : Icons.videocam_off,
              color: Colors.white,
            ),
            onPressed: () async {
              final enabled = localParticipant.isCameraEnabled();
              await localParticipant.setCameraEnabled(!enabled);
              setState(() {});
            },
          ),
          if (_screenShareSupported)
            IconButton(
              icon: Icon(
                localParticipant.isScreenShareEnabled() ? Icons.stop_screen_share : Icons.screen_share,
                color: Colors.white,
              ),
              tooltip: 'Share screen',
              onPressed: () async {
                final enabled = localParticipant.isScreenShareEnabled();
                final turningOn = !enabled;
                // Must be running before capture starts, so start it first;
                // safe to stop only after capture has actually turned off.
                if (turningOn) await _setAndroidScreenShareForegroundService(true);
                try {
                  await localParticipant.setScreenShareEnabled(turningOn);
                } finally {
                  if (!turningOn) await _setAndroidScreenShareForegroundService(false);
                }
                setState(() {});
              },
            ),

          Container(width: 1, height: 32, color: Colors.grey.shade800),

          // Layout Toggle
          IconButton(
            icon: Icon(
              _isSpeakerView ? Icons.dashboard : Icons.person,
              color: Colors.white,
            ),
            tooltip: 'Toggle Layout',
            onPressed: () {
              setState(() => _isSpeakerView = !_isSpeakerView);
            },
          ),

          // Chat Toggle
          IconButton(
            icon: Icon(Icons.chat, color: _isChatVisible ? Colors.blue : Colors.white),
            tooltip: 'Chat',
            onPressed: () {
              if (isDesktop) {
                setState(() => _isChatVisible = !_isChatVisible);
              } else {
                _showMobileChatSheet();
              }
            },
          ),

          Container(width: 1, height: 32, color: Colors.grey.shade800),

          // Reactions
          _buildReactionButton('👍'),
          _buildReactionButton('❤️'),
          _buildReactionButton('👏'),
          _buildReactionButton('😂'),
        ],
      ),
    )));
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
                if (MediaQuery.of(context).size.width < 800)
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final p = participants[index];
        final isMe = p is LocalParticipant;
        final isSpeaking = p.isSpeaking;
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSpeaking ? Colors.blue : Colors.grey.shade700,
            child: Text(
              p.identity.isNotEmpty ? p.identity[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(
            isMe ? 'You' : p.name.isNotEmpty ? p.name : p.identity,
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
      },
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
      });
      _chatController.clear();
    });
  }

  Widget _buildReactionButton(String emoji) {
    return IconButton(
      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
      onPressed: () {
        // Show locally immediately so the sender always sees their own
        // reaction even if the network publish is momentarily unavailable.
        _showReaction(emoji);
        // Broadcast to others (reliable so it isn't dropped).
        final lp = _room.localParticipant;
        if (lp != null) {
          final data = utf8.encode('REACTION:$emoji');
          lp.publishData(data, reliable: true);
        }
      },
    );
  }
}

class VideoGrid extends StatefulWidget {
  final Room room;
  final bool isSpeakerView;
  const VideoGrid({super.key, required this.room, required this.isSpeakerView});

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  List<Participant> _participants = [];
  Participant? _activeSpeaker;
  // When set, this participant stays "featured" regardless of who's talking -
  // lets someone keep themselves (or anyone else) big instead of the view
  // always jumping to whoever's currently speaking.
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

    // Fallback if active speaker left the room
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

    if (widget.isSpeakerView) {
      final pinned = _pinnedIdentity == null
          ? null
          : _participants.where((p) => p.identity == _pinnedIdentity).firstOrNull;
      // A stale pin (participant left) falls back to auto speaker-follow.
      if (_pinnedIdentity != null && pinned == null) _pinnedIdentity = null;
      final mainParticipant = pinned ?? _activeSpeaker ?? _participants.first;
      final others = _participants.where((p) => p.identity != mainParticipant.identity).toList();
      final isPinned = pinned != null;

      return Column(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Stack(
                children: [
                  Positioned.fill(child: VideoWidget(participant: mainParticipant)),
                  if (isPinned)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _pinnedIdentity = null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.push_pin, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Pinned - tap to unpin', style: TextStyle(color: Colors.white, fontSize: 11)),
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
            Expanded(
              flex: 1,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                scrollDirection: Axis.horizontal,
                itemCount: others.length,
                itemBuilder: (context, index) {
                  final p = others[index];
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
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
    }

    int crossAxisCount = 1;
    if (_participants.length > 1 && _participants.length <= 4) {
      crossAxisCount = 2;
    } else if (_participants.length > 4) {
      crossAxisCount = 3;
    }

    final grid = GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 16 / 9,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _participants.length,
      itemBuilder: (context, index) {
        return VideoWidget(participant: _participants[index]);
      },
    );

    // Alone in the room - reassure the user it's working and they're just
    // waiting, rather than leaving a single silent tile that looks stuck.
    if (_participants.length == 1) {
      return Column(
        children: [
          Expanded(child: grid),
          Padding(
            padding: const EdgeInsets.only(bottom: 96, left: 24, right: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Waiting for others to join. Share the invite link from the top bar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return grid;
  }

}

class VideoWidget extends StatefulWidget {
  final Participant participant;

  const VideoWidget({super.key, required this.participant});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  EventsListener<ParticipantEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    _listener!.on<SpeakingChangedEvent>((event) {
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
    // Prioritize screen share if available
    var videoTrack = widget.participant.videoTrackPublications
        .where((p) => p.source == TrackSource.screenShareVideo)
        .firstOrNull?.track as VideoTrack?;
        
    final isScreenShare = videoTrack != null;
    final isSpeaking = widget.participant.isSpeaking;

    if (videoTrack == null) {
      videoTrack = widget.participant.videoTrackPublications
          .where((p) => p.source == TrackSource.camera)
          .firstOrNull?.track as VideoTrack?;
    }
    
    // Fallback if no specific source found
    videoTrack ??= widget.participant.videoTrackPublications.firstOrNull?.track as VideoTrack?;
    
    // Base decoration
    final boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: Colors.black,
      border: isSpeaking 
          ? Border.all(color: Colors.blueAccent, width: 3)
          : Border.all(color: Colors.transparent, width: 3),
      boxShadow: isSpeaking 
          ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
          : [],
    );

    if (videoTrack != null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
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
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Screen Share', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.participant.isMicrophoneEnabled()) ...[
                      const Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
                      const SizedBox(width: 4),
                    ] else if (isSpeaking) ...[
                      const Icon(Icons.volume_up, color: Colors.blueAccent, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      widget.participant.name.isNotEmpty ? widget.participant.name : widget.participant.identity,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: isSpeaking 
              ? Border.all(color: Colors.blueAccent, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: isSpeaking 
              ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]
              : [],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.participant.isMicrophoneEnabled())
                const Icon(Icons.mic_off, color: Colors.redAccent, size: 32)
              else if (isSpeaking)
                const Icon(Icons.volume_up, color: Colors.blueAccent, size: 32)
              else
                const Icon(Icons.person, color: Colors.white54, size: 32),
              const SizedBox(height: 8),
              Text(
                widget.participant.name.isNotEmpty ? widget.participant.name : widget.participant.identity,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
  }
}
