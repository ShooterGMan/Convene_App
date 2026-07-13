import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

final audioRecorderServiceProvider = Provider<AudioRecorderService>((ref) {
  return AudioRecorderService();
});

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();

  Stream<double> get amplitudeStream => _amplitudeController.stream;
  
  Future<bool> get isRecording => _audioRecorder.isRecording();

  Future<void> startRecording(String meetingId) async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Audio recorder permission denied');
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/meeting_$meetingId.m4a';

    // Ensure previous recording is stopped
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    _amplitudeSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amplitude) {
      // amplitude.current is in dBFS (usually -160 to 0)
      // We map it to a rough 0.0 to 1.0 scale
      double normalized = (amplitude.current + 60) / 60;
      if (normalized < 0) normalized = 0.0;
      if (normalized > 1) normalized = 1.0;
      
      _amplitudeController.add(normalized);
    });
  }

  Future<String?> stopRecording() async {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    
    final path = await _audioRecorder.stop();
    return path;
  }

  void dispose() {
    _amplitudeSubscription?.cancel();
    _amplitudeController.close();
    _audioRecorder.dispose();
  }
}
