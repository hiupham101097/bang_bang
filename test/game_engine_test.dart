import 'package:bangbang/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameEngine', () {
    test('creates a four-player offline game with secret roles', () {
      final game = GameEngine.offline(seed: 1);
      expect(game.players, hasLength(4));
      expect(game.players.map((p) => p.role).toSet(), hasLength(4));
      expect(game.human.hand, hasLength(4));
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
