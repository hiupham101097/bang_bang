import 'dart:async';

import 'package:bangbang/data/online_room_repository.dart';
import 'package:bangbang/domain/online_models.dart';
import 'package:bangbang/game_card_widget.dart';
import 'package:bangbang/game_engine.dart';
import 'package:bangbang/online_battle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('battle table fits eight players without vertical scrolling', (
    tester,
  ) async {
    final repository = _FakeBattleRepository();
    for (final size in const [Size(640, 360), Size(568, 320)]) {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: OnlineBattleScreen(repository: repository, room: _room()),
        ),
      );
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(GridView), findsNothing);
      expect(find.text('+ TRANG BI'), findsNWidgets(7));
      expect(find.byTooltip('VOLCANIC 10 SPADE'), findsOneWidget);
      final verticalLists = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((list) => list.scrollDirection == Axis.vertical);
      expect(verticalLists, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('bang selects valid targets directly on the table', (
    tester,
  ) async {
    final repository = _FakeBattleRepository();
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBattleScreen(
          repository: repository,
          room: _room(phase: 'play_phase'),
        ),
      ),
    );
    await tester.pump();

    final bang = tester.widget<GameCardWidget>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is GameCardWidget &&
                widget.card.type == CardType.bang &&
                widget.onTap != null,
          )
          .first,
    );
    bang.onTap!();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.gps_fixed), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.gps_fixed).first);
    await tester.pumpAndSettle();
    expect(repository.lastActionName, 'playCard');
    expect(repository.lastPayload?['targetPlayerId'], isNotNull);
  });

  testWidgets('bang target gets ten seconds and dodge controls', (
    tester,
  ) async {
    final repository = _FakeBattleRepository(
      pendingActions: [
        {
          'id': 'bang-1',
          'actionType': 'bang',
          'actorPlayerId': 'p1',
          'targetPlayerId': 'p0',
          'currentTargetId': 'p0',
          'responseDeadlineAt': DateTime.now()
              .add(const Duration(seconds: 10))
              .millisecondsSinceEpoch,
          'requiredDodges': 1,
        },
      ],
    );
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBattleScreen(
          repository: repository,
          room: _room(phase: 'waiting_response'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('NE'), findsOneWidget);
    expect(find.text('NHAN DAN'), findsOneWidget);
    expect(find.textContaining('Phản ứng: 10 giây'), findsOneWidget);
  });
}

OnlineRoom _room({String phase = 'turn_start'}) => OnlineRoom(
  id: 'room',
  code: 'ABC123',
  settings: const RoomSettings(roomName: 'Test', maxPlayers: 8),
  hostUid: 'p0',
  status: RoomStatus.playing,
  phase: phase,
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
      equipment: index == 0 ? const ['volcanic_10_spade'] : const [],
    ),
  ),
);

class _FakeBattleRepository implements OnlineRoomRepository {
  _FakeBattleRepository({this.pendingActions = const []});

  final List<Map<String, dynamic>> pendingActions;
  String? lastActionName;
  Map<String, dynamic>? lastPayload;

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
      Stream.value(pendingActions);

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
  ) async {
    lastActionName = name;
    lastPayload = payload;
    return const {};
  }

  Never _unused() => throw UnimplementedError();
}
