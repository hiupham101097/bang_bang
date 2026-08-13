import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'data/online_room_repository.dart';
import 'domain/online_models.dart';
import 'game_setup_screen.dart';
import 'online_battle_screen.dart';
import 'ui/bang_ui.dart';

const ButtonStyle _lobbyButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(44, 40)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  visualDensity: VisualDensity.compact,
  textStyle: WidgetStatePropertyAll(
    TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .4),
  ),
);

class LobbyViewModel extends ChangeNotifier {
  LobbyViewModel(this.repository);
  final OnlineRoomRepository repository;
  StreamSubscription<List<OnlineRoom>>? _roomsSubscription;
  StreamSubscription<LobbyStats>? _statsSubscription;
  List<OnlineRoom> rooms = const [];
  LobbyStats stats = const LobbyStats();
  String? error;
  bool loading = true;

  void start() {
    _roomsSubscription ??= repository.watchWaitingRooms().listen((value) {
      rooms = value;
      loading = false;
      notifyListeners();
    }, onError: _report);
    _statsSubscription ??= repository.watchStats().listen((value) {
      stats = value;
      notifyListeners();
    });
  }

  Future<T?> run<T>(Future<T> Function() action) async {
    try {
      error = null;
      notifyListeners();
      return await action();
    } catch (exception) {
      _report(exception);
      return null;
    }
  }

  void _report(Object exception) {
    final raw = exception.toString();
    error = raw.length > 180
        ? 'Không thể tải dữ liệu online. Kiểm tra kết nối rồi thử lại.'
        : raw;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _roomsSubscription?.cancel();
    _statsSubscription?.cancel();
    super.dispose();
  }
}

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key, required this.repository});
  final OnlineRoomRepository repository;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  late final LobbyViewModel model;
  final code = TextEditingController();

  @override
  void initState() {
    super.initState();
    GameAudio.instance.startMusic();
    model = LobbyViewModel(widget.repository)..start();
  }

  @override
  void dispose() {
    code.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> _open(OnlineRoom? room) async {
    if (!mounted || room == null) return;
    await Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            WaitingRoomScreen(repository: widget.repository, roomId: room.id),
        transitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.035, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _quickJoin() async {
    final room = await model.run(widget.repository.quickJoin);
    if (room != null) {
      await _open(room);
    } else if (mounted) {
      final create = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa có phòng phù hợp'),
          content: const Text('Bạn có muốn tạo phòng mới?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('HỦY'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('TẠO PHÒNG'),
            ),
          ],
        ),
      );
      if (create == true) await _create();
    }
  }

  Future<void> _joinCode() async {
    if (code.text.trim().isEmpty) return;
    final room = await model.run(() => widget.repository.joinByCode(code.text));
    if (room == null && mounted) {
      _snack('Mã phòng không tồn tại hoặc phòng đã đầy.');
    }
    await _open(room);
  }

  Future<void> _create() async {
    final settings = await showDialog<RoomSettings>(
      context: context,
      builder: (_) => const CreateRoomDialog(),
    );
    if (settings == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreatingRoomDialog(),
    );
    OnlineRoom? room;
    try {
      room = await model.run(
        () => widget.repository
            .createRoom(settings)
            .timeout(const Duration(seconds: 12)),
      );
      if (room != null) {
        for (var index = 0; index < settings.initialBotCount; index++) {
          await model.run(
            () => widget.repository
                .addBot(room!.id, 'normal')
                .timeout(const Duration(seconds: 8)),
          );
        }
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    if (mounted && room != null) await _open(room);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 46,
      title: const Text('PHÒNG ĐẤU'),
      actions: [_appBarControls()],
    ),
    floatingActionButton: _CreateRoomButton(onPressed: _create),
    body: BangScenicBackground(
      overlay: .72,
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: model,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                if (model.error != null)
                  BangPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      model.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xffff8a7f)),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: BangMotion.resolve(context, BangMotion.standard),
                    switchInCurve: BangMotion.curve,
                    switchOutCurve: Curves.easeOut,
                    child: KeyedSubtree(
                      key: ValueKey('${model.loading}-${model.rooms.length}'),
                      child: _rooms(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _appBarControls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 108,
        height: 34,
        child: TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 10),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 14),
            hintText: 'Mã phòng',
            filled: true,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onSubmitted: (_) => _joinCode(),
        ),
      ),
      const SizedBox(width: 3),
      OutlinedButton(
        style: _lobbyButtonStyle,
        onPressed: _joinCode,
        child: const Text('VÀO'),
      ),
      const SizedBox(width: 3),
      FilledButton.tonal(
        style: _lobbyButtonStyle,
        onPressed: _quickJoin,
        child: const Text('NHANH'),
      ),
      const SizedBox(width: 6),
    ],
  );

  Widget _rooms() => RoomGrid(
    rooms: model.rooms,
    loading: model.loading,
    onJoin: (room) async =>
        _open(await model.run(() => widget.repository.joinRoom(room.id))),
    onCreate: _create,
  );
}

class _CreateRoomButton extends StatefulWidget {
  const _CreateRoomButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CreateRoomButton> createState() => _CreateRoomButtonState();
}

class _CreateRoomButtonState extends State<_CreateRoomButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 90),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween<double>(
      begin: 1,
      end: .96,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
    child: FloatingActionButton.extended(
      heroTag: 'create_room',
      backgroundColor: const Color(0xffe9ba57),
      foregroundColor: const Color(0xff43200d),
      icon: const Icon(Icons.add_circle_outline),
      label: const Text(
        'TẠO PHÒNG',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      onPressed: () async {
        await _controller.forward();
        await _controller.reverse();
        widget.onPressed();
      },
    ),
  );
}

class _CreatingRoomDialog extends StatelessWidget {
  const _CreatingRoomDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: 230,
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: const [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'ĐANG TẠO BÀN...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class RoomGrid extends StatelessWidget {
  const RoomGrid({
    super.key,
    required this.rooms,
    required this.loading,
    required this.onJoin,
    required this.onCreate,
  });

  final List<OnlineRoom> rooms;
  final bool loading;
  final Future<void> Function(OnlineRoom room) onJoin;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth >= 700
              ? 5
              : constraints.maxWidth >= 520
              ? 4
              : 3,
          mainAxisExtent: constraints.maxWidth >= 700 ? 104 : 116,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: rooms.length + 1 < 20 ? 20 : rooms.length + 1,
        itemBuilder: (context, index) {
          if (index >= rooms.length) {
            return loading ? _loadingTable(index) : _emptyTable();
          }
          final room = rooms[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onJoin(room),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: const DecorationImage(
                  image: AssetImage('assets/images/room_table.png'),
                  fit: BoxFit.cover,
                  opacity: .75,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xdd160c08), Color(0x22160c08)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.settings.roomName == 'Bàn mới'
                          ? 'BÀN ${room.code}'
                          : room.settings.roomName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    BangStatusPill(
                      label: room.status == RoomStatus.waiting
                          ? 'ĐANG CHỜ'
                          : 'ĐANG ĐẤU',
                      color: room.status == RoomStatus.waiting
                          ? const Color(0xff75d48a)
                          : bangGold,
                      icon: room.status == RoomStatus.waiting
                          ? Icons.meeting_room_outlined
                          : Icons.local_fire_department_outlined,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${room.totalCount}/${room.settings.maxPlayers} người  •  ${room.botCount} bot',
                      style: const TextStyle(
                        color: Color(0xffffd272),
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      'Mã ${room.code}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyTable() => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onCreate,
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xff20120d),
        border: Border.all(color: const Color(0xff725037)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xff4a2d1c),
            child: Icon(Icons.add, color: Color(0xffffd272), size: 26),
          ),
          SizedBox(height: 8),
          Text('BÀN TRỐNG', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 3),
          Text(
            'Chạm để tạo bàn',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    ),
  );

  Widget _loadingTable(int index) => Ink(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      image: const DecorationImage(
        image: AssetImage('assets/images/room_table.png'),
        fit: BoxFit.cover,
        opacity: .45,
      ),
      border: Border.all(color: const Color(0xff725037)),
    ),
    child: Center(
      child: Text(
        'BÀN ${index + 1}',
        style: const TextStyle(
          color: Colors.white54,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({
    super.key,
    required this.repository,
    required this.roomId,
  });
  final OnlineRoomRepository repository;
  final String roomId;
  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  StreamSubscription<OnlineRoom?>? subscription;
  OnlineRoom? room;
  PlayerProfile? profile;
  String? error;
  bool startingGame = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await subscription?.cancel();
    subscription = null;
    try {
      profile = await widget.repository.ensureSignedIn();
      subscription = widget.repository
          .watchRoom(widget.roomId)
          .listen(
            (value) {
              if (!mounted) return;
              setState(() {
                room = value;
                if (value?.status == RoomStatus.starting ||
                    value?.status == RoomStatus.playing ||
                    value?.phase == 'choosing_character') {
                  startingGame = false;
                }
              });
            },
            onError: (Object value) {
              if (mounted) setState(() => error = '$value');
            },
          );
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> _call(Future<void> Function() action) async {
    try {
      GameAudio.instance.playSfx('button_tap');
      await action();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$exception')));
      }
    }
  }

  Future<void> _startTestGame(OnlineRoom current) async {
    setState(() {
      startingGame = true;
      error = null;
    });
    try {
      GameAudio.instance.playSfx('button_tap');
      final requiredBots = current.settings.maxPlayers - current.totalCount;
      for (var index = 0; index < requiredBots; index++) {
        await widget.repository.addBot(current.id, 'normal');
      }
      await widget.repository.startGame(current.id);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        startingGame = false;
        error = '$exception';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$exception')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = room;
    if (current == null) {
      if (error == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        backgroundColor: const Color(0xff160c08),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: Colors.redAccent,
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'KHÔNG TẢI ĐƯỢC PHÒNG',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() => error = null);
                      _load();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('THỬ LẠI'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('VỀ SẢNH'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (startingGame && current.status == RoomStatus.waiting) {
      return const _RoomBootScreen(
        title: 'DANG KHOI TAO TRAN DAU',
        detail: 'Dang nap ban, tron vai tro va chia bai...',
      );
    }
    if (current.status == RoomStatus.starting ||
        current.phase == 'choosing_character') {
      // `current` is already an authoritative snapshot received from the
      // room stream.  Do not wait for a second subscription here: a late
      // WebSocket event used to leave this gate on the brown loading screen.
      return GameSetupScreen(repository: widget.repository, room: current);
    }
    if (current.status == RoomStatus.playing) {
      // Do not gate the table behind a second WebSocket subscription. The
      // current room snapshot is already authoritative and contains the
      // private hand when available. Rendering immediately prevents a black
      // or endless loading screen if that secondary stream reconnects late.
      return OnlineBattleScreen(repository: widget.repository, room: current);
    }
    if (current.phase == 'game_over') {
      final orderedMembers = [...current.members]
        ..sort((left, right) => left.seat.compareTo(right.seat));
      return Scaffold(
        backgroundColor: const Color(0xff160c08),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      size: 72,
                      color: Color(0xffffc451),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'TRẬN ĐẤU KẾT THÚC',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffc451),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      current.winner ?? 'Đang xác định phe thắng',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'VAI TRÒ CÔNG KHAI',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xffffc451),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...orderedMembers.map(
                      (member) => ListTile(
                        dense: true,
                        leading: Icon(
                          member.isAlive
                              ? Icons.person
                              : Icons.person_off_outlined,
                          color: member.isAlive
                              ? const Color(0xffe7c58a)
                              : Colors.white38,
                        ),
                        title: Text(member.displayName),
                        trailing: Text(
                          _roleLabel(member.revealedRole),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _roleColor(member.revealedRole),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('VỀ SẢNH'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final self = profile == null ? null : current.memberFor(profile!.uid);
    final isHost =
        self?.isHost == true ||
        (profile != null && current.isHost(profile!.uid));
    final guestsReady = current.members
        .where((member) => !member.isBot && !member.isHost)
        .every((member) => member.isReady && member.isOnline);
    final canHostStart =
        guestsReady && (current.totalCount >= 4 || current.settings.allowBots);
    final startHint = !guestsReady
        ? 'Đang chờ tất cả khách sẵn sàng.'
        : current.totalCount < 4 && !current.settings.allowBots
        ? 'Cần đủ 4 người hoặc bật cho phép bot.'
        : current.totalCount < 4
        ? 'Bấm BẮT ĐẦU để tự thêm bot còn thiếu.'
        : 'Tất cả đã sẵn sàng.';
    return Scaffold(
      backgroundColor: const Color(0xff160c08),
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text('${current.settings.roomName} • ${current.code}'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              Text(
                '${current.totalCount}/${current.settings.maxPlayers}  •  ${current.humanCount} người thật  •  ${current.botCount} bot  •  ${current.settings.turnDurationSeconds}s',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) => GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: size.maxWidth > 760 ? 4 : 2,
                      childAspectRatio: 2.3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: current.settings.maxPlayers,
                    itemBuilder: (context, index) {
                      final member = current.members
                          .where((item) => item.seat == index)
                          .firstOrNull;
                      return _seat(member, index, isHost);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff26150e),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff6c4425)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Chủ phòng bấm BẮT ĐẦU; khách chỉ cần SẴN SÀNG. $startHint ${error ?? ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    OutlinedButton.icon(
                      style: _lobbyButtonStyle,
                      onPressed: () async {
                        await _call(
                          () => widget.repository.leaveRoom(current.id),
                        );
                        if (!mounted) return;
                        Navigator.of(this.context).pop();
                      },
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('RỜI PHÒNG'),
                    ),
                    if (!isHost)
                      FilledButton.icon(
                        style: _lobbyButtonStyle,
                        onPressed: profile == null
                            ? null
                            : () => _call(
                                () => widget.repository.setReady(
                                  current.id,
                                  !(self?.isReady ?? false),
                                ),
                              ),
                        icon: Icon(
                          self?.isReady == true ? Icons.close : Icons.check,
                          size: 16,
                        ),
                        label: Text(
                          self?.isReady == true ? 'HỦY READY' : 'SẴN SÀNG',
                        ),
                      ),
                    if (isHost) ...[
                      OutlinedButton.icon(
                        style: _lobbyButtonStyle,
                        onPressed:
                            current.settings.allowBots && current.hasSeats
                            ? () => _call(
                                () => widget.repository.addBot(
                                  current.id,
                                  'normal',
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.smart_toy_outlined, size: 16),
                        label: const Text('THÊM BOT'),
                      ),
                    ],
                  ],
                ),
              ),
              if (isHost) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canHostStart
                        ? () => _startTestGame(current)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      current.totalCount < 4 && current.settings.allowBots
                          ? 'BẮT ĐẦU (THÊM BOT TỰ ĐỘNG)'
                          : 'BẮT ĐẦU VÁN ĐẤU',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _seat(RoomMember? member, int index, bool isHost) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      color: member?.isBot == true
          ? const Color(0xff26331d)
          : member?.isReady == true
          ? const Color(0xff1e3824)
          : const Color(0xff352014),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: member == null
            ? const Color(0xff725037)
            : member.isReady
            ? const Color(0xff75d48a)
            : const Color(0xffb88957),
        width: member?.isReady == true ? 2 : 1,
      ),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: member == null
          ? Center(
              child: Text(
                'GHẾ ${index + 1}\nTRỐNG',
                textAlign: TextAlign.center,
              ),
            )
          : Row(
              children: [
                Icon(member.isBot ? Icons.smart_toy : Icons.person),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${member.displayName}${member.isHost ? ' ★' : ''}\n${member.isBot
                        ? 'BOT – ${member.difficulty}'
                        : member.isHost
                        ? 'CHỦ PHÒNG'
                        : member.isReady
                        ? 'ĐÃ SẴN SÀNG'
                        : 'CHƯA SẴN SÀNG'}',
                  ),
                ),
                if (isHost && member.isBot)
                  IconButton(
                    onPressed: () => _call(
                      () => widget.repository.removeBot(room!.id, member.id),
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
    ),
  );
}

class _RoomBootScreen extends StatelessWidget {
  const _RoomBootScreen({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    body: Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/room_table.png'),
                fit: BoxFit.cover,
                opacity: .7,
              ),
            ),
          ),
        ),
        const Positioned.fill(child: ColoredBox(color: Color(0xb0160c08))),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xffffc451),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffffc451),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String _roleLabel(String? role) => switch (role) {
  'sheriff' => 'CẢNH SÁT TRƯỞNG',
  'deputy' => 'CẢNH SÁT PHÓ',
  'outlaw' => 'KẺ CƯỚP',
  'renegade' => 'KẺ PHẢN BỘI',
  _ => 'CHƯA CÔNG KHAI',
};

Color _roleColor(String? role) => switch (role) {
  'sheriff' => const Color(0xffffc451),
  'deputy' => const Color(0xff64b5f6),
  'outlaw' => const Color(0xffef5350),
  'renegade' => const Color(0xffba68c8),
  _ => Colors.white54,
};

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({super.key});
  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  int maxPlayers = 8, duration = 45, botCount = 3;
  bool isPublic = true, voice = true, chat = true, bots = true;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AlertDialog(
      title: const Text('TẠO VÁN ĐẤU', style: TextStyle(fontSize: 15)),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      content: SizedBox(
        width: 290,
        height: 194,
        child: Column(
          children: [
            const TabBar(
              labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: 'THIẾT LẬP'),
                Tab(text: 'TÙY CHỌN'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        _select(
                          'Số người',
                          maxPlayers,
                          [4, 5, 6, 7, 8],
                          (value) => setState(() {
                            maxPlayers = value;
                            if (botCount >= maxPlayers) {
                              botCount = maxPlayers - 1;
                            }
                          }),
                          suffix: 'người',
                        ),
                        _select(
                          'Lượt',
                          duration,
                          [30, 45, 60, 90],
                          (value) => setState(() => duration = value),
                          suffix: 'giây',
                        ),
                        _select(
                          'Bot',
                          botCount,
                          List.generate(maxPlayers, (index) => index),
                          (value) => setState(() => botCount = value),
                          suffix: 'bot',
                          enabled: bots,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        _check(
                          'Công khai',
                          isPublic,
                          (v) => setState(() => isPublic = v),
                        ),
                        _check(
                          'Voice',
                          voice,
                          (v) => setState(() => voice = v),
                        ),
                        _check('Chat', chat, (v) => setState(() => chat = v)),
                        _check(
                          'Cho phép bot',
                          bots,
                          (v) => setState(() => bots = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      actions: [
        Row(
          children: [
            SizedBox(
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('HỦY'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text(
                    'TẠO PHÒNG',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    RoomSettings(
                      roomName: 'Bàn mới',
                      maxPlayers: maxPlayers,
                      isPublic: isPublic,
                      turnDurationSeconds: duration,
                      voiceEnabled: voice,
                      chatEnabled: chat,
                      allowBots: bots,
                      initialBotCount: bots ? botCount : 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _select(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> onChanged, {
    required String suffix,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: value,
            isDense: true,
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            ),
            items: values
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text('$item $suffix'),
                  ),
                )
                .toList(),
            onChanged: enabled ? (item) => onChanged(item ?? value) : null,
          ),
        ),
      ],
    ),
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      SizedBox(
        height: 31,
        child: CheckboxListTile(
          value: value,
          onChanged: (checked) => onChanged(checked ?? false),
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      );
}
