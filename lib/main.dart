import 'dart:math' as math;

import 'package:bangbang/game_engine.dart';
import 'package:bangbang/audio_service.dart';
import 'package:bangbang/game_card_widget.dart';
import 'package:bangbang/data/cloudflare_match_repository.dart';
import 'package:bangbang/config/game_backend.dart';
import 'package:bangbang/data/online_room_repository.dart';
import 'package:bangbang/online_lobby.dart';
import 'package:bangbang/splash_screen.dart';
import 'package:bangbang/ui/bang_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const BangBangApp());
}

class BangBangApp extends StatelessWidget {
  const BangBangApp({super.key});
  static const _matchUrl = cloudflareMatchUrl;
  static final OnlineRoomRepository _rooms = _matchUrl.isNotEmpty
      ? CloudflareMatchRepository(_matchUrl)
      : const UnavailableOnlineRoomRepository(
          'Chưa cấu hình Cloudflare Worker. Chạy app với '
          '--dart-define=CLOUDFLARE_MATCH_URL=https://<worker>.workers.dev',
        );
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: bangTheme(),
    home: SplashScreen(repository: _rooms),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});
  final OnlineRoomRepository repository;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _openingLobby = false;

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

  Future<void> _openLobby() async {
    if (_openingLobby) return;
    setState(() => _openingLobby = true);
    try {
      await widget.repository.ensureSignedIn();
      if (!mounted) return;
      await Navigator.push(
        context,
        bangRoute(OnlineLobbyScreen(repository: widget.repository)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _openingLobby = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: BangScenicBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final portrait = constraints.maxHeight > constraints.maxWidth;
            final content = <Widget>[
              Flexible(
                flex: compact ? 4 : 5,
                child: RepaintBoundary(
                  child: Image.asset(
                    'assets/images/bang_bang_logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              SizedBox(width: compact ? 12 : 28, height: 12),
              Flexible(
                flex: 4,
                child: BangPanel(
                  padding: EdgeInsets.all(compact ? 14 : 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'HỖN CHIẾN MIỀN VIỄN TÂY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: BangColors.paper,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        BangButton(
                          label: 'CHƠI ONLINE',
                          icon: Icons.public_rounded,
                          loading: _openingLobby,
                          onPressed: _openLobby,
                          minWidth: double.infinity,
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Expanded(
                              child: BangButton(
                                label: 'NHIỆM VỤ',
                                icon: Icons.emoji_events_outlined,
                                secondary: true,
                                minWidth: 0,
                                onPressed: () => _dialog(
                                  'Nhiệm vụ hôm nay',
                                  const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: BangButton(
                                label: 'LUẬT CHƠI',
                                icon: Icons.menu_book_outlined,
                                secondary: true,
                                minWidth: 0,
                                onPressed: () => _dialog(
                                  'Hướng dẫn nhanh',
                                  const Text(
                                    'Rút bài → chọn bài → chạm mục tiêu. BANG gây 1 sát thương; NÉ chặn BANG. Trang bị giúp tăng tầm hoặc phòng thủ. Theo dõi khu giữa bàn để biết ai vừa đánh lá nào vào ai.',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ];
            return Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: portrait
                          ? Column(children: content)
                          : Row(children: content),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 10,
                  child: Row(
                    children: [
                      BangIconButton(
                        tooltip: 'Bộ sưu tập thẻ',
                        icon: Icons.style_outlined,
                        onPressed: () => Navigator.push(
                          context,
                          bangRoute(const CardPreviewScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BangIconButton(
                        tooltip: GameAudio.instance.enabled
                            ? 'Tắt âm thanh'
                            : 'Bật âm thanh',
                        icon: GameAudio.instance.enabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        onPressed: () async {
                          await GameAudio.instance.toggle();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class GameTable extends StatefulWidget {
  const GameTable({super.key, this.playerCount = 4})
    : assert(playerCount >= 4 && playerCount <= 8);

  final int playerCount;

  @override
  State<GameTable> createState() => _GameTableState();
}

class _GameTableState extends State<GameTable> {
  late GameEngine game;
  int selected = 0;
  bool choosingTarget = false;
  bool sound = true, revealRoles = false;

  @override
  void initState() {
    super.initState();
    game = GameEngine.offline(playerCount: widget.playerCount);
  }

  void _click({bool attack = false}) {
    if (sound) {
      SystemSound.play(attack ? SystemSoundType.alert : SystemSoundType.click);
    }
  }

  void _play(GamePlayer? target) {
    if (game.human.hand.isEmpty) return;
    final card = game.human.hand[selected.clamp(0, game.human.hand.length - 1)];
    if (card.needsTarget && target == null) {
      setState(() => choosingTarget = true);
      return;
    }
    game.playHumanCard(selected, card.needsTarget ? target : null);
    selected = selected
        .clamp(0, game.human.hand.isEmpty ? 0 : game.human.hand.length - 1)
        .toInt();
    choosingTarget = false;
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
  Widget _field(BoxConstraints c) {
    final opponents = game.players.where((player) => !player.isHuman).toList();
    return Stack(
      children: [
        for (var index = 0; index < opponents.length; index++)
          () {
            final angle =
                -math.pi / 2 + (2 * math.pi * index / opponents.length);
            final x =
                c.maxWidth / 2 + math.cos(angle) * (c.maxWidth * .36) - 75;
            final y =
                c.maxHeight / 2 + math.sin(angle) * (c.maxHeight * .33) - 32;
            return Positioned(
              left: x.clamp(4.0, c.maxWidth - 154),
              top: y.clamp(4.0, c.maxHeight - 72),
              child: _player(opponents[index]),
            );
          }(),
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
  }

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
    onTap: choosingTarget && p.alive && !p.isHuman ? () => _play(p) : null,
    child: AnimatedScale(
      duration: BangMotion.resolve(context, BangMotion.standard),
      curve: BangMotion.curve,
      scale: choosingTarget && !p.isHuman && p.alive ? 1.04 : 1,
      child: AnimatedOpacity(
        duration: BangMotion.resolve(context, BangMotion.fast),
        opacity: p.alive ? 1 : .42,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xff25130d).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: choosingTarget && !p.isHuman && p.alive
                  ? const Color(0xffff5c43)
                  : p.role == PlayerRole.sheriff
                  ? const Color(0xffffcf5b)
                  : Colors.white70,
              width: choosingTarget && !p.isHuman && p.alive ? 3 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      _face(p),
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      cacheWidth: 68,
                    ),
                  ),
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
              Row(
                children: [
                  Image.asset(
                    'assets/images/health_bullet.png',
                    width: 15,
                    height: 15,
                  ),
                  Expanded(
                    child: Text(
                      ' ${p.health}/${p.maxHealth}  🂠 ${p.hand.length}  ↔ ${p.alive ? game.distance(game.human, p) : '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffffd2cb),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (p.equipment.isNotEmpty)
                Text(
                  p.equipment.map((e) => GameCard(e).name).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xffffd458), fontSize: 9),
                ),
              if (revealRoles || !p.alive || p.role == PlayerRole.sheriff)
                Text(
                  _role(p.role),
                  style: const TextStyle(
                    color: Color(0xffffd458),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  String _face(GamePlayer p) => switch (p.name) {
    'Lucky Joe' => 'assets/images/characters/lucky_duke.png',
    'Iron Rose' => 'assets/images/characters/rose_oolan.png',
    'Quick Jack' => 'assets/images/characters/black_jack.png',
    'Doctor Lee' => 'assets/images/characters/sid_ketchum.png',
    _ => 'assets/images/role_deputy.png',
  };
  String _role(PlayerRole r) => switch (r) {
    PlayerRole.sheriff => 'CẢNH TRƯỞNG',
    PlayerRole.deputy => 'CẢNH SÁT PHÓ',
    PlayerRole.outlaw => 'KẺ CƯỚP',
    PlayerRole.renegade => 'KẺ PHẢN BỘI',
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
          onPressed: game.human.hand.isEmpty ? null : () => _play(null),
          icon: Icon(
            choosingTarget ? Icons.ads_click : Icons.play_arrow_rounded,
          ),
          label: Text(choosingTarget ? 'CHỌN MỤC TIÊU' : 'ĐÁNH / DÙNG'),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: choosingTarget
              ? () => setState(() => choosingTarget = false)
              : () {
                  game.endHumanTurn();
                  _click();
                  setState(() {});
                },
          icon: Icon(choosingTarget ? Icons.close : Icons.skip_next, size: 16),
          label: Text(choosingTarget ? 'HỦY' : 'KẾT THÚC'),
        ),
      ],
    ),
  );
  Widget _card(GameCard c, bool active) => AnimatedSlide(
    duration: BangMotion.resolve(context, BangMotion.fast),
    curve: BangMotion.curve,
    offset: active ? const Offset(0, -.08) : Offset.zero,
    child: AnimatedScale(
      duration: BangMotion.resolve(context, BangMotion.fast),
      curve: BangMotion.curve,
      scale: active ? 1.04 : 1,
      child: SizedBox(
        width: 87,
        child: GameCardWidget(card: c, width: 87, isSelected: active),
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
                  game = GameEngine.offline(playerCount: widget.playerCount);
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
