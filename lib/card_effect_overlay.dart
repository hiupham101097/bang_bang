import 'package:flutter/material.dart';

class _SpriteSheetFrame extends StatelessWidget {
  const _SpriteSheetFrame({
    required this.asset,
    required this.frame,
    required this.size,
  });

  final String asset;
  final int frame;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeFrame = frame.clamp(0, 3);
    final column = safeFrame % 2;
    final row = safeFrame ~/ 2;
    return ClipRect(
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.translate(
          offset: Offset(-column * size, -row * size),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size * 2,
            maxWidth: size * 2,
            minHeight: size * 2,
            maxHeight: size * 2,
            child: Image.asset(
              asset,
              width: size * 2,
              height: size * 2,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.low,
              cacheWidth: (size * 2 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
          ),
        ),
      ),
    );
  }
}

int _spriteFrame(AnimationController controller) =>
    (controller.value * 4).floor().clamp(0, 3);

/// Reusable, non-blocking visual effect for a resolved BANG action.
class BangEffectOverlay extends StatefulWidget {
  const BangEffectOverlay({super.key, this.size = 180});

  final double size;

  @override
  State<BangEffectOverlay> createState() => _BangEffectOverlayState();
}

class DodgeEffectOverlay extends StatefulWidget {
  const DodgeEffectOverlay({super.key, this.size = 150});

  final double size;

  @override
  State<DodgeEffectOverlay> createState() => _DodgeEffectOverlayState();
}

class _DodgeEffectOverlayState extends State<DodgeEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Opacity(
      opacity: _controller.value < .98 ? 1 : 0,
      child: Transform.translate(
        offset: Offset((_controller.value - .5) * 10, 0),
        child: _SpriteSheetFrame(
          asset: 'assets/images/effects/dodge_sprite.png',
          frame: _spriteFrame(_controller),
          size: widget.size,
        ),
      ),
    ),
  );
}

class AreaAttackEffectOverlay extends StatefulWidget {
  const AreaAttackEffectOverlay({super.key, this.size = 180});

  final double size;

  @override
  State<AreaAttackEffectOverlay> createState() =>
      _AreaAttackEffectOverlayState();
}

class DeathEffectOverlay extends StatefulWidget {
  const DeathEffectOverlay({super.key});

  @override
  State<DeathEffectOverlay> createState() => _DeathEffectOverlayState();
}

class _DeathEffectOverlayState extends State<DeathEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = _controller.value;
      return Opacity(
        opacity: (1 - progress).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.65 + progress * 1.4,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xaa8f1616),
              boxShadow: [BoxShadow(color: Color(0xffff3a2c), blurRadius: 12)],
            ),
            child: Center(
              child: Icon(Icons.close_rounded, color: Colors.white, size: 34),
            ),
          ),
        ),
      );
    },
  );
}

class HealEffectOverlay extends StatefulWidget {
  const HealEffectOverlay({super.key, this.size = 130});

  final double size;

  @override
  State<HealEffectOverlay> createState() => _HealEffectOverlayState();
}

class _HealEffectOverlayState extends State<HealEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Transform.scale(
      scale: .84 + _controller.value * .22,
      child: Opacity(
        opacity: _controller.value < .98 ? .55 + _controller.value * .45 : 0,
        child: Icon(
          Icons.favorite,
          color: const Color(0xff77e78b),
          size: widget.size,
          shadows: const [Shadow(color: Color(0xff1c7336), blurRadius: 16)],
        ),
      ),
    ),
  );
}

class _AreaAttackEffectOverlayState extends State<AreaAttackEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Opacity(
      opacity: _controller.value < .98 ? 1 : 0,
      child: Transform.scale(
        scale: .9 + _controller.value * .16,
        child: _SpriteSheetFrame(
          asset: 'assets/images/effects/area_attack_sprite.png',
          frame: _spriteFrame(_controller),
          size: widget.size,
        ),
      ),
    ),
  );
}

class _BangEffectOverlayState extends State<BangEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Opacity(
      opacity: _controller.value < .98 ? 0.72 + _controller.value * 0.28 : 0,
      child: Transform.scale(
        scale: 0.9 + _controller.value * 0.12,
        child: _SpriteSheetFrame(
          asset: 'assets/images/effects/bang_sprite.png',
          frame: _spriteFrame(_controller),
          size: widget.size,
        ),
      ),
    ),
  );
}
