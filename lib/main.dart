import 'package:bangbang/game_engine.dart';
import 'package:bangbang/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // The offline game works while Firebase is not configured for every platform.
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const BangBangApp());
}

class BangBangApp extends StatelessWidget {
  const BangBangApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    GameAudio.instance.startMusic();
  }

  void _dialog(String title, Widget content) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xfff4dfac),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xff4d2410),
        ),
      ),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ĐÓNG'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/wild_west_town.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: .45)),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: Color(0xffffc74f),
                    size: 52,
                  ),
                  const Text(
                    'BANG BANG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const Text(
                    'HỖN CHIẾN MIỀN VIỄN TÂY',
                    style: TextStyle(
                      color: Color(0xffffd272),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _menu(
                    'BẮT ĐẦU',
                    Icons.play_arrow_rounded,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GameTable()),
                    ),
                  ),
                  _menu(
                    'NHIỆM VỤ',
                    Icons.emoji_events_outlined,
                    () => _dialog(
                      'Nhiệm vụ hôm nay',
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('☐ Thắng một ván bất kỳ'),
                          SizedBox(height: 8),
                          Text('☐ Dùng BANG! 5 lần'),
                          SizedBox(height: 8),
                          Text('☐ Sống sót với 1 máu'),
                        ],
                      ),
                    ),
                  ),
                  _menu(
                    'HƯỚNG DẪN',
                    Icons.menu_book_outlined,
                    () => _dialog(
                      'Hướng dẫn nhanh',
                      const Text(
                        'Rút bài → chọn bài → chạm mục tiêu. BANG gây 1 sát thương; NÉ chặn BANG. Kính ngắm tăng tầm, Ngựa khiến đối thủ xa hơn. Cảnh trưởng và Vệ sĩ loại Kẻ cướp/Kẻ phản bội; Kẻ phản bội phải là người cuối cùng.',
                      ),
                    ),
                  ),
                  _menu('THOÁT', Icons.power_settings_new, SystemNavigator.pop),
                  const SizedBox(height: 10),
                  IconButton(
                    onPressed: () async {
                      await GameAudio.instance.toggle();
                      if (mounted) setState(() {});
                    },
                    icon: Icon(
                      GameAudio.instance.enabled
                          ? Icons.volume_up
                          : Icons.volume_off,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _menu(String text, IconData icon, VoidCallback action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SizedBox(
      width: 265,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: action,
        icon: Icon(icon),
        label: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xffe9ba57),
          foregroundColor: const Color(0xff43200d),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xffffe4a0), width: 2),
          ),
        ),
      ),
    ),
  );
}

class GameTable extends StatefulWidget {
  const GameTable({super.key});
  @override
  State<GameTable> createState() => _GameTableState();
}

class _GameTableState extends State<GameTable> {
  GameEngine game = GameEngine.offline();
  int selected = 0;
  bool sound = true, revealRoles = false;
  void _click({bool attack = false}) {
    if (sound)
      SystemSound.play(attack ? SystemSoundType.alert : SystemSoundType.click);
  }

  void _play(GamePlayer p) {
    if (game.human.hand.isEmpty) return;
    final card = game.human.hand[selected.clamp(0, game.human.hand.length - 1)];
    game.playHumanCard(selected, card.needsTarget ? p : null);
    selected = selected
        .clamp(0, game.human.hand.isEmpty ? 0 : game.human.hand.length - 1)
        .toInt();
    _click(attack: card.type == CardType.bang);
    setState(() {});
  }

  void _rules() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Luật BANG BANG'),
      content: const SingleChildScrollView(
        child: Text(
          'Vai trò bí mật: Cảnh trưởng và Vệ sĩ loại Kẻ cướp/Kẻ phản bội. Kẻ cướp loại Cảnh trưởng. Kẻ phản bội sống sót cuối cùng.\n\nMỗi lượt rút 2 lá, dùng bài rồi bỏ bớt để số bài không vượt máu. Nhấn lá BANG rồi chạm đối thủ trong tầm để tấn công. Bot tự NÉ nếu có lá NÉ.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ĐÃ HIỂU'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/wild_west_town.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (_, c) => Column(
              children: [
                _top(),
                Expanded(child: _field(c)),
                _hand(c),
              ],
            ),
          ),
        ),
        if (game.isOver) _victory(),
      ],
    ),
  );
  Widget _top() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 5, 12, 3),
    child: Row(
      children: [
        const Icon(Icons.local_fire_department, color: Color(0xffffc64b)),
        const SizedBox(width: 6),
        const Text(
          'BANG BANG',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        Text(
          'VÒNG ${game.round}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          onPressed: () => setState(() => revealRoles = !revealRoles),
          icon: const Icon(Icons.visibility),
          color: Colors.white,
        ),
        IconButton(
          onPressed: _rules,
          icon: const Icon(Icons.help_outline),
          color: Colors.white,
        ),
        IconButton(
          onPressed: () => setState(() => sound = !sound),
          icon: Icon(sound ? Icons.volume_up : Icons.volume_off),
          color: Colors.white,
        ),
      ],
    ),
  );
  Widget _field(BoxConstraints c) => Stack(
    children: [
      Positioned(top: 4, left: 12, child: _player(game.players[1])),
      Positioned(top: 4, right: 12, child: _player(game.players[2])),
      Positioned(
        top: c.maxHeight * .48,
        right: 12,
        child: _player(game.players[3]),
      ),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _event(),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _deck('BỘ BÀI', '🂠', game.deck.length),
                const SizedBox(width: 18),
                _deck('ĐÃ ĐÁNH', '🃏', game.discard.length),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _message(),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _event() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xff4e2813),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffffcb50)),
    ),
    child: Text(
      '⚡ ${game.eventLabel}',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
  );
  Widget _deck(String label, String icon, int count) => Column(
    children: [
      Container(
        width: 60,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xffebd094),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Text(icon, style: const TextStyle(fontSize: 34)),
      ),
      Text(
        '$label ($count)',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
  Widget _message() => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      game.log.isEmpty ? 'Chọn một lá bài rồi chọn mục tiêu.' : game.log,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white),
    ),
  );
  Widget _player(GamePlayer p) => GestureDetector(
    onTap: () => _play(p),
    child: Opacity(
      opacity: p.alive ? 1 : .42,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xff25130d).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: p.role == PlayerRole.sheriff
                ? const Color(0xffffcf5b)
                : Colors.white70,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_face(p), style: const TextStyle(fontSize: 27)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Row(children: [
              Image.asset('assets/images/health_bullet.png', width: 15, height: 15),
              Text(' ${p.health}/${p.maxHealth}  🂠 ${p.hand.length}  ↔ ${p.alive ? game.distance(game.human, p) : '-'}', style: const TextStyle(color: Color(0xffffd2cb), fontSize: 12)),
            ]),
            if (p.equipment.isNotEmpty)
              Text(
                p.equipment.map((e) => GameCard(e).name).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xffffd458), fontSize: 9),
              ),
            if (revealRoles || p.role == PlayerRole.sheriff)
              Text(
                _role(p.role),
                style: const TextStyle(color: Color(0xffffd458), fontSize: 10),
              ),
          ],
        ),
      ),
    ),
  );
  String _face(GamePlayer p) => switch (p.name) {
    'Lucky Joe' => '🤠',
    'Iron Rose' => '👩‍🦰',
    'Quick Jack' => '🧔',
    _ => '🧑‍⚕️',
  };
  String _role(PlayerRole r) => switch (r) {
    PlayerRole.sheriff => 'CẢNH TRƯỞNG',
    PlayerRole.guardian => 'VỆ SĨ',
    PlayerRole.raider => 'KẺ CƯỚP',
    PlayerRole.traitor => 'KẺ PHẢN BỘI',
  };
  Widget _hand(BoxConstraints c) => Container(
    color: const Color(0xff160b08).withValues(alpha: .94),
    padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
    child: Row(
      children: [
        _player(game.human),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 91,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: game.human.hand.length,
              separatorBuilder: (_, i) => const SizedBox(width: 7),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() {
                  selected = i;
                  _click();
                }),
                child: _card(game.human.hand[i], i == selected),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () {
            game.endHumanTurn();
            _click(attack: true);
            setState(() {});
          },
          icon: const Icon(Icons.skip_next),
          label: const Text('KẾT THÚC'),
        ),
      ],
    ),
  );
  Widget _card(GameCard c, bool active) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    width: 87,
    margin: EdgeInsets.only(top: active ? 0 : 10, bottom: active ? 8 : 0),
    decoration: BoxDecoration(
      color: c.type == CardType.bang
          ? const Color(0xffbd332c)
          : const Color(0xfff5dfaa),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: active ? const Color(0xffffd452) : Colors.white,
        width: active ? 3 : 1,
      ),
    ),
    alignment: Alignment.center,
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Text(
        c.name,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.type == CardType.bang
              ? Colors.white
              : const Color(0xff422212),
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    ),
  );
  Widget _victory() => Positioned.fill(
    child: ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xff4e2813),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xffffce57), width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🏆 VÁN ĐẤU KẾT THÚC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                game.winner ?? '',
                style: const TextStyle(color: Color(0xffffd75c), fontSize: 19),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() {
                  game = GameEngine.offline();
                  selected = 0;
                }),
                child: const Text('CHƠI VÁN MỚI'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
