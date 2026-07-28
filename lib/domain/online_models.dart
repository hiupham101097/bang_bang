enum RoomStatus { waiting, starting, playing, finished }

enum MemberType { human, bot }

class PlayerProfile {
  const PlayerProfile({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
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
  });

  final String id;
  final String displayName;
  final int seat;
  final MemberType type;
  final bool isHost;
  final bool isReady;
  final bool isOnline;
  final String difficulty;

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
  });

  final String roomName;
  final int maxPlayers;
  final bool isPublic;
  final int turnDurationSeconds;
  final bool voiceEnabled;
  final bool chatEnabled;
  final bool allowBots;
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
      humanCount >= 2 &&
      members
          .where((member) => !member.isBot)
          .every((member) => member.isReady && member.isOnline);

  OnlineRoom copyWith({
    List<RoomMember>? members,
    RoomStatus? status,
    String? phase,
    String? sheriffPlayerId,
    String? winner,
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
