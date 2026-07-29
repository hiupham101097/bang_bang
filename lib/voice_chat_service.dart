import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain/online_models.dart';

/// Voice and room chat are intentionally unavailable until their WebRTC
/// signaling protocol is implemented in the Cloudflare Worker.
class GameVoiceChat extends ChangeNotifier {
  GameVoiceChat._();

  static final GameVoiceChat instance = GameVoiceChat._();
  static const bool isAvailable = false;

  final _messagesChanged = StreamController<List<RoomChatMessage>>.broadcast();
  bool get isJoining => false;
  bool get isJoined => false;
  bool get isMuted => false;
  int get participantCount => 0;
  String? get roomId => null;
  List<RoomChatMessage> get messages => const [];
  Stream<List<RoomChatMessage>> get messageStream => _messagesChanged.stream;

  Future<void> join(String roomId) async =>
      throw StateError('Voice/chat đang chờ signaling Cloudflare.');

  Future<void> setMuted(bool muted) async {}

  Future<void> sendText(String text, {required String authorName}) async =>
      throw StateError(
        'Chat realtime chưa được kết nối với Cloudflare Worker.',
      );

  Future<void> leave() async {}
}
