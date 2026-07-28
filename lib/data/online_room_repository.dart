import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/online_models.dart';

abstract class OnlineRoomRepository {
  Future<PlayerProfile> ensureSignedIn();
  Stream<LobbyStats> watchStats();
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20});
  Stream<OnlineRoom?> watchRoom(String roomId);
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId);
  Stream<List<String>> watchHand(String roomId);
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId);
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId);
  Future<OnlineRoom> createRoom(RoomSettings settings);
  Future<OnlineRoom> joinRoom(String roomId);
  Future<OnlineRoom?> joinByCode(String code);
  Future<OnlineRoom?> quickJoin();
  Future<void> leaveRoom(String roomId);
  Future<void> setReady(String roomId, bool ready);
  Future<void> addBot(String roomId, String difficulty);
  Future<void> removeBot(String roomId, String botId);
  Future<void> startGame(String roomId);
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  );
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  );
}

/// Firebase-first repository. Server-side Cloud Functions enforce all room
/// mutations; the local implementation is a development fallback until the
/// Functions are deployed.
class HybridOnlineRoomRepository implements OnlineRoomRepository {
  HybridOnlineRoomRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalOnlineRoomRepository? fallback,
  }) : _fallback = fallback ?? LocalOnlineRoomRepository() {
    _auth = auth;
    _firestore = firestore;
    _functions = functions;
  }

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseFunctions? _functions;
  final LocalOnlineRoomRepository _fallback;
  bool _useFallback = false;

  FirebaseAuth get firebaseAuth => _auth ??= FirebaseAuth.instance;
  FirebaseFirestore get firestore => _firestore ??= FirebaseFirestore.instance;
  FirebaseFunctions get functions => _functions ??= FirebaseFunctions.instance;

  @override
  Future<PlayerProfile> ensureSignedIn() async {
    try {
      final user =
          firebaseAuth.currentUser ??
          (await firebaseAuth.signInAnonymously()).user;
      if (user == null) throw StateError('Không thể đăng nhập ẩn danh.');
      return PlayerProfile(
        uid: user.uid,
        displayName: 'Cao bồi ${user.uid.substring(0, 5)}',
      );
    } catch (_) {
      _useFallback = true;
      return _fallback.ensureSignedIn();
    }
  }

  Future<T> _call<T>(
    String name,
    Map<String, dynamic> payload,
    Future<T> Function() local,
  ) async {
    if (_useFallback) return local();
    try {
      await functions.httpsCallable(name).call(payload);
      return local();
    } on FirebaseFunctionsException {
      _useFallback = true;
      return local();
    } on FirebaseException {
      _useFallback = true;
      return local();
    }
  }

  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) async {
    if (_useFallback) {
      throw StateError('Chế độ offline không hỗ trợ trận online.');
    }
    final result = await functions.httpsCallable(name).call(payload);
    return Map<String, dynamic>.from(result.data as Map? ?? const {});
  }

  @override
  Stream<LobbyStats> watchStats() {
    if (_useFallback) return _fallback.watchStats();
    return firestore
        .doc('systemStats/global')
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data() ?? const <String, dynamic>{};
          return LobbyStats(
            onlineUsers: (data['onlineUsers'] as num?)?.toInt() ?? 0,
            waitingRooms: (data['waitingRooms'] as num?)?.toInt() ?? 0,
            playingRooms: (data['playingRooms'] as num?)?.toInt() ?? 0,
          );
        })
        .handleError((_) => const LobbyStats());
  }

  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) {
    if (_useFallback) return _fallback.watchWaitingRooms(limit: limit);
    return firestore
        .collection('rooms')
        .where('status', isEqualTo: 'waiting')
        .where('isPublic', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(_roomFromDocument)
              .where((room) => room.hasSeats)
              .toList(),
        )
        .handleError((_) => <OnlineRoom>[]);
  }

  @override
  Stream<OnlineRoom?> watchRoom(String roomId) {
    if (_useFallback) return _fallback.watchRoom(roomId);
    return firestore
        .doc('rooms/$roomId')
        .snapshots()
        .asyncMap((snapshot) async {
          if (!snapshot.exists) return null;
          final room = _roomFromDocument(snapshot);
          final players = await firestore
              .collection('rooms/$roomId/players')
              .orderBy('seat')
              .get();
          return room.copyWith(
            members: players.docs.map(_memberFromDocument).toList(),
          );
        })
        .handleError((_) => null);
  }

  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) async* {
    final profile = await ensureSignedIn();
    if (_useFallback) {
      yield null;
      return;
    }
    yield* firestore
        .doc('rooms/$roomId/privateStates/${profile.uid}')
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) return null;
          return PrivateSetupState(
            role: data['role'] as String?,
            characterOptions: List<String>.from(
              data['characterOptions'] as List? ?? const [],
            ),
            selectedCharacterId: data['selectedCharacterId'] as String?,
            submitted: data['characterSelectionSubmitted'] as bool? ?? false,
          );
        });
  }

  @override
  Stream<List<String>> watchHand(String roomId) async* {
    final profile = await ensureSignedIn();
    if (_useFallback) {
      yield const [];
      return;
    }
    yield* firestore
        .doc('rooms/$roomId/privateStates/${profile.uid}')
        .snapshots()
        .map(
          (snapshot) => List<String>.from(
            snapshot.data()?['handCardIds'] as List? ?? const [],
          ),
        );
  }

  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) {
    if (_useFallback) return Stream.value(null);
    return firestore
        .collection('rooms/$roomId/pendingActions')
        .limit(1)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.isEmpty ? null : snapshot.docs.first.data(),
        );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) {
    if (_useFallback) return Stream.value(const []);
    return firestore
        .collection('rooms/$roomId/pendingActions')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => {'id': document.id, ...document.data()})
              .toList(),
        );
  }

  OnlineRoom _roomFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final humans = (data['humanPlayerCount'] as num?)?.toInt() ?? 0;
    final bots = (data['botPlayerCount'] as num?)?.toInt() ?? 0;
    return OnlineRoom(
      id: document.id,
      code: data['roomCode'] as String? ?? document.id,
      hostUid: data['hostUid'] as String? ?? '',
      status: _status(data['status'] as String?),
      phase: data['phase'] as String? ?? 'lobby',
      sheriffPlayerId: data['sheriffPlayerId'] as String?,
      winner: data['winner'] as String?,
      settings: RoomSettings(
        roomName: data['roomName'] as String? ?? 'Phòng chưa đặt tên',
        maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 8,
        isPublic: data['isPublic'] as bool? ?? true,
        turnDurationSeconds:
            (data['turnDurationSeconds'] as num?)?.toInt() ?? 45,
        voiceEnabled: data['voiceEnabled'] as bool? ?? true,
        chatEnabled: data['chatEnabled'] as bool? ?? true,
        allowBots: data['allowBots'] as bool? ?? true,
      ),
      members: [
        for (var i = 0; i < humans; i++)
          RoomMember(
            id: 'human_$i',
            displayName: 'Người chơi',
            seat: i,
            type: MemberType.human,
          ),
        for (var i = 0; i < bots; i++)
          RoomMember(
            id: 'bot_$i',
            displayName: 'Bot',
            seat: humans + i,
            type: MemberType.bot,
            isReady: true,
          ),
      ],
    );
  }

  RoomMember _memberFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return RoomMember(
      id: data['uid'] as String? ?? data['botId'] as String? ?? document.id,
      displayName: data['displayName'] as String? ?? 'Người chơi',
      seat: (data['seat'] as num?)?.toInt() ?? 0,
      type: data['playerType'] == 'bot' ? MemberType.bot : MemberType.human,
      isHost: data['isHost'] as bool? ?? false,
      isReady: data['isReady'] as bool? ?? false,
      isOnline: data['connectionState'] != 'offline',
      difficulty: data['difficulty'] as String? ?? 'normal',
    );
  }

  RoomStatus _status(String? value) => switch (value) {
    'starting' => RoomStatus.starting,
    'playing' => RoomStatus.playing,
    'finished' => RoomStatus.finished,
    _ => RoomStatus.waiting,
  };

  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) => _call('createRoom', {
    'roomName': settings.roomName,
    'maxPlayers': settings.maxPlayers,
    'isPublic': settings.isPublic,
    'turnDurationSeconds': settings.turnDurationSeconds,
    'voiceEnabled': settings.voiceEnabled,
    'chatEnabled': settings.chatEnabled,
    'allowBots': settings.allowBots,
  }, () => _fallback.createRoom(settings));

  @override
  Future<OnlineRoom> joinRoom(String roomId) =>
      _call('joinRoom', {'roomId': roomId}, () => _fallback.joinRoom(roomId));

  @override
  Future<OnlineRoom?> joinByCode(String code) =>
      _call('joinRoom', {'roomCode': code}, () => _fallback.joinByCode(code));

  @override
  Future<OnlineRoom?> quickJoin() =>
      _call('quickJoinRoom', const {}, _fallback.quickJoin);

  @override
  Future<void> leaveRoom(String roomId) =>
      _call('leaveRoom', {'roomId': roomId}, () => _fallback.leaveRoom(roomId));

  @override
  Future<void> setReady(String roomId, bool ready) => _call('setReady', {
    'roomId': roomId,
    'isReady': ready,
  }, () => _fallback.setReady(roomId, ready));

  @override
  Future<void> addBot(String roomId, String difficulty) => _call('addBot', {
    'roomId': roomId,
    'difficulty': difficulty,
  }, () => _fallback.addBot(roomId, difficulty));

  @override
  Future<void> removeBot(String roomId, String botId) => _call('removeBot', {
    'roomId': roomId,
    'botId': botId,
  }, () => _fallback.removeBot(roomId, botId));

  @override
  Future<void> startGame(String roomId) =>
      _call('startGame', {'roomId': roomId}, () => _fallback.startGame(roomId));

  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) => _call('chooseCharacter', {
    'roomId': roomId,
    'characterId': characterId,
    'actionId': actionId,
  }, () => _fallback.chooseCharacter(roomId, characterId, actionId));
}

/// In-memory implementation used only when Firebase is unavailable locally.
class LocalOnlineRoomRepository implements OnlineRoomRepository {
  LocalOnlineRoomRepository() {
    _rooms = [
      _sampleRoom('Cao bồi miền Tây', 'A7K9P2', 8, humans: 3, bots: 1),
      _sampleRoom('Miền Tây vui vẻ', 'R8D4Q1', 6, humans: 2),
    ];
  }

  late List<OnlineRoom> _rooms;
  final _changes = StreamController<void>.broadcast();
  final _random = Random();
  PlayerProfile? _profile;

  OnlineRoom _sampleRoom(
    String name,
    String code,
    int max, {
    required int humans,
    int bots = 0,
  }) {
    final members = <RoomMember>[
      for (var i = 0; i < humans; i++)
        RoomMember(
          id: 'sample_${code}_$i',
          displayName: i == 0 ? 'Lucky Joe' : 'Cao bồi ${i + 1}',
          seat: i,
          type: MemberType.human,
          isHost: i == 0,
          isReady: i > 0,
        ),
      for (var i = 0; i < bots; i++)
        RoomMember(
          id: 'bot_$code$i',
          displayName: 'Billy Bot',
          seat: humans + i,
          type: MemberType.bot,
          isReady: true,
        ),
    ];
    return OnlineRoom(
      id: 'room_$code',
      code: code,
      hostUid: members.first.id,
      settings: RoomSettings(roomName: name, maxPlayers: max),
      members: members,
    );
  }

  @override
  Future<PlayerProfile> ensureSignedIn() async => _profile ??=
      const PlayerProfile(uid: 'local_cowboy', displayName: 'Cao bồi ẩn danh');

  @override
  Stream<LobbyStats> watchStats() => _changes.stream
      .startWith(null)
      .map(
        (_) => LobbyStats(
          onlineUsers: 126,
          waitingRooms: _rooms.where((room) => room.canBeListed).length,
          playingRooms: _rooms
              .where((room) => room.status == RoomStatus.playing)
              .length,
        ),
      );

  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) => _changes
      .stream
      .startWith(null)
      .map(
        (_) => _rooms.where((room) => room.canBeListed).take(limit).toList(),
      );

  @override
  Stream<OnlineRoom?> watchRoom(String roomId) =>
      _changes.stream.startWith(null).map((_) => _find(roomId));

  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) =>
      Stream.value(null);

  OnlineRoom? _find(String id) {
    for (final room in _rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  void _save(OnlineRoom room) {
    _rooms = [
      for (final item in _rooms)
        if (item.id == room.id) room else item,
    ];
    _changes.add(null);
  }

  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) async {
    final profile = await ensureSignedIn();
    final id = 'room_${DateTime.now().microsecondsSinceEpoch}';
    final code = List.generate(
      6,
      (index) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_random.nextInt(32)],
    ).join();
    final room = OnlineRoom(
      id: id,
      code: code,
      hostUid: profile.uid,
      settings: settings,
      members: [
        RoomMember(
          id: profile.uid,
          displayName: profile.displayName,
          seat: 0,
          type: MemberType.human,
          isHost: true,
        ),
      ],
    );
    _rooms = [room, ..._rooms];
    _changes.add(null);
    return room;
  }

  @override
  Future<OnlineRoom> joinRoom(String roomId) async {
    final room = _find(roomId);
    final profile = await ensureSignedIn();
    if (room == null || !room.canBeListed) {
      throw StateError('Phòng không còn chỗ hoặc đã bắt đầu.');
    }
    if (room.memberFor(profile.uid) != null) return room;
    final seat = List.generate(
      room.settings.maxPlayers,
      (index) => index,
    ).firstWhere((seat) => !room.members.any((member) => member.seat == seat));
    final joined = room.copyWith(
      members: [
        ...room.members,
        RoomMember(
          id: profile.uid,
          displayName: profile.displayName,
          seat: seat,
          type: MemberType.human,
        ),
      ],
    );
    _save(joined);
    return joined;
  }

  @override
  Future<OnlineRoom?> joinByCode(String code) async {
    for (final room in _rooms) {
      if (room.code.toUpperCase() == code.trim().toUpperCase()) {
        return joinRoom(room.id);
      }
    }
    return null;
  }

  @override
  Future<OnlineRoom?> quickJoin() async {
    final candidates = _rooms.where((room) => room.canBeListed).toList()
      ..sort((a, b) => b.humanCount.compareTo(a.humanCount));
    return candidates.isEmpty ? null : joinRoom(candidates.first.id);
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    final profile = await ensureSignedIn();
    final room = _find(roomId);
    if (room == null) return;
    final members = room.members
        .where((member) => member.id != profile.uid)
        .toList();
    if (members.isEmpty) {
      _rooms.removeWhere((item) => item.id == roomId);
    } else {
      _save(room.copyWith(members: members));
    }
    _changes.add(null);
  }

  @override
  Future<void> setReady(String roomId, bool ready) async {
    final profile = await ensureSignedIn();
    final room = _find(roomId);
    if (room == null) return;
    _save(
      room.copyWith(
        members: [
          for (final member in room.members)
            if (member.id == profile.uid)
              member.copyWith(isReady: ready)
            else
              member,
        ],
      ),
    );
  }

  @override
  Future<void> addBot(String roomId, String difficulty) async {
    final room = _find(roomId);
    if (room == null || !room.settings.allowBots || !room.hasSeats) return;
    final seat = List.generate(
      room.settings.maxPlayers,
      (index) => index,
    ).firstWhere((seat) => !room.members.any((member) => member.seat == seat));
    _save(
      room.copyWith(
        members: [
          ...room.members,
          RoomMember(
            id: 'bot_${DateTime.now().millisecondsSinceEpoch}',
            displayName: 'Billy Bot',
            seat: seat,
            type: MemberType.bot,
            isReady: true,
            difficulty: difficulty,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> removeBot(String roomId, String botId) async {
    final room = _find(roomId);
    if (room != null) {
      _save(
        room.copyWith(
          members: room.members.where((member) => member.id != botId).toList(),
        ),
      );
    }
  }

  @override
  Future<void> startGame(String roomId) async {
    final profile = await ensureSignedIn();
    final room = _find(roomId);
    if (room == null || !room.canStart(profile.uid)) {
      throw StateError('Chưa đủ điều kiện bắt đầu.');
    }
    _save(room.copyWith(status: RoomStatus.starting));
  }

  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) async {}

  @override
  Stream<List<String>> watchHand(String roomId) => Stream.value(const []);

  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) =>
      Stream.value(null);

  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) =>
      Stream.value(const []);

  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) => Future<Map<String, dynamic>>.error(
    StateError('Chế độ offline không hỗ trợ trận online.'),
  );
}

extension _StreamStart<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
