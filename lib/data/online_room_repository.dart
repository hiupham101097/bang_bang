import '../domain/online_models.dart';

/// Contract used by every online screen. The live implementation is backed by
/// Cloudflare Workers and Durable Objects; UI code never mutates match state.
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

/// Keeps the application usable before a Worker URL is configured, while
/// deliberately refusing to create a local or alternate online match.
class UnavailableOnlineRoomRepository implements OnlineRoomRepository {
  const UnavailableOnlineRoomRepository(this.message);
  final String message;

  Never _unavailable() => throw StateError(message);

  @override
  Future<PlayerProfile> ensureSignedIn() async => _unavailable();
  @override
  Stream<LobbyStats> watchStats() => Stream.value(const LobbyStats());
  @override
  Stream<List<OnlineRoom>> watchWaitingRooms({int limit = 20}) =>
      Stream.value(const []);
  @override
  Stream<OnlineRoom?> watchRoom(String roomId) => Stream.value(null);
  @override
  Stream<PrivateSetupState?> watchPrivateSetup(String roomId) =>
      Stream.value(null);
  @override
  Stream<List<String>> watchHand(String roomId) => Stream.value(const []);
  @override
  Stream<Map<String, dynamic>?> watchPendingAction(String roomId) =>
      Stream.value(null);
  @override
  Stream<List<Map<String, dynamic>>> watchPendingActions(String roomId) =>
      Stream.value(const []);
  @override
  Future<OnlineRoom> createRoom(RoomSettings settings) async => _unavailable();
  @override
  Future<OnlineRoom> joinRoom(String roomId) async => _unavailable();
  @override
  Future<OnlineRoom?> joinByCode(String code) async => _unavailable();
  @override
  Future<OnlineRoom?> quickJoin() async => _unavailable();
  @override
  Future<void> leaveRoom(String roomId) async => _unavailable();
  @override
  Future<void> setReady(String roomId, bool ready) async => _unavailable();
  @override
  Future<void> addBot(String roomId, String difficulty) async => _unavailable();
  @override
  Future<void> removeBot(String roomId, String botId) async => _unavailable();
  @override
  Future<void> startGame(String roomId) async => _unavailable();
  @override
  Future<void> chooseCharacter(
    String roomId,
    String characterId,
    String actionId,
  ) async => _unavailable();
  @override
  Future<Map<String, dynamic>> runGameAction(
    String name,
    Map<String, dynamic> payload,
  ) async => _unavailable();
}
