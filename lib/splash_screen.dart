import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'data/online_room_repository.dart';
import 'main.dart' show HomeScreen;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.repository});
  final OnlineRoomRepository repository;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

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
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => HomeScreen(repository: widget.repository),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    body: Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Opacity(
          opacity: Curves.easeOut.transform(_controller.value),
          child: Transform.scale(
            scale: .72 + (_controller.value * .28),
            child: child,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/bang_bang_logo.png', width: 520),
            const SizedBox(height: 12),
            const Text(
              'HỖN CHIẾN MIỀN VIỄN TÂY',
              style: TextStyle(
                color: Color(0xffffd272),
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 150,
              child: LinearProgressIndicator(color: Color(0xffffc451)),
            ),
          ],
        ),
      ),
    ),
  );
}
