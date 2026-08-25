import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundMeetingService {
  static const _channel = MethodChannel('com.convene.convene/screen_share');

  /// Starts the Android foreground service to keep audio/WebRTC room active in the
  /// background during multitasking.
  static Future<void> start({
    required String title,
    required String text,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('start', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      debugPrint('BackgroundMeetingService.start failed: $e');
    }
  }

  /// Stops the background meeting foreground service.
  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('BackgroundMeetingService.stop failed: $e');
    }
  }
}
