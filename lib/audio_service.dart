import 'package:flutter/services.dart';

class GameAudio {
  GameAudio._();
  static final instance = GameAudio._();
  static const _channel = MethodChannel('bangbang/audio');
  bool enabled = true;
  bool _playing = false;

  Future<void> playSplashIntro() async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod<void>('splash');
    } on MissingPluginException {
      // Desktop/web/test builds may not ship the native audio bridge.
    }
  }

  Future<void> playSfx(String name) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod<void>('sfx', {'name': name});
    } on MissingPluginException {
      // Keep gameplay responsive when audio is unavailable.
    }
  }

  Future<void> startMusic() async {
    if (!enabled || _playing) return;
    try {
      await _channel.invokeMethod<void>('start');
      _playing = true;
    } on MissingPluginException {
      // Optional audio must never block navigation or tests.
    }
  }

  Future<void> toggle() async {
    enabled = !enabled;
    if (enabled) {
      await startMusic();
    } else {
      try {
        await _channel.invokeMethod<void>('stop');
      } on MissingPluginException {
        // No native bridge on this platform.
      }
      _playing = false;
    }
  }
}
