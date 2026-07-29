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

  group('Private setup state', () {
    test('tracks role and character deck choices', () {
      const state = PrivateSetupState(
        phase: 'role_selection',
        playerId: 'p1',
        role: null,
        roleDeck: [
          SetupChoice(id: 'role_0', value: 'sheriff'),
          SetupChoice(id: 'role_1', value: '', pickedBy: 'p2'),
        ],
        characterDeck: [SetupChoice(id: 'character_0', value: 'black_jack')],
        characterOptions: [],
      );

      expect(state.phase, 'role_selection');
      expect(state.roleDeck, hasLength(2));
      expect(state.roleDeck.first.isPicked, isFalse);
      expect(state.roleDeck.last.isPicked, isTrue);
      expect(state.characterDeck.single.value, 'black_jack');
    });

    test('role setup exposes one face-down choice per player', () {
      for (final playerCount in [4, 5, 6, 7, 8]) {
        final choices = List<SetupChoice>.generate(
          playerCount,
          (index) => SetupChoice(id: 'role_$index', value: 'deputy'),
        );
        final state = PrivateSetupState(
          phase: 'role_selection',
          role: null,
          roleDeck: choices,
          characterOptions: const [],
        );

        expect(state.roleDeck, hasLength(playerCount));
      }
    });
  });
}
