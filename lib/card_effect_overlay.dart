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
