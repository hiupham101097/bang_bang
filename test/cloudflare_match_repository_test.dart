import 'dart:convert';

import 'package:bangbang/data/cloudflare_match_repository.dart';
import 'package:bangbang/domain/online_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('private streams emit cached snapshot immediately', () async {
    SharedPreferences.setMockInitialValues({
      'bangbang_fallback_player_id': 'player_cache_test_12345',
    });
    final repository = CloudflareMatchRepository(
      'https://match.test',
      client: MockClient((request) async {
        if (request.url.path == '/v1/session') {
          return http.Response(jsonEncode({'token': 'test-token'}), 200);
        }
        if (request.url.path == '/v1/rooms') {
          return http.Response(
            jsonEncode({
              'room': _roomSnapshot(
                phase: 'role_selection',
                status: 'starting',
                hand: const ['bang_ace_spade', 'beer_2_heart'],
                pendingBang: const {
                  'id': 'pending_1',
                  'actionType': 'bang',
                  'actorId': 'p2',
                  'targetId': 'player_cache_test_12345',
                  'deadline': 123456,
                  'requiredDodges': 1,
                },
              ),
            }),
            201,
          );
        }
        return http.Response(jsonEncode({'error': 'unexpected'}), 404);
      }),
    );

    final room = await repository.createRoom(
      const RoomSettings(roomName: 'Test', maxPlayers: 8),
    );

    final setup = await repository.watchPrivateSetup(room.id).first;
    final hand = await repository.watchHand(room.id).first;
    final pending = await repository.watchPendingAction(room.id).first;
    final pendingList = await repository.watchPendingActions(room.id).first;

    expect(setup?.phase, 'role_selection');
    expect(setup?.roleDeck, hasLength(8));
    expect(hand, ['bang_ace_spade', 'beer_2_heart']);
    expect(pending?['id'], 'pending_1');
    expect(pending?['targetPlayerId'], 'player_cache_test_12345');
    expect(pendingList, hasLength(1));
  });

  test('waiting room summaries preserve starting status', () async {
    SharedPreferences.setMockInitialValues({
      'bangbang_fallback_player_id': 'player_cache_test_12345',
    });
    final repository = CloudflareMatchRepository(
      'https://match.test',
      client: MockClient((request) async {
        if (request.url.path == '/v1/session') {
          return http.Response(jsonEncode({'token': 'test-token'}), 200);
        }
        if (request.url.path == '/v1/rooms') {
          return http.Response(
            jsonEncode({
              'rooms': [
                {
                  'id': 'ROOM1',
                  'code': 'ROOM1',
                  'hostId': 'host',
                  'maxPlayers': 8,
                  'turnDurationSeconds': 60,
                  'status': 'starting',
                  'phase': 'role_selection',
                  'totalCount': 4,
                  'botCount': 0,
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'error': 'unexpected'}), 404);
      }),
    );

    final rooms = await repository.watchWaitingRooms().first;

    expect(rooms.single.status, RoomStatus.starting);
    expect(rooms.single.phase, 'role_selection');
  });

  test(
    'command snapshots update room watchers without waiting for WebSocket',
    () async {
      SharedPreferences.setMockInitialValues({
        'bangbang_fallback_player_id': 'player_cache_test_12345',
      });
      final repository = CloudflareMatchRepository(
        'https://match.test',
        client: MockClient((request) async {
          if (request.url.path == '/v1/session') {
            return http.Response(jsonEncode({'token': 'test-token'}), 200);
          }
          if (request.url.path == '/v1/rooms') {
            return http.Response(
              jsonEncode({
                'room': _roomSnapshot(
                  phase: 'lobby',
                  status: 'waiting',
                  hand: const [],
                ),
              }),
              201,
            );
          }
          if (request.url.path == '/v1/rooms/ROOM1') {
            return http.Response(
              jsonEncode({
                'room': _roomSnapshot(
                  phase: 'role_selection',
                  status: 'starting',
                  hand: const [],
                ),
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'error': 'unexpected'}), 404);
        }),
      );

      final room = await repository.createRoom(
        const RoomSettings(roomName: 'Test', maxPlayers: 4),
      );
      final updates = <OnlineRoom?>[];
      final subscription = repository.watchRoom(room.id).listen(updates.add);
      await Future<void>.delayed(Duration.zero);

      await repository.startGame(room.id);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(updates.first?.phase, 'lobby');
      expect(updates.last?.phase, 'role_selection');
      expect(updates.last?.status, RoomStatus.starting);
    },
  );
}

Map<String, Object?> _roomSnapshot({
  required String phase,
  required String status,
  required List<String> hand,
  Map<String, Object?>? pendingBang,
}) => {
  'id': 'ROOM1',
  'code': 'ROOM1',
  'hostId': 'player_cache_test_12345',
  'maxPlayers': 8,
  'turnDurationSeconds': 60,
  'status': status,
  'phase': phase,
  'turnNumber': 0,
  'bangUsedThisTurn': 0,
  'publicLog': const [],
  'pendingBang': ?pendingBang,
  'roleDeck': List.generate(
    8,
    (index) => {
      'id': 'role_$index',
      'value': index == 0 ? 'sheriff' : '',
      'pickedBy': index == 0 ? 'player_cache_test_12345' : null,
    },
  ),
  'characterDeck': const [],
  'players': [
    {
      'id': 'player_cache_test_12345',
      'name': 'Cache Tester',
      'seat': 0,
      'bot': false,
      'ready': false,
      'alive': true,
      'health': 0,
      'maxHealth': 0,
      'cardCount': hand.length,
      'hand': hand,
      'equipment': const [],
      'attackRange': 1,
      'role': 'sheriff',
      'characterOptions': const [],
      'characterChosen': false,
      'revealedRole': 'sheriff',
    },
  ],
};
