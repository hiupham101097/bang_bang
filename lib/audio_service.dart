import 'package:flutter/services.dart';

class GameAudio {
  GameAudio._();
  static final instance = GameAudio._();
  static const _channel = MethodChannel('bangbang/audio');
  bool enabled = true;
  bool _playing = false;
  Future<void> startMusic() async {
    if (!enabled || _playing) return;
    await _channel.invokeMethod<void>('start');
    _playing = true;
  }

  Future<void> toggle() async {
    enabled = !enabled;
    if (enabled) {
      await startMusic();
    } else {
      await _channel.invokeMethod<void>('stop');
      _playing = false;
    }
  }
}
