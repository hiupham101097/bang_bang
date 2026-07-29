enum RoomStatus { waiting, starting, playing, finished }

enum MemberType { human, bot }

class PlayerProfile {
  const PlayerProfile({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
}

class RoomChatMessage {
  const RoomChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? sentAt;
}

class RoomMember {
  const RoomMember({
    required this.id,
    required this.displayName,
    required this.seat,
    required this.type,
    this.isHost = false,
    this.isReady = false,
    this.isOnline = true,
    this.difficulty = 'normal',
    this.health = 0,
    this.maxHealth = 0,
    this.cardCount = 0,
    this.isAlive = true,
    this.characterId,
    this.revealedRole,
    this.equipment = const [],
    this.attackRange = 1,
  });

  final String id;
  final String displayName;
  final int seat;
  final MemberType type;
  final bool isHost;
  final bool isReady;
  final bool isOnline;
  final String difficulty;
  final int health;
  final int maxHealth;
  final int cardCount;
  final bool isAlive;
  final String? characterId;
  final String? revealedRole;
  final List<String> equipment;
  final int attackRange;

  bool get isBot => type == MemberType.bot;

  RoomMember copyWith({bool? isReady, bool? isOnline}) => RoomMember(
    id: id,
    displayName: displayName,
    seat: seat,
    type: type,
    isHost: isHost,
    isReady: isReady ?? this.isReady,
    isOnline: isOnline ?? this.isOnline,
    difficulty: difficulty,
    health: health,
    maxHealth: maxHealth,
    cardCount: cardCount,
    isAlive: isAlive,
    characterId: characterId,
    revealedRole: revealedRole,
    equipment: equipment,
    attackRange: attackRange,
  );
}

class RoomSettings {
  const RoomSettings({
    required this.roomName,
    this.maxPlayers = 8,
    this.isPublic = true,
    this.turnDurationSeconds = 45,
    this.voiceEnabled = true,
    this.chatEnabled = true,
    this.allowBots = true,
    this.initialBotCount = 0,
  });

  final String roomName;
  final int maxPlayers;
  final bool isPublic;
  final int turnDurationSeconds;
  final bool voiceEnabled;
  final bool chatEnabled;
  final bool allowBots;
  final int initialBotCount;
}

class OnlineRoom {
  const OnlineRoom({
    required this.id,
    required this.code,
    required this.settings,
    required this.hostUid,
    required this.members,
    this.status = RoomStatus.waiting,
    this.phase = 'lobby',
    this.sheriffPlayerId,
    this.winner,
    this.currentTurnPlayerId,
    this.turnDeadlineAt,
    this.turnNumber = 0,
    this.judgmentsResolvedForTurn = 0,
    this.hasDrawnThisTurn = false,
    this.cardsPlayedThisTurn = 0,
    this.bangUsedThisTurn = 0,
    this.publicLog = const [],
    this.discardTopCardId,
    this.dyingPlayerId,
  });

  final String id;
  final String code;
  final RoomSettings settings;
  final String hostUid;
  final List<RoomMember> members;
  final RoomStatus status;
  final String phase;
  final String? sheriffPlayerId;
  final String? winner;
  final String? currentTurnPlayerId;
  final DateTime? turnDeadlineAt;
  final int turnNumber;
  final int judgmentsResolvedForTurn;
  final bool hasDrawnThisTurn;
  final int cardsPlayedThisTurn;
  final int bangUsedThisTurn;
  final List<String> publicLog;
  final String? discardTopCardId;
  final String? dyingPlayerId;

  int get humanCount => members.where((member) => !member.isBot).length;
  int get botCount => members.where((member) => member.isBot).length;
  int get totalCount => members.length;
  bool get hasSeats => totalCount < settings.maxPlayers;
  bool get canBeListed =>
      status == RoomStatus.waiting && settings.isPublic && hasSeats;
  bool isHost(String uid) => uid == hostUid;
  RoomMember? memberFor(String uid) =>
      members.where((member) => member.id == uid).firstOrNull;

  bool canStart(String uid) =>
      isHost(uid) &&
      status == RoomStatus.waiting &&
      totalCount >= 4 &&
      humanCount >= 1 &&
      members
          .where((member) => !member.isBot)
          .every((member) => member.isReady && member.isOnline);

  OnlineRoom copyWith({
    List<RoomMember>? members,
    RoomStatus? status,
    String? phase,
    String? sheriffPlayerId,
    String? winner,
    String? currentTurnPlayerId,
    DateTime? turnDeadlineAt,
    int? turnNumber,
    int? judgmentsResolvedForTurn,
    bool? hasDrawnThisTurn,
    int? cardsPlayedThisTurn,
    int? bangUsedThisTurn,
    List<String>? publicLog,
    String? discardTopCardId,
    String? dyingPlayerId,
  }) => OnlineRoom(
    id: id,
    code: code,
    settings: settings,
    hostUid: hostUid,
    members: members ?? this.members,
    status: status ?? this.status,
    phase: phase ?? this.phase,
    sheriffPlayerId: sheriffPlayerId ?? this.sheriffPlayerId,
    winner: winner ?? this.winner,
    currentTurnPlayerId: currentTurnPlayerId ?? this.currentTurnPlayerId,
    turnDeadlineAt: turnDeadlineAt ?? this.turnDeadlineAt,
    turnNumber: turnNumber ?? this.turnNumber,
    judgmentsResolvedForTurn:
        judgmentsResolvedForTurn ?? this.judgmentsResolvedForTurn,
    hasDrawnThisTurn: hasDrawnThisTurn ?? this.hasDrawnThisTurn,
    cardsPlayedThisTurn: cardsPlayedThisTurn ?? this.cardsPlayedThisTurn,
    bangUsedThisTurn: bangUsedThisTurn ?? this.bangUsedThisTurn,
    publicLog: publicLog ?? this.publicLog,
    discardTopCardId: discardTopCardId ?? this.discardTopCardId,
    dyingPlayerId: dyingPlayerId ?? this.dyingPlayerId,
  );
}

class PrivateSetupState {
  const PrivateSetupState({
    required this.role,
    required this.characterOptions,
    this.selectedCharacterId,
    this.submitted = false,
  });
  final String? role;
  final List<String> characterOptions;
  final String? selectedCharacterId;
  final bool submitted;
}

class LobbyStats {
  const LobbyStats({
    this.onlineUsers = 0,
    this.waitingRooms = 0,
    this.playingRooms = 0,
  });

  final int onlineUsers;
  final int waitingRooms;
  final int playingRooms;
}
