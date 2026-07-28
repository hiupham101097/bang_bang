import 'package:flutter_test/flutter_test.dart';

import 'package:bangbang/domain/online_models.dart';

void main() {
  group('OnlineRoom game result', () {
    final settings = RoomSettings(
      roomName: 'Phòng test',
      maxPlayers: 4,
      isPublic: true,
      turnDurationSeconds: 45,
      voiceEnabled: false,
      chatEnabled: true,
      allowBots: true,
    );

    test('keeps the winner when room members update', () {
      final room = OnlineRoom(
        id: 'room_1',
        code: 'ABC123',
        settings: settings,
        hostUid: 'host',
        members: const [],
        status: RoomStatus.finished,
        phase: 'game_over',
        winner: 'Phe Cảnh sát',
      );

      expect(room.copyWith(members: const []).winner, 'Phe Cảnh sát');
    });
  });
}
