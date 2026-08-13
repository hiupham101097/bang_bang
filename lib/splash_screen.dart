import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'data/online_room_repository.dart';
import 'main.dart' show HomeScreen;
import 'ui/bang_ui.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.repository});
  final OnlineRoomRepository repository;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _assetsWarmed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
    GameAudio.instance.playSplashIntro();
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(bangRoute(HomeScreen(repository: widget.repository)));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsWarmed) return;
    _assetsWarmed = true;
    for (final asset in const [
      'assets/images/wild_west_town.png',
      'assets/images/room_table.png',
      'assets/images/effects/bang_sprite.png',
      'assets/images/effects/dodge_sprite.png',
    ]) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BangScenicBackground(
      overlay: .72,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (BangMotion.reduce(context)) return child!;
            final value = Curves.easeOutCubic.transform(_controller.value);
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: Transform.scale(scale: .94 + value * .06, child: child),
              ),
            );
          },
          child: Semantics(
            label: 'Bang Bang, hỗn chiến miền viễn Tây',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  child: Image.asset(
                    'assets/images/bang_bang_logo.png',
                    width: 480,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'HỖN CHIẾN MIỀN VIỄN TÂY',
                  style: TextStyle(
                    color: BangColors.paper,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const SizedBox(
                    width: 180,
                    height: 4,
                    child: LinearProgressIndicator(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
