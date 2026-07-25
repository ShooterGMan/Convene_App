import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class PreJoinScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final String groupId;
  final String title;

  const PreJoinScreen({
    super.key,
    required this.meetingId,
    required this.groupId,
    required this.title,
  });

  @override
  ConsumerState<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends ConsumerState<PreJoinScreen> {
  LocalVideoTrack? _videoTrack;
  LocalAudioTrack? _audioTrack;
  bool _isMicMuted = false;
  bool _isCameraMuted = false;
  final _nameController = TextEditingController();

  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  MediaDevice? _selectedAudioInput;
  MediaDevice? _selectedVideoInput;

  @override
  void initState() {
    super.initState();
    // Pre-fill the name others (and the AI summary) will see, from the
    // profile - editable here so someone can correct it before joining.
    final profileName = ref.read(appUserProvider).name;
    if (profileName.isNotEmpty && profileName != 'Guest' && profileName != 'User') {
      _nameController.text = profileName;
    }
    _initLocalTracks();
  }

  Future<void> _initLocalTracks() async {
    try {
      _videoTrack = await LocalVideoTrack.createCameraTrack();
      _audioTrack = await LocalAudioTrack.create();

      // Fetch available devices
      final devices = await Hardware.instance.enumerateDevices();
      _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

      if (_audioInputs.isNotEmpty) _selectedAudioInput = _audioInputs.first;
      if (_videoInputs.isNotEmpty) _selectedVideoInput = _videoInputs.first;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Failed to create local tracks: $e");
    }
  }

  Future<void> _changeVideoDevice(MediaDevice? device) async {
    if (device == null) return;
    setState(() => _selectedVideoInput = device);
    // Restart camera with new device
    await _videoTrack?.dispose();
    _videoTrack = await LocalVideoTrack.createCameraTrack(
      CameraCaptureOptions(deviceId: device.deviceId),
    );
    if (mounted) setState(() {});
  }

  Future<void> _changeAudioDevice(MediaDevice? device) async {
    if (device == null) return;
    setState(() => _selectedAudioInput = device);
    // Restart mic with new device
    await _audioTrack?.dispose();
    _audioTrack = await LocalAudioTrack.create(
      AudioCaptureOptions(deviceId: device.deviceId),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _videoTrack?.dispose();
    _audioTrack?.dispose();
    super.dispose();
  }

  void _joinMeeting() {
    // Navigate to actual live meeting, passing the state
    context.pushReplacement(
      '/live/${widget.meetingId}',
      extra: {
        'groupId': widget.groupId,
        'title': widget.title,
        'isMicMuted': _isMicMuted,
        'isCameraMuted': _isCameraMuted,
        'displayName': _nameController.text.trim(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Devices')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your camera and microphone before joining.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Display name - what others and the AI summary will call you.
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: context.colors.textMain),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Your name in this meeting',
                      helperText: 'Used to label you in the recording & AI summary',
                      labelStyle: TextStyle(color: context.colors.textMuted),
                      filled: true,
                      fillColor: context.colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.badge_outlined, color: context.colors.textLight),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Video Preview Box
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.primary.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_videoTrack != null && !_isCameraMuted)
                            VideoTrackRenderer(_videoTrack!)
                          else
                            const Center(
                              child: Icon(
                                Icons.videocam_off,
                                size: 64,
                                color: Colors.white54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Device Selection Dropdowns
                  if (_videoInputs.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.videocam,
                          color: context.colors.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<MediaDevice>(
                            isExpanded: true,
                            value: _selectedVideoInput,
                            dropdownColor: context.colors.surface,
                            style: TextStyle(color: context.colors.textMain),
                            underline: const SizedBox(),
                            items: _videoInputs.map((device) {
                              return DropdownMenuItem(
                                value: device,
                                child: Text(
                                  device.label.isNotEmpty
                                      ? device.label
                                      : 'Camera ${device.deviceId}',
                                ),
                              );
                            }).toList(),
                            onChanged: _changeVideoDevice,
                          ),
                        ),
                      ],
                    ),
                  if (_audioInputs.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.mic,
                          color: context.colors.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<MediaDevice>(
                            isExpanded: true,
                            value: _selectedAudioInput,
                            dropdownColor: context.colors.surface,
                            style: TextStyle(color: context.colors.textMain),
                            underline: const SizedBox(),
                            items: _audioInputs.map((device) {
                              return DropdownMenuItem(
                                value: device,
                                child: Text(
                                  device.label.isNotEmpty
                                      ? device.label
                                      : 'Microphone ${device.deviceId}',
                                ),
                              );
                            }).toList(),
                            onChanged: _changeAudioDevice,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 32),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton(
                        heroTag: 'mic_toggle',
                        onPressed: () {
                          setState(() {
                            _isMicMuted = !_isMicMuted;
                          });
                        },
                        backgroundColor: _isMicMuted
                            ? Colors.red
                            : Colors.grey[200],
                        foregroundColor: _isMicMuted
                            ? Colors.white
                            : Colors.black,
                        child: Icon(_isMicMuted ? Icons.mic_off : Icons.mic),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: 'cam_toggle',
                        onPressed: () {
                          setState(() {
                            _isCameraMuted = !_isCameraMuted;
                          });
                        },
                        backgroundColor: _isCameraMuted
                            ? Colors.red
                            : Colors.grey[200],
                        foregroundColor: _isCameraMuted
                            ? Colors.white
                            : Colors.black,
                        child: Icon(
                          _isCameraMuted ? Icons.videocam_off : Icons.videocam,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),

                  // Join Button - requires a name so nobody joins as "Speaker".
                  ElevatedButton(
                    onPressed: _nameController.text.trim().isEmpty ? null : _joinMeeting,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: context.colors.primary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    child: Text(
                      _nameController.text.trim().isEmpty ? 'Enter your name to join' : 'Join Meeting',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
