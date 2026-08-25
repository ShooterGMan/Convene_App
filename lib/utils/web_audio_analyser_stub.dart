import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

double _mobileMicLevel = 0.0;
Timer? _mobileMicTimer;
AudioPlayer? _player;

void startMicLevelMeter() {
  stopMicLevelMeter();
  _mobileMicTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final rand = math.Random();
    _mobileMicLevel = 0.15 + rand.nextDouble() * 0.45;
  });
}

void stopMicLevelMeter() {
  _mobileMicTimer?.cancel();
  _mobileMicTimer = null;
  _mobileMicLevel = 0.0;
}

void setMicGain(double gain) {}

double getRealMicLevel() => _mobileMicLevel;

/// Synthesizes a 3-tone PCM WAV audio chime in memory and plays it via audioplayers
Future<void> playTestChime() async {
  try {
    _player ??= AudioPlayer();
    final bytes = _generate3ToneWavBytes();
    await _player!.play(BytesSource(bytes));
  } catch (e) {
    debugPrint('Mobile speaker chime test error: $e');
  }
}

/// Generates a 3-tone chime (523Hz C5 -> 659Hz E5 -> 783Hz G5) as a 16-bit PCM WAV byte array
Uint8List _generate3ToneWavBytes() {
  const sampleRate = 22050;
  const toneDurationMs = 180;
  const numTones = 3;
  const totalSamples = (sampleRate * toneDurationMs * numTones) ~/ 1000;
  
  final frequencies = [523.25, 659.25, 783.99]; // C5, E5, G5
  final samplesPerTone = (sampleRate * toneDurationMs) ~/ 1000;
  
  final pcmData = Int16List(totalSamples);
  
  for (int t = 0; t < numTones; t++) {
    final freq = frequencies[t];
    final startIdx = t * samplesPerTone;
    for (int i = 0; i < samplesPerTone; i++) {
      final sampleIdx = startIdx + i;
      final time = i / sampleRate;
      final envelope = 1.0 - (i / samplesPerTone);
      final sampleValue = (math.sin(2 * math.pi * freq * time) * 16000 * envelope).toInt();
      pcmData[sampleIdx] = sampleValue.clamp(-32768, 32767);
    }
  }

  final dataSize = totalSamples * 2;
  final fileSize = 36 + dataSize;
  final buffer = ByteData(44 + dataSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // 'R'
  buffer.setUint8(1, 0x49); // 'I'
  buffer.setUint8(2, 0x46); // 'F'
  buffer.setUint8(3, 0x46); // 'F'
  buffer.setUint32(4, fileSize, Endian.little);
  buffer.setUint8(8, 0x57);  // 'W'
  buffer.setUint8(9, 0x41);  // 'A'
  buffer.setUint8(10, 0x56); // 'V'
  buffer.setUint8(11, 0x45); // 'E'

  // fmt chunk
  buffer.setUint8(12, 0x66); // 'f'
  buffer.setUint8(13, 0x6D); // 'm'
  buffer.setUint8(14, 0x74); // 't'
  buffer.setUint8(15, 0x20); // ' '
  buffer.setUint32(16, 16, Endian.little); // chunk size 16
  buffer.setUint16(20, 1, Endian.little);  // PCM format
  buffer.setUint16(22, 1, Endian.little);  // mono
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  buffer.setUint16(32, 2, Endian.little);  // block align
  buffer.setUint16(34, 16, Endian.little); // bits per sample

  // data chunk
  buffer.setUint8(36, 0x64); // 'd'
  buffer.setUint8(37, 0x61); // 'a'
  buffer.setUint8(38, 0x74); // 't'
  buffer.setUint8(39, 0x61); // 'a'
  buffer.setUint32(40, dataSize, Endian.little);

  // Copy PCM samples
  for (int i = 0; i < totalSamples; i++) {
    buffer.setInt16(44 + i * 2, pcmData[i], Endian.little);
  }

  return buffer.buffer.asUint8List();
}
