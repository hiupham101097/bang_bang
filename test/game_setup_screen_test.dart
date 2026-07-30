import 'dart:async';

import 'package:bangbang/data/online_room_repository.dart';
import 'package:bangbang/domain/online_models.dart';
import 'package:bangbang/game_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('setup screen fits eight-player role selection without scroll', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      PrivateSetupState(
        phase: 'role_selection',
        playerId: 'p0',
        role: null,
        characterOptions: const [],
        roleDeck: List.generate(
          8,
          (index) => SetupChoice(id: 'r$index', value: ''),
        ),
      ),
    );
    await _pumpSetupAtSizes(tester, repository);
  });

  testWidgets('role selection starts with only one face-down card per player', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      PrivateSetupState(
        phase: 'role_selection',
        playerId: 'p0',
        role: null,
        characterOptions: const [],
        roleDeck: List.generate(
          8,
          (index) => SetupChoice(id: 'r$index', value: ''),
        ),
      ),
    );

    await _pumpSetup(tester, repository, const Size(640, 360));

    expect(find.byKey(const ValueKey('role_card_r0')), findsOneWidget);
    expect(find.text('CHON 1 LA'), findsNothing);
    expect(find.text('CHON'), findsNothing);
    _expectNoScrollOrOverflow(tester);
  });

  testWidgets('setup screen fits eight-player character deck without scroll', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      PrivateSetupState(
        phase: 'character_selection',
        playerId: 'p0',
        role: 'sheriff',
        characterOptions: const [],
        characterDeck: List.generate(
          16,
          (index) => SetupChoice(id: 'c$index', value: ''),
        ),
      ),
    );
    await _pumpSetupAtSizes(tester, repository);
  });

  testWidgets('setup screen fits final two-card choice without scroll', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      const PrivateSetupState(
        phase: 'choosing_character',
        playerId: 'p0',
        role: 'sheriff',
        characterOptions: ['black_jack', 'lucky_duke'],
      ),
    );
    await _pumpSetupAtSizes(tester, repository);
  });

  testWidgets('submitted character stays visible while waiting', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      const PrivateSetupState(
        phase: 'choosing_character',
        playerId: 'p0',
        role: 'sheriff',
        characterOptions: ['black_jack', 'lucky_duke'],
        selectedCharacterId: 'lucky_duke',
        submitted: true,
      ),
    );

    await _pumpSetup(tester, repository, const Size(360, 640));

    expect(find.text('Lucky Duke'), findsWidgets);
    expect(find.text('CHON'), findsNothing);
    _expectNoScrollOrOverflow(tester);
  });

  testWidgets('role card requires confirm before choosing', (tester) async {
    final repository = _FakeSetupRepository(
      PrivateSetupState(
        phase: 'role_selection',
        playerId: 'p0',
        role: null,
        characterOptions: const [],
        roleDeck: List.generate(
          8,
          (index) => SetupChoice(id: 'r$index', value: ''),
        ),
      ),
    );

    await _pumpSetup(tester, repository, const Size(360, 640));
    await tester.tap(find.byKey(const ValueKey('role_card_r0')));
    await tester.pump();

    expect(repository.chosenRoleCardId, isNull);
    expect(find.text('CHON'), findsOneWidget);

    await tester.tap(find.text('CHON'));
    await tester.pump();

    expect(repository.chosenRoleCardId, 'r0');
    _expectNoScrollOrOverflow(tester);
  });

  testWidgets('character card requires confirm before taking', (tester) async {
    final repository = _FakeSetupRepository(
      PrivateSetupState(
        phase: 'character_selection',
        playerId: 'p0',
        role: 'sheriff',
        characterOptions: const [],
        characterDeck: List.generate(
          16,
          (index) => SetupChoice(id: 'c$index', value: ''),
        ),
      ),
    );

    await _pumpSetup(tester, repository, const Size(360, 640));
    await tester.tap(find.byKey(const ValueKey('character_card_c0')));
    await tester.pump();

    expect(repository.takenCharacterCardId, isNull);
    expect(find.text('CHON'), findsOneWidget);

    await tester.tap(find.text('CHON'));
    await tester.pump();

    expect(repository.takenCharacterCardId, 'c0');
    _expectNoScrollOrOverflow(tester);
  });

  testWidgets('final character choice can be confirmed after inspecting', (
    tester,
  ) async {
    final repository = _FakeSetupRepository(
      const PrivateSetupState(
        phase: 'choosing_character',
        playerId: 'p0',
        role: 'sheriff',
        characterOptions: ['black_jack', 'lucky_duke'],
      ),
    );

    await _pumpSetup(tester, repository, const Size(360, 640));

    expect(find.text('CHON'), findsNothing);
    await tester.tap(find.text('Lucky Duke'));
    await tester.pump();
    expect(repository.chosenCharacterId, isNull);
    expect(find.text('CHON'), findsOneWidget);

    await tester.tap(find.text('CHON'));
    await tester.pump();

    expect(repository.chosenCharacterId, 'lucky_duke');
    _expectNoScrollOrOverflow(tester);
  });
}

Future<void> _pumpSetupAtSizes(
  WidgetTester tester,
  OnlineRoomRepository repository,
) async {
  for (final size in const [Size(640, 360), Size(568, 320)]) {
    await _pumpSetup(tester, repository, size);
    _expectNoScrollOrOverflow(tester);
  }
}

Future<void> _pumpSetup(
  WidgetTester tester,
  OnlineRoomRepository repository,
  Size size,
) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      home: GameSetupScreen(repository: repository, room: _room(8)),
    ),
  );
  await tester.pump();
}

void _expectNoScrollOrOverflow(WidgetTester tester) {
  expect(find.byType(SingleChildScrollView), findsNothing);
  expect(find.byType(ListView), findsNothing);
  expect(find.byType(GridView), findsNothing);
  expect(tester.takeException(), isNull);
}

OnlineRoom _room(int players) => OnlineRoom(
  id: 'room',
  code: 'ABC123',
  settings: const RoomSettings(roomName: 'Test', maxPlayers: 8),
  hostUid: 'p0',
  status: RoomStatus.starting,
  phase: 'character_selection',
  members: List.generate(
    players,
    (index) => RoomMember(
      id: 'p$index',
      displayName: 'P$index',
      seat: index,
      type: index == 0 ? MemberType.human : MemberType.bot,
    ),
  ),
);

class _FakeSetupRepository implements OnlineRoomRepository {
  _FakeSetupRepository(this.state);

  final PrivateSetupState state;
  String? chosenRoleCardId;
  String? takenCharacterCardId;
  String? chosenCharacterId;

  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) =>
      Stream.value(state);

  @override
  Future<PlayerProfile> ensureSignedIn() async =>
      const PlayerProfile(uid: 'p0', displayName: 'P0');

  @override
  Future<void> chooseRole(String roomId, String cardId) async {
    chosenRoleCardId = cardId;
  }

  @override
  Future<void> takeCharacterCard(String roomId, String cardId) async {
    takenCharacterCardId = cardId;
  }

  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) async {
    chosenCharacterId = characterId;
  }

  @override
  Future<void> addBot(String roomId, String difficulty) => _unused();

  @override
  Future<void> removeBot(String roomId, String botId) => _unused();

  @override
  Future<void> setReady(String roomId, bool ready) => _unused();

  @override
  Future<void> startGame(String roomId) => _unused();

  @override
  Future<void> leaveRoom(String roomId) => _unused();

  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) => _unused();

  @override
  Future<OnlineRoom> joinRoom(String roomId) => _unused();

  @override
  Future<OnlineRoom?> joinByCode(String code) => _unused();

  @override
  Future<OnlineRoom?> quickJoin() => _unused();

  @override
  Stream<List<String>> watchHand(String roomId) => const Stream.empty();

  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) =>
      const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) =>
      const Stream.empty();

  @override
  Stream<OnlineRoom?> watchRoom(String roomId) => const Stream.empty();

  @override
  Stream<LobbyStats> watchStats() => const Stream.empty();

  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) =>
      const Stream.empty();

  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) => _unused();

  Never _unused() => throw UnimplementedError();
}
