import 'dart:async';

import 'package:bangbang/data/online_room_repository.dart';
import 'package:bangbang/domain/online_models.dart';
import 'package:bangbang/online_battle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('battle table fits eight players without vertical scrolling', (
    tester,
  ) async {
    final repository = _FakeBattleRepository();
    for (final size in const [Size(360, 640), Size(320, 568)]) {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineBattleScreen(repository: repository, room: _room()),
        ),
      );
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(GridView), findsNothing);
      final verticalLists = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((list) => list.scrollDirection == Axis.vertical);
      expect(verticalLists, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}

OnlineRoom _room() => OnlineRoom(
  id: 'room',
  code: 'ABC123',
  settings: const RoomSettings(roomName: 'Test', maxPlayers: 8),
  hostUid: 'p0',
  status: RoomStatus.playing,
  phase: 'turn_start',
  currentTurnPlayerId: 'p0',
  turnDeadlineAt: DateTime.now().add(const Duration(seconds: 60)),
  discardTopCardId: 'beer_2_heart',
  publicLog: const ['p0 drew cards'],
  members: List.generate(
    8,
    (index) => RoomMember(
      id: 'p$index',
      displayName: 'P$index',
      seat: index,
      type: index == 0 ? MemberType.human : MemberType.bot,
      health: 4,
      maxHealth: 4,
      cardCount: 7,
      characterId: index == 0 ? 'lucky_duke' : null,
      revealedRole: index == 0 ? 'sheriff' : null,
    ),
  ),
);

class _FakeBattleRepository implements OnlineRoomRepository {
  @override
  Future<PlayerProfile> ensureSignedIn() async =>
      const PlayerProfile(uid: 'p0', displayName: 'P0');

  @override
  Stream<List<String>> watchHand(String roomId) => Stream.value(const [
    'bang_ace_spade',
    'dodge_2_heart',
    'beer_3_diamond',
    'gatling_4_club',
    'panico_5_spade',
    'cat_balou_6_heart',
    'saloon_7_diamond',
  ]);

  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) =>
      Stream.value(const []);

  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) =>
      Stream.value(null);

  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) =>
      Stream.value(null);

  @override
  Stream<OnlineRoom?> watchRoom(String roomId) => Stream.value(_room());

  @override
  Stream<LobbyStats> watchStats() => Stream.value(const LobbyStats());

  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) =>
      Stream.value(const []);

  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) => _unused();
  @override
  Future<OnlineRoom> joinRoom(String roomId) => _unused();
  @override
  Future<OnlineRoom?> joinByCode(String code) => _unused();
  @override
  Future<OnlineRoom?> quickJoin() => _unused();
  @override
  Future<void> leaveRoom(String roomId) => _unused();
  @override
  Future<void> setReady(String roomId, bool ready) => _unused();
  @override
  Future<void> addBot(String roomId, String difficulty) => _unused();
  @override
  Future<void> removeBot(String roomId, String botId) => _unused();
  @override
  Future<void> startGame(String roomId) => _unused();
  @override
  Future<void> chooseRole(String roomId, String cardId) => _unused();
  @override
  Future<void> takeCharacterCard(String roomId, String cardId) => _unused();
  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) => _unused();
  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) => _unused();

  Never _unused() => throw UnimplementedError();
}
