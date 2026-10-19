import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/firestore_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_audio_analyser.dart';
import '../../widgets/recording_consent.dart';
import '../../models/meeting.dart';

class PreJoinScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final String groupId;
  final String title;
  final bool isNewInstantMeeting;

  const PreJoinScreen({
    super.key,
    required this.meetingId,
    required this.groupId,
    required this.title,
    this.isNewInstantMeeting = false,
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

  // Name is autofilled from the profile; the field only unfolds if it's
  // missing or the user chooses to edit it, so a returning user isn't asked
  // to retype what we already know.
  bool _editingName = false;

  // Permission state, tracked per-device so we can offer a one-tap fix.
  bool _micDenied = false;
  bool _camDenied = false;
  bool _permissionDismissed = false;

  bool _devicesExpanded = false;
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  MediaDevice? _selectedAudioInput;
  MediaDevice? _selectedVideoInput;
  double _micGain = 1.0;
  bool _noiseSuppression = true;

  @override
  void initState() {
    super.initState();
    final profileName = ref.read(appUserProvider).name;
    final hasUsableName = profileName.isNotEmpty && profileName != 'Guest' && profileName != 'User';
    if (hasUsableName) {
      _nameController.text = profileName;
    } else {
      _editingName = true; // force the user to supply a name
    }
    _initLocalTracks();
  }

  Future<void> _initLocalTracks() async {
    if (!kIsWeb) {
      try {
        await [
          Permission.microphone,
          Permission.camera,
          Permission.bluetoothConnect,
        ].request();
      } catch (e) {
        debugPrint('Permission request failed: $e');
      }
    }

    // Attempt each capture device independently so one denial doesn't hide the
    // other, and we can tell the user exactly which permission to grant.
    try {
      _audioTrack = await LocalAudioTrack.create(
        AudioCaptureOptions(
          noiseSuppression: _noiseSuppression,
          echoCancellation: true,
          autoGainControl: true,
        ),
      );
      _micDenied = false;
    } catch (e) {
      _micDenied = true;
      debugPrint('Mic init failed: $e');
    }
    try {
      _videoTrack = await LocalVideoTrack.createCameraTrack();
      _camDenied = false;
    } catch (e) {
      _camDenied = true;
      debugPrint('Camera init failed: $e');
    }

    try {
      final devices = await Hardware.instance.enumerateDevices();
      _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
      if (_audioInputs.isNotEmpty) _selectedAudioInput = _audioInputs.first;
      if (_videoInputs.isNotEmpty) _selectedVideoInput = _videoInputs.first;
    } catch (e) {
      debugPrint('Device enumeration failed: $e');
    }

    if (mounted) setState(() {});
  }

  Future<void> _retryCamera() async {
    try {
      await _videoTrack?.dispose();
      _videoTrack = await LocalVideoTrack.createCameraTrack(
        _selectedVideoInput != null ? CameraCaptureOptions(deviceId: _selectedVideoInput!.deviceId) : const CameraCaptureOptions(),
      );
      _camDenied = false;
    } catch (e) {
      _camDenied = true;
      debugPrint('Camera retry failed: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _retryMic() async {
    try {
      await _audioTrack?.dispose();
      _audioTrack = await LocalAudioTrack.create(
        AudioCaptureOptions(
          deviceId: _selectedAudioInput?.deviceId,
          noiseSuppression: _noiseSuppression,
          echoCancellation: true,
          autoGainControl: true,
        ),
      );
      _micDenied = false;
    } catch (e) {
      _micDenied = true;
      debugPrint('Mic retry failed: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeVideoDevice(MediaDevice? device) async {
    if (device == null) return;
    setState(() => _selectedVideoInput = device);
    await _videoTrack?.dispose();
    _videoTrack = await LocalVideoTrack.createCameraTrack(
      CameraCaptureOptions(deviceId: device.deviceId),
    );
    if (mounted) setState(() {});
  }

  Future<void> _changeAudioDevice(MediaDevice? device) async {
    if (device == null) return;
    setState(() => _selectedAudioInput = device);
    await _audioTrack?.dispose();
    _audioTrack = await LocalAudioTrack.create(
      AudioCaptureOptions(
        deviceId: device.deviceId,
        noiseSuppression: _noiseSuppression,
        echoCancellation: true,
        autoGainControl: true,
      ),
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

  bool _isCreating = false;

  Future<void> _joinMeeting() async {
    if (widget.isNewInstantMeeting) {
      setState(() => _isCreating = true);
      final user = ref.read(appUserProvider);
      final now = DateTime.now();
      final meeting = Meeting(
        id: widget.meetingId,
        title: widget.title,
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        type: MeetingType.meet,
        participants: [user],
        isInstant: true,
      );
      try {
        await ref.read(firestoreRepositoryProvider).createMeeting(meeting).timeout(const Duration(seconds: 10));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create meeting: $e')));
          setState(() => _isCreating = false);
        }
        return;
      }
    }

    if (!mounted) return;

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

  bool get _canJoin => _nameController.text.trim().isNotEmpty;
  bool get _isTestMode => widget.meetingId == 'test-room' || widget.title.toLowerCase().contains('device test');

  @override
  Widget build(BuildContext context) {
    final showPermissionBanner = (_camDenied || _micDenied) && !_permissionDismissed;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.colors.textMain),
          onPressed: () => context.canPop() ? context.pop() : context.go('/upcoming'),
        ),
        title: Text(
          _isTestMode ? 'Test Devices' : 'Ready to join?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isTestMode ? 'Camera & Microphone Preview' : widget.title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: context.colors.textMain),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Preview — camera and mic controls.
                _buildPreview(context),
                const SizedBox(height: 12),

                // Sound Check bar — real-time mic level meter & speaker test button.
                _buildSoundCheckBar(context),
                const SizedBox(height: 16),

                if (showPermissionBanner) ...[
                  _buildPermissionBanner(context),
                  const SizedBox(height: 16),
                ],

                if (!_isTestMode) ...[
                  _buildNameSection(context),
                  const SizedBox(height: 16),
                  const RecordingConsentNotice(),
                  const SizedBox(height: 20),
                ],

                ElevatedButton(
                  onPressed: _isCreating
                      ? null
                      : (_isTestMode
                          ? () => Navigator.of(context).pop()
                          : (_canJoin ? _joinMeeting : null)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.colors.primary.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                  ),
                  child: _isCreating
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isTestMode ? 'Done Testing' : (_canJoin ? 'Join now' : 'Enter your name to join'),
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                ),
                const SizedBox(height: 12),

                // Device settings tucked away as secondary configuration.
                _buildDeviceSettings(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoTrack != null && !_isCameraMuted && !_camDenied)
              VideoTrackRenderer(_videoTrack!)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_camDenied ? Icons.videocam_off_rounded : Icons.videocam_off, size: 48, color: Colors.white54),
                    if (_camDenied) ...[
                      const SizedBox(height: 8),
                      const Text('Camera off', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ],
                ),
              ),

            // Compact mic/camera toggles overlaid on the preview.
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _previewToggle(
                    icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                    active: !_isMicMuted && !_micDenied,
                    onTap: _micDenied ? _retryMic : () => setState(() => _isMicMuted = !_isMicMuted),
                  ),
                  const SizedBox(width: 16),
                  _previewToggle(
                    icon: _isCameraMuted || _camDenied ? Icons.videocam_off : Icons.videocam,
                    active: !_isCameraMuted && !_camDenied,
                    onTap: _camDenied ? _retryCamera : () => setState(() => _isCameraMuted = !_isCameraMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewToggle({required IconData icon, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.9) : Colors.red,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: active ? Colors.black87 : Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final both = _camDenied && _micDenied;
    final message = both
        ? 'Convene can\'t see your camera or hear your mic.'
        : _micDenied
            ? 'Convene can\'t hear your microphone.'
            : 'Convene can\'t see your camera.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: context.colors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Check your browser\'s address-bar permission prompt, then retry.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_micDenied)
                _bannerAction(context, 'Allow microphone', _retryMic, primary: true),
              if (_camDenied)
                _bannerAction(context, 'Allow camera', _retryCamera, primary: true),
              _bannerAction(
                context,
                'Continue anyway',
                () => setState(() {
                  _permissionDismissed = true;
                  if (_camDenied) _isCameraMuted = true;
                  if (_micDenied) _isMicMuted = true;
                }),
                primary: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerAction(BuildContext context, String label, VoidCallback onTap, {required bool primary}) {
    return SizedBox(
      height: 36,
      child: primary
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
              ),
              child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textMuted,
                side: BorderSide(color: context.colors.border),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
              ),
              child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _buildNameSection(BuildContext context) {
    if (!_editingName && _canJoin) {
      // Returning user: show the autofilled name compactly with an Edit affordance.
      return GestureDetector(
        onTap: () => setState(() => _editingName = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.badge_outlined, size: 20, color: context.colors.textLight),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: context.colors.textMuted),
                    children: [
                      const TextSpan(text: 'Joining as '),
                      TextSpan(
                        text: _nameController.text.trim(),
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMain),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                'Edit',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.primary),
              ),
            ],
          ),
        ),
      );
    }

    return TextField(
      controller: _nameController,
      textCapitalization: TextCapitalization.words,
      autofocus: _editingName && !_canJoin,
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
    );
  }

  Widget _buildDeviceSettings(BuildContext context) {
    if (_audioInputs.isEmpty && _videoInputs.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        initiallyExpanded: _devicesExpanded,
        onExpansionChanged: (v) => setState(() => _devicesExpanded = v),
        leading: Icon(Icons.tune_rounded, size: 20, color: context.colors.textMuted),
        title: Text(
          'Device settings',
          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (_videoInputs.isNotEmpty)
            _deviceDropdown(context, Icons.videocam, _selectedVideoInput, _videoInputs, _changeVideoDevice, 'Camera'),
          if (_audioInputs.isNotEmpty) ...[
            _deviceDropdown(context, Icons.mic, _selectedAudioInput, _audioInputs, _changeAudioDevice, 'Microphone'),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.volume_up_rounded, size: 20, color: context.colors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Mic Input Volume',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textMain),
                          ),
                          Text(
                            '${(_micGain * 100).toInt()}%',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.primary),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          activeTrackColor: context.colors.primary,
                          inactiveTrackColor: context.colors.border,
                          thumbColor: context.colors.primary,
                        ),
                        child: Slider(
                          value: _micGain,
                          min: 0.0,
                          max: 2.0,
                          divisions: 20,
                          onChanged: (val) {
                            setState(() => _micGain = val);
                            if (kIsWeb) setMicGain(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _noiseSuppression,
              contentPadding: EdgeInsets.zero,
              activeTrackColor: context.colors.primary,
              title: Text(
                'Background Noise Suppression',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textMain),
              ),
              subtitle: Text(
                'Filters out fans, room noise & typing',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: context.colors.textMuted),
              ),
              secondary: Icon(Icons.cleaning_services_rounded, size: 20, color: context.colors.textMuted),
              onChanged: (val) async {
                setState(() => _noiseSuppression = val);
                await _retryMic();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceDropdown(
    BuildContext context,
    IconData icon,
    MediaDevice? selected,
    List<MediaDevice> devices,
    ValueChanged<MediaDevice?> onChanged,
    String fallbackLabel,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: context.colors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<MediaDevice>(
              isExpanded: true,
              value: selected,
              dropdownColor: context.colors.surface,
              style: TextStyle(color: context.colors.textMain),
              underline: const SizedBox(),
              items: devices.map((device) {
                return DropdownMenuItem(
                  value: device,
                  child: Text(
                    device.label.isNotEmpty ? device.label : '$fallbackLabel ${device.deviceId}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundCheckBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _SoundLevelMeter(
              audioTrack: _audioTrack,
              isMicMuted: _isMicMuted,
              isMicDenied: _micDenied,
            ),
          ),
          const SizedBox(width: 12),
          const _SpeakerTestButton(),
        ],
      ),
    );
  }
}

class _SoundLevelMeter extends StatefulWidget {
  final LocalAudioTrack? audioTrack;
  final bool isMicMuted;
  final bool isMicDenied;

  const _SoundLevelMeter({
    required this.audioTrack,
    required this.isMicMuted,
    required this.isMicDenied,
  });

  @override
  State<_SoundLevelMeter> createState() => _SoundLevelMeterState();
}

class _SoundLevelMeterState extends State<_SoundLevelMeter> {
  Timer? _levelTimer;
  double _level = 0.0;

  @override
  void initState() {
    super.initState();
    _updateMeterState();
  }

  @override
  void didUpdateWidget(covariant _SoundLevelMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMicMuted != widget.isMicMuted ||
        oldWidget.isMicDenied != widget.isMicDenied ||
        oldWidget.audioTrack != widget.audioTrack) {
      _updateMeterState();
    }
  }

  void _updateMeterState() {
    _levelTimer?.cancel();
    _levelTimer = null;

    if (widget.isMicMuted || widget.isMicDenied || widget.audioTrack == null) {
      if (kIsWeb) {
        stopMicLevelMeter();
      }
      if (_level != 0.0 && mounted) {
        setState(() => _level = 0.0);
      }
      return;
    }

    if (kIsWeb) {
      startMicLevelMeter();
    }

    // Measure real physical audio frequency levels from hardware
    _levelTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) return;
      if (widget.isMicMuted || widget.isMicDenied || widget.audioTrack == null) {
        _levelTimer?.cancel();
        _levelTimer = null;
        if (kIsWeb) {
          stopMicLevelMeter();
        }
        if (_level != 0.0) setState(() => _level = 0.0);
        return;
      }

      double sampledLevel = 0.0;
      if (kIsWeb) {
        sampledLevel = getRealMicLevel();
      }

      if ((_level - sampledLevel).abs() > 0.01) {
        setState(() => _level = sampledLevel);
      }
    });
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    if (kIsWeb) {
      stopMicLevelMeter();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMicDenied) {
      return Text(
        'Mic permission required',
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.error, fontWeight: FontWeight.w600),
      );
    }

    if (widget.isMicMuted) {
      return Row(
        children: [
          Icon(Icons.mic_off_rounded, size: 14, color: context.colors.textMuted),
          const SizedBox(width: 6),
          Text(
            'Microphone Muted',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: context.colors.textMuted, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(Icons.mic_rounded, size: 15, color: context.colors.primary),
        const SizedBox(width: 6),
        Text(
          'Mic:',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        const SizedBox(width: 8),
        Row(
          children: List.generate(7, (i) {
            final threshold = (i + 1) / 7.0;
            final isActive = _level >= threshold;
            Color barColor;
            if (i < 4) {
              barColor = const Color(0xFF10B981);
            } else if (i < 6) {
              barColor = Colors.amber;
            } else {
              barColor = Colors.redAccent;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: isActive ? barColor : barColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _level > 0.05 ? 'Testing' : 'Speak to test',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: _level > 0.05 ? context.colors.primary : context.colors.textLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeakerTestButton extends StatefulWidget {
  const _SpeakerTestButton();

  @override
  State<_SpeakerTestButton> createState() => _SpeakerTestButtonState();
}

class _SpeakerTestButtonState extends State<_SpeakerTestButton> {
  bool _isPlaying = false;

  Future<void> _playTestChime() async {
    setState(() => _isPlaying = true);
    if (kIsWeb) {
      playTestChime();
    } else {
      SystemSound.play(SystemSoundType.click);
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _isPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isPlaying ? null : _playTestChime,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: context.colors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
              size: 15,
              color: context.colors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              _isPlaying ? 'Playing Sound 🎵' : 'Test Speaker',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
