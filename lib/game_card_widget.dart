import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_engine.dart';

String getRankLabel(CardRank rank) => switch (rank) {
  CardRank.ace => 'A',
  CardRank.two => '2',
  CardRank.three => '3',
  CardRank.four => '4',
  CardRank.five => '5',
  CardRank.six => '6',
  CardRank.seven => '7',
  CardRank.eight => '8',
  CardRank.nine => '9',
  CardRank.ten => '10',
  CardRank.jack => 'J',
  CardRank.queen => 'Q',
  CardRank.king => 'K',
};

String getSuitSymbol(CardSuit suit) => switch (suit) {
  CardSuit.spade => '♠',
  CardSuit.club => '♣',
  CardSuit.diamond => '♦',
  CardSuit.heart => '♥',
};

Color getSuitColor(CardSuit suit) => switch (suit) {
  CardSuit.heart || CardSuit.diamond => const Color(0xffbd302d),
  CardSuit.spade || CardSuit.club => const Color(0xff24170f),
};

/// Existing artwork plus responsive, code-rendered rank and suit markers.
class GameCardWidget extends StatelessWidget {
  const GameCardWidget({
    required this.card,
    required this.width,
    this.height,
    this.isSelected = false,
    this.isEnabled = true,
    this.onTap,
    super.key,
  });

  final GameCard card;
  final double width;
  final double? height;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  static const _aspectRatio = 2.5 / 3.5;

  @override
  Widget build(BuildContext context) {
    final cardFace = height == null
        ? AspectRatio(
            aspectRatio: _aspectRatio,
            child: _CardFace(card: card, isSelected: isSelected),
          )
        : SizedBox(
            height: height,
            child: _CardFace(card: card, isSelected: isSelected),
          );

    return Semantics(
      button: onTap != null,
      enabled: isEnabled,
      label:
          '${card.name}: ${getRankLabel(card.rank)} ${getSuitSymbol(card.suit)}',
      child: SizedBox(
        width: width,
        child: Opacity(
          opacity: isEnabled ? 1 : .48,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? onTap : null,
              borderRadius: BorderRadius.circular(width * .08),
              child: cardFace,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.isSelected});

  final GameCard card;
  final bool isSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth = constraints.maxWidth;
      final cardHeight = constraints.maxHeight;
      final radius = cardWidth * .08;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.asset(card.imageAsset, fit: BoxFit.cover),
          ),
          Positioned(
            top: cardHeight * .045,
            left: cardWidth * .055,
            child: _CornerRankSuit(
              rank: card.rank,
              suit: card.suit,
              cardWidth: cardWidth,
            ),
          ),
          Positioned(
            bottom: cardHeight * .045,
            right: cardWidth * .055,
            child: Transform.rotate(
              angle: math.pi,
              child: _CornerRankSuit(
                rank: card.rank,
                suit: card.suit,
                cardWidth: cardWidth,
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xffffc451)
                      : Colors.transparent,
                  width: isSelected ? (cardWidth * .025).clamp(2, 4) : 0,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CornerRankSuit extends StatelessWidget {
  const _CornerRankSuit({
    required this.rank,
    required this.suit,
    required this.cardWidth,
  });

  final CardRank rank;
  final CardSuit suit;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final rankFontSize = (cardWidth * .13).clamp(12.0, 26.0);
    final suitFontSize = (cardWidth * .11).clamp(11.0, 24.0);
    final style = TextStyle(
      color: getSuitColor(suit),
      fontWeight: FontWeight.w900,
      height: .88,
      shadows: const [
        Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.white70),
      ],
    );

    return SizedBox(
      width: cardWidth * .18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              getRankLabel(rank),
              style: style.copyWith(fontSize: rankFontSize),
            ),
          ),
          Text(
            getSuitSymbol(suit),
            style: style.copyWith(fontSize: suitFontSize),
          ),
        ],
      ),
    );
  }
}

/// Debug gallery: all existing assets are used while the 52 standard
/// rank/suit combinations are displayed exactly once.
class CardPreviewScreen extends StatelessWidget {
  const CardPreviewScreen({super.key});

  static const _assets = [
    'appaloosa.png',
    'bang.png',
    'barrel.png',
    'beer.png',
    'cat_balou.png',
    'dilizenza.png',
    'duello.png',
    'dynamite.png',
    'gatling.png',
    'general_store.png',
    'gun_range_2.png',
    'gun_range_3.png',
    'gun_range_4.png',
    'gun_range_5.png',
    'indiani.png',
    'jail.png',
    'mustang.png',
    'ne.png',
    'panico.png',
    'saloon.png',
    'volcanic.png',
    'wells_fargo.png',
  ];

  static final _deck = [
    for (final suit in CardSuit.values)
      for (final rank in CardRank.values) (rank: rank, suit: suit),
  ];

  GameCard _previewCard(int index) {
    final marker = _deck[index % _deck.length];
    final asset = _assets[index % _assets.length];
    return GameCard(
      CardType.bang,
      id: 'preview_${asset.replaceAll('.png', '')}_${marker.rank.name}_${marker.suit.name}',
      rank: marker.rank,
      suit: marker.suit,
      imageAsset: 'assets/images/cards/$asset',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff17100b),
    appBar: AppBar(title: const Text('Kiểm tra toàn bộ thẻ bài')),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 6
            : constraints.maxWidth >= 700
            ? 4
            : 3;
        final cardWidth =
            ((constraints.maxWidth - 48 - (columns - 1) * 14) / columns).clamp(
              90.0,
              190.0,
            );
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: 14,
            childAspectRatio: .62,
          ),
          itemCount: _deck.length,
          itemBuilder: (context, index) => Center(
            child: GameCardWidget(card: _previewCard(index), width: cardWidth),
          ),
        );
      },
    ),
  );
}
