import 'package:flutter/material.dart';

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
    duration: const Duration(milliseconds: 620),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.translate(
      offset: Offset((_controller.value - .5) * 24, 0),
      child: Opacity(opacity: .6 + _controller.value * .4, child: child),
    ),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Image.asset(
        'assets/images/effects/dodge_sprite.png',
        fit: BoxFit.contain,
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
    duration: const Duration(milliseconds: 950),
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
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

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
        opacity: .55 + _controller.value * .45,
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
    duration: const Duration(milliseconds: 520),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.scale(
      scale: .9 + _controller.value * .16,
      child: Opacity(opacity: .65 + _controller.value * .35, child: child),
    ),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Image.asset(
        'assets/images/effects/area_attack_sprite.png',
        fit: BoxFit.contain,
      ),
    ),
  );
}

class _BangEffectOverlayState extends State<BangEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: 0.65 + _controller.value * 0.35,
      child: Transform.scale(
        scale: 0.82 + _controller.value * 0.22,
        child: child,
      ),
    ),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Image.asset(
        'assets/images/effects/bang_sprite.png',
        fit: BoxFit.contain,
      ),
    ),
  );
}
