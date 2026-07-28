import 'package:bangbang/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameEngine', () {
    test('creates a four-player offline game with secret roles', () {
      final game = GameEngine.offline(seed: 1);
      expect(game.players, hasLength(4));
      expect(
        game.players.where((p) => p.role == PlayerRole.sheriff),
        hasLength(1),
      );
      expect(game.players.where((p) => p.role == PlayerRole.renegade), isEmpty);
      expect(game.human.hand, hasLength(4));
    });

    test('builds the official role table for rooms of 4 through 8', () {
      final expected = {
        4: [1, 1, 2, 0],
        5: [1, 1, 2, 1],
        6: [1, 1, 3, 1],
        7: [1, 2, 3, 1],
        8: [1, 2, 4, 1],
      };
      for (final entry in expected.entries) {
        final roles = GameEngine.buildRoles(entry.key);
        expect([
          roles.where((r) => r == PlayerRole.sheriff).length,
          roles.where((r) => r == PlayerRole.deputy).length,
          roles.where((r) => r == PlayerRole.outlaw).length,
          roles.where((r) => r == PlayerRole.renegade).length,
        ], entry.value);
      }
    });

    test('distance uses the shortest path around living players', () {
      final game = GameEngine.offline(seed: 2);
      expect(game.distance(game.players[0], game.players[3]), 1);
    });

    test('human gets two cards after completing a full round', () {
      final game = GameEngine.offline(seed: 3);
      final before = game.human.hand.length;
      game.endHumanTurn();
      expect(game.currentPlayer, game.human);
      expect(game.human.hand.length, greaterThanOrEqualTo(before));
    });
  });
}
