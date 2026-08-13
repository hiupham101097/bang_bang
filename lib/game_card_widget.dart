import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_catalog.dart';
import 'game_engine.dart';
import 'ui/bang_ui.dart';

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
class GameCardWidget extends StatefulWidget {
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
  State<GameCardWidget> createState() => _GameCardWidgetState();
}

class _GameCardWidgetState extends State<GameCardWidget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cardFace = widget.height == null
        ? AspectRatio(
            aspectRatio: GameCardWidget._aspectRatio,
            child: _CardFace(card: widget.card, isSelected: widget.isSelected),
          )
        : SizedBox(
            height: widget.height,
            child: _CardFace(card: widget.card, isSelected: widget.isSelected),
          );

    return Semantics(
      button: widget.onTap != null,
      enabled: widget.isEnabled,
      label:
          '${widget.card.name}: ${getRankLabel(widget.card.rank)} ${getSuitSymbol(widget.card.suit)}',
      child: AnimatedScale(
        duration: BangMotion.resolve(context, BangMotion.instant),
        curve: BangMotion.curve,
        scale: _pressed && widget.isEnabled ? .96 : 1,
        child: Listener(
          onPointerDown: widget.isEnabled && widget.onTap != null
              ? (_) => setState(() => _pressed = true)
              : null,
          onPointerUp: widget.isEnabled && widget.onTap != null
              ? (_) => setState(() => _pressed = false)
              : null,
          onPointerCancel: widget.isEnabled && widget.onTap != null
              ? (_) => setState(() => _pressed = false)
              : null,
          child: SizedBox(
            width: widget.width,
            child: AnimatedOpacity(
              duration: BangMotion.resolve(context, BangMotion.fast),
              opacity: widget.isEnabled ? 1 : .48,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isEnabled ? widget.onTap : null,
                  borderRadius: BorderRadius.circular(widget.width * .08),
                  child: cardFace,
                ),
              ),
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
            child: RepaintBoundary(
              child: Image.asset(
                card.imageAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                cacheWidth: (cardWidth * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
            ),
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

/// Card collection shown from Home. It displays each card type once; rank and
/// suit remain code-rendered by [GameCardWidget], not baked into the assets.
class CardPreviewScreen extends StatelessWidget {
  const CardPreviewScreen({super.key});
  GameCard _previewCard(int index) {
    final info = cardCatalog[index];
    return GameCard(
      CardType.bang,
      id: 'catalog_${info.id}',
      rank: CardRank.values[index % CardRank.values.length],
      suit: CardSuit.values[index % CardSuit.values.length],
      imageAsset: info.imagePath!,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff17100b),
    appBar: AppBar(title: const Text('THẺ BÀI')),
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
          itemCount: cardCatalog.length,
          itemBuilder: (context, index) => Center(
            child: Semantics(
              button: true,
              label: 'Xem thông tin ${cardCatalog[index].name}',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _CardDetailScreen(
                      info: cardCatalog[index],
                      card: _previewCard(index),
                    ),
                  ),
                ),
                child: GameCardWidget(
                  card: _previewCard(index),
                  width: cardWidth,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _CardDetailScreen extends StatelessWidget {
  const _CardDetailScreen({required this.info, required this.card});

  final CardInfo info;
  final GameCard card;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff17100b),
    appBar: AppBar(title: Text(info.name)),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameCardWidget(card: card, width: 270),
                const SizedBox(height: 22),
                Text(
                  info.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffffc451),
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CHỨC NĂNG',
                    style: TextStyle(
                      color: Color(0xffffc451),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  info.description,
                  style: const TextStyle(fontSize: 16, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
