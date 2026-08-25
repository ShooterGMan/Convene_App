import 'dart:js_interop';

@JS('startMicLevelMeter')
external void startMicLevelMeter();

@JS('stopMicLevelMeter')
external void stopMicLevelMeter();

@JS('setMicGain')
external void setMicGain(double gain);

@JS('playTestChime')
external void playTestChime();

@JS('getRealMicLevel')
external double getRealMicLevel();
