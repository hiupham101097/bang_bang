import 'package:bangbang/game_card_widget.dart';
import 'package:bangbang/game_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rank and suit helpers return standard deck labels', () {
    expect(getRankLabel(CardRank.ace), 'A');
    expect(getRankLabel(CardRank.ten), '10');
    expect(getRankLabel(CardRank.jack), 'J');
    expect(getRankLabel(CardRank.queen), 'Q');
    expect(getRankLabel(CardRank.king), 'K');
    expect(getSuitSymbol(CardSuit.spade), '♠');
    expect(getSuitSymbol(CardSuit.club), '♣');
    expect(getSuitSymbol(CardSuit.diamond), '♦');
    expect(getSuitSymbol(CardSuit.heart), '♥');
    expect(getSuitColor(CardSuit.heart), const Color(0xffbd302d));
    expect(getSuitColor(CardSuit.club), const Color(0xff24170f));
  });

  testWidgets('renders two corner markers and rotates the lower marker', (
    tester,
  ) async {
    final card = GameCard(
      CardType.bang,
      id: 'bang_ten_heart',
      rank: CardRank.ten,
      suit: CardSuit.heart,
      imageAsset: 'assets/images/cards/bang.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: GameCardWidget(card: card, width: 160)),
        ),
      ),
    );

    expect(find.text('10'), findsNWidgets(2));
    expect(find.text('♥'), findsNWidgets(2));
    expect(find.byType(Transform), findsAtLeastNWidgets(1));
  });
}
