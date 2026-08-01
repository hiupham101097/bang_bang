import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/online_models.dart';
import 'firebase_player_profile_store.dart';
import 'online_room_repository.dart';

/// Authoritative match repository backed by Cloudflare Durable Objects.
/// Pass its HTTPS worker URL with --dart-define=CLOUDFLARE_MATCH_URL=... .
class CloudflareMatchRepository implements OnlineRoomRepository {
  CloudflareMatchRepository(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;
  PlayerProfile? _profile;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<PlayerProfile> ensureSignedIn() async {
    if (_profile != null) return _profile!;
    PlayerProfile profile;
    try {
      final account = await FirebasePlayerProfileStore.instance.ensureAccount();
      profile = PlayerProfile(
        uid: account.uid,
        displayName: account.displayName,
      );
    } catch (_) {
      // Firebase Auth can be enabled later without stopping local/online
      // matches today. The Worker receives a stable installation id instead.
      profile = await _localFallbackProfile();
    }
    final response = await _client.post(
      _uri('/v1/session'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceId': profile.uid,
        'displayName': profile.displayName,
      }),
    );
    final data = _decode(response);
    _token = data['token'] as String?;
    if (_token == null) throw StateError('Không thể tạo phiên máy chủ.');
    _profile = profile;
    return profile;
  }

  Future<PlayerProfile> _localFallbackProfile() async {
    final preferences = await SharedPreferences.getInstance();
    var uid = preferences.getString('bangbang_fallback_player_id');
    if (uid == null || uid.length < 8) {
      const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final random = Random.secure();
      uid = List.generate(
        24,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      await preferences.setString('bangbang_fallback_player_id', uid);
    }
    final resolvedUid = uid;
    return PlayerProfile(
      uid: resolvedUid,
      displayName: 'Cao bồi ${resolvedUid.substring(0, 5)}',
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    await ensureSignedIn();
    final response = await _client.post(
      _uri(path),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $_token',
      },
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    await ensureSignedIn();
    final response = await _client.get(
      _uri(path),
      headers: {'authorization': 'Bearer $_token'},
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = Map<String, dynamic>.from(decoded as Map);
    } on FormatException {
      throw StateError(
        'Máy chủ trận đấu lỗi HTTP ${response.statusCode}. '
        'Vui lòng thử lại sau.',
      );
    }
    if (response.statusCode >= 400) {
      throw StateError(data['error'] ?? 'Máy chủ trận đấu không phản hồi.');
    }
    return data;
  }

  Future<Map<String, dynamic>> _command(
    String roomId,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final data = await _post('/v1/rooms/$roomId', {
      'action': action,
      'payload': payload,
    });
    final rawRoom = data['room'];
    if (rawRoom is Map) {
      _publishRoom(_roomFromJson(Map<String, dynamic>.from(rawRoom)));
    }
    return data;
  }

  final Map<String, OnlineRoom?> _roomSnapshots = {};
  final Map<String, StreamController<OnlineRoom?>> _roomUpdates = {};
  final Map<String, StreamSubscription<OnlineRoom?>> _roomFeeds = {};

  @override
  Stream<OnlineRoom?> watchRoom(String roomId) async* {
    _startRoomFeed(roomId);
    if (_roomSnapshots.containsKey(roomId)) {
      yield _roomSnapshots[roomId];
    }
    yield* _roomUpdates[roomId]!.stream;
  }

  void _startRoomFeed(String roomId) {
    _roomUpdates.putIfAbsent(roomId, StreamController<OnlineRoom?>.broadcast);
    if (_roomFeeds.containsKey(roomId)) return;
    _roomFeeds[roomId] = _watchRoomSocket(roomId).listen((room) {
      if (room != null) {
        _publishRoom(room);
      }
    }, onError: _roomUpdates[roomId]!.addError);
  }

  void _publishRoom(OnlineRoom room) {
    _roomSnapshots[room.id] = room;
    _roomUpdates[room.id]?.add(room);
  }

  Stream<OnlineRoom?> _watchRoomSocket(String roomId) async* {
    await ensureSignedIn();
    final wsUrl = _uri('/v1/rooms/$roomId/ws').replace(
      scheme: baseUrl.startsWith('https') ? 'wss' : 'ws',
      queryParameters: {'token': _token},
    );
    try {
      final channel = WebSocketChannel.connect(wsUrl, protocols: const []);
      try {
        await for (final event in channel.stream) {
          final data = jsonDecode(event as String) as Map<String, dynamic>;
          if (data['type'] == 'state' && data['room'] is Map) {
            yield _roomFromJson(Map<String, dynamic>.from(data['room'] as Map));
          }
        }
      } finally {
        await channel.sink.close();
      }
    } catch (_) {
      // The table must remain usable on networks that block WebSockets.
    }
    while (true) {
      try {
        final data = await _get('/v1/rooms/$roomId');
        final rawRoom = data['room'];
        if (rawRoom is Map) {
          yield _roomFromJson(Map<String, dynamic>.from(rawRoom));
        }
      } catch (_) {
        yield null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  // The battle screen receives hand data through the same private WebSocket
  // snapshot. This small cache avoids exposing any other player's hand.
  final Map<String, List<String>> _hands = {};
  final Map<String, List<Map<String, dynamic>>> _pendingActions = {};
  final Map<String, PrivateSetupState?> _privateSetup = {};

  OnlineRoom _roomFromJson(Map<String, dynamic> data) {
    final profile = _profile;
    final rawPlayers = List<Map<String, dynamic>>.from(
      (data['players'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final mine = rawPlayers
        .where((item) => item['id'] == profile?.uid)
        .firstOrNull;
    if (mine?['hand'] is List) {
      _hands[data['id'] as String] = List<String>.from(mine!['hand'] as List);
    }
    _privateSetup[data['id'] as String] = mine == null
        ? null
        : PrivateSetupState(
            role: mine['role'] as String?,
            phase: data['phase'] as String? ?? 'lobby',
            playerId: profile?.uid,
            roleDeck: _setupChoices(data['roleDeck']),
            characterDeck: _setupChoices(data['characterDeck']),
            characterOptions: List<String>.from(
              mine['characterOptions'] as List? ?? const [],
            ),
            selectedCharacterId: mine['characterId'] as String?,
            selectionDeadlineAt: data['characterSelectionDeadline'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (data['characterSelectionDeadline'] as num).toInt(),
                  )
                : null,
            submitted: mine['characterChosen'] == true,
          );
    final pending = data['pendingBang'];
    if (pending is Map) {
      final item = Map<String, dynamic>.from(pending);
      _pendingActions[data['id'] as String] = [
        {
          'id': item['id'],
          'actionType': item['actionType'] ?? 'bang',
          'actorPlayerId': item['actorId'],
          'targetPlayerId': item['targetId'],
          'currentTargetId': item['targetId'],
          'responseDeadlineAt': item['deadline'],
          'requiredDodges': item['requiredDodges'],
          'openedCardIds': item['openedCardIds'],
          'currentPickerId': item['currentPickerId'],
        },
      ];
    } else {
      _pendingActions.remove(data['id'] as String);
    }
    final status = switch (data['status']) {
      'playing' => RoomStatus.playing,
      'finished' => RoomStatus.finished,
      'starting' => RoomStatus.starting,
      _ => RoomStatus.waiting,
    };
    final room = OnlineRoom(
      id: data['id'] as String,
      code: data['code'] as String,
      hostUid: data['hostId'] as String,
      settings: RoomSettings(
        roomName: 'Bàn ${data['code']}',
        maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 4,
        turnDurationSeconds:
            (data['turnDurationSeconds'] as num?)?.toInt() ?? 60,
      ),
      status: status,
      phase: data['phase'] as String? ?? 'lobby',
      sheriffPlayerId:
          data['sheriffPlayerId'] as String? ??
          rawPlayers
              .where((player) => player['revealedRole'] == 'sheriff')
              .map((player) => player['id'] as String)
              .firstOrNull,
      winner: data['winner'] as String?,
      currentTurnPlayerId: data['currentTurnPlayerId'] as String?,
      turnDeadlineAt: data['turnDeadline'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['turnDeadline'] as num).toInt(),
            )
          : null,
      turnNumber: (data['turnNumber'] as num?)?.toInt() ?? 0,
      bangUsedThisTurn: (data['bangUsedThisTurn'] as num?)?.toInt() ?? 0,
      publicLog: List<String>.from(data['publicLog'] as List? ?? const []),
      discardTopCardId: (data['discard'] as List?)?.lastOrNull as String?,
      members: rawPlayers.map(_memberFromJson).toList(),
    );
    return room;
  }

  RoomMember _memberFromJson(Map<String, dynamic> data) => RoomMember(
    id: data['id'] as String,
    displayName: data['name'] as String? ?? 'Cao bồi',
    seat: (data['seat'] as num?)?.toInt() ?? 0,
    type: data['bot'] == true ? MemberType.bot : MemberType.human,
    isHost: data['id'] == _profile?.uid,
    isReady: data['ready'] == true,
    health: (data['health'] as num?)?.toInt() ?? 0,
    maxHealth: (data['maxHealth'] as num?)?.toInt() ?? 0,
    cardCount: (data['cardCount'] as num?)?.toInt() ?? 0,
    isAlive: data['alive'] != false,
    characterId: data['characterId'] as String?,
    revealedRole: data['revealedRole'] as String? ?? data['role'] as String?,
    equipment: List<String>.from(data['equipment'] as List? ?? const []),
    attackRange: (data['attackRange'] as num?)?.toInt() ?? 1,
  );

  List<SetupChoice> _setupChoices(Object? raw) {
    if (raw is! List) return const <SetupChoice>[];
    return raw
        .whereType<Map>()
        .map((item) {
          final data = Map<String, dynamic>.from(item);
          return SetupChoice(
            id: data['id'] as String? ?? '',
            value: data['value'] as String? ?? '',
            pickedBy: data['pickedBy'] as String?,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  @override
  Stream<List<String>> watchHand(String roomId) async* {
    if (_hands.containsKey(roomId)) {
      yield _hands[roomId] ?? const <String>[];
    }
    await for (final room in watchRoom(roomId)) {
      yield _hands[room?.id] ?? const <String>[];
    }
  }

  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) async {
    final data = await _post('/v1/rooms', {
      'maxPlayers': settings.maxPlayers,
      'turnDurationSeconds': settings.turnDurationSeconds,
    });
    final room = _roomFromJson(Map<String, dynamic>.from(data['room'] as Map));
    _publishRoom(room);
    return room;
  }

  @override
  Future<OnlineRoom> joinRoom(String roomId) async => _roomFromJson(
    Map<String, dynamic>.from((await _command(roomId, 'join'))['room'] as Map),
  );

  @override
  Future<OnlineRoom?> joinByCode(String code) async {
    try {
      return await joinRoom(code.trim().toUpperCase());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setReady(String roomId, bool ready) async =>
      _command(roomId, 'ready', {'ready': ready});
  @override
  Future<void> addBot(String roomId, String difficulty) async =>
      _command(roomId, 'add_bot');
  @override
  Future<void> startGame(String roomId) async => _command(roomId, 'start');
  @override
  Future<void> chooseRole(String roomId, String cardId) async =>
      _command(roomId, 'choose_role', {'cardId': cardId});
  @override
  Future<void> takeCharacterCard(String roomId, String cardId) async =>
      _command(roomId, 'take_character_card', {'cardId': cardId});
  @override
  Future<void> leaveRoom(String roomId) async => _command(roomId, 'leave');
  @override
  Future<void> removeBot(String roomId, String botId) async =>
      _command(roomId, 'remove_bot', {'botId': botId});
  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) async => _command(roomId, 'choose_character', {'characterId': characterId});
  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) async* {
    if (_privateSetup.containsKey(roomId)) {
      yield _privateSetup[roomId];
    }
    await for (final _ in watchRoom(roomId)) {
      yield _privateSetup[roomId];
    }
  }

  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) async* {
    if (_pendingActions.containsKey(roomId)) {
      final actions = _pendingActions[roomId] ?? const <Map<String, dynamic>>[];
      yield actions.isEmpty ? null : actions.first;
    }
    await for (final _ in watchRoom(roomId)) {
      final actions = _pendingActions[roomId] ?? const <Map<String, dynamic>>[];
      yield actions.isEmpty ? null : actions.first;
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) async* {
    if (_pendingActions.containsKey(roomId)) {
      yield _pendingActions[roomId] ?? const <Map<String, dynamic>>[];
    }
    await for (final _ in watchRoom(roomId)) {
      yield _pendingActions[roomId] ?? const <Map<String, dynamic>>[];
    }
  }

  @override
  Stream<LobbyStats> watchStats() => Stream.value(const LobbyStats());
  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) async* {
    while (true) {
      try {
        final data = await _get('/v1/rooms');
        final rooms = List<Map<String, dynamic>>.from(
          (data['rooms'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        ).take(limit).map(_roomFromSummary).toList();
        yield rooms;
      } catch (_) {
        yield const <OnlineRoom>[];
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  OnlineRoom _roomFromSummary(Map<String, dynamic> data) => OnlineRoom(
    id: data['id'] as String,
    code: data['code'] as String,
    hostUid: data['hostId'] as String? ?? '',
    settings: RoomSettings(
      roomName: 'Bàn ${data['code']}',
      maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 4,
      turnDurationSeconds: (data['turnDurationSeconds'] as num?)?.toInt() ?? 45,
    ),
    status: switch (data['status']) {
      'playing' => RoomStatus.playing,
      'finished' => RoomStatus.finished,
      'starting' => RoomStatus.starting,
      _ => RoomStatus.waiting,
    },
    phase: data['phase'] as String? ?? 'lobby',
    members: List<RoomMember>.generate(
      (data['totalCount'] as num?)?.toInt() ?? 0,
      (index) => RoomMember(
        id: 'summary_$index',
        displayName: 'Người chơi',
        seat: index,
        type:
            index <
                ((data['totalCount'] as num?)?.toInt() ?? 0) -
                    ((data['botCount'] as num?)?.toInt() ?? 0)
            ? MemberType.human
            : MemberType.bot,
      ),
    ),
  );
  @override
  Future<OnlineRoom?> quickJoin() async {
    final data = await _get('/v1/rooms');
    final rooms = List<Map<String, dynamic>>.from(
      (data['rooms'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    if (rooms.isEmpty) return null;
    return joinRoom(rooms.first['id'] as String);
  }

  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) async {
    if (name == 'resolveTurnTimeout') return const <String, dynamic>{};
    final roomId = payload['roomId'] as String;
    final action = switch (name) {
      'drawTurnCards' => 'draw',
      'openKitCarlson' => 'draw',
      'drawCharacterTurnCards' => 'draw',
      'drawJesseJones' => 'draw',
      'playCard' => 'play',
      'playSpecialCard' => 'play',
      'resolveTargetCard' => 'play',
      'openGeneralStore' => 'play',
      'chooseGeneralStoreCard' => 'choose_general_store',
      'useSidKetchum' => 'sid_ketchum',
      'respondToAction' => 'respond_bang',
      'acceptBangDamage' => 'respond_bang',
      'resolveExpiredResponse' => 'respond_bang',
      'respondMultiAttack' => 'respond_bang',
      'respondDuel' => 'respond_bang',
      'resolveSlabDodge' => 'respond_bang',
      'useCalamityJanetDodge' => 'respond_bang',
      'resolveJourdonnais' => 'respond_bang',
      'startMultiAttack' => 'play',
      'startDuel' => 'play',
      'requestEndTurn' => 'end_turn',
      'discardCards' => 'discard',
      _ => throw StateError('Hành động $name chưa được Worker hỗ trợ.'),
    };
    final workerPayload = <String, dynamic>{...payload};
    if (name == 'respondToAction') {
      final response = payload['responseType'];
      workerPayload['response'] = response == 'missed' || response == 'dodge'
          ? 'dodge'
          : response ?? 'damage';
    } else if (name == 'respondMultiAttack' || name == 'respondDuel') {
      workerPayload['response'] = payload['cardId'] == null ? 'damage' : 'card';
    } else if (name == 'resolveSlabDodge') {
      workerPayload['response'] = 'dodge';
      final cards = List<String>.from(payload['cardIds'] as List? ?? const []);
      workerPayload['cardIds'] = cards;
    } else if (name == 'useCalamityJanetDodge') {
      workerPayload['response'] = 'dodge';
    } else if (name == 'resolveJourdonnais') {
      workerPayload['response'] = 'damage';
    } else if (name == 'acceptBangDamage' || name == 'resolveExpiredResponse') {
      workerPayload['response'] = 'damage';
    }
    return _command(roomId, action, workerPayload);
  }
}
