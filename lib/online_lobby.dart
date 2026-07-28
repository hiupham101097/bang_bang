import 'dart:async';

import 'package:flutter/material.dart';

import 'data/online_room_repository.dart';
import 'domain/online_models.dart';
import 'game_setup_screen.dart';
import 'online_battle_screen.dart';

const ButtonStyle _compactButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 26)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 6, vertical: 0),
  ),
  visualDensity: VisualDensity(horizontal: -4, vertical: -4),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 9)),
);

const ButtonStyle _lobbyButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 38)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  textStyle: WidgetStatePropertyAll(
    TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
    error = exception.toString();
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
      MaterialPageRoute(
        builder: (_) =>
            WaitingRoomScreen(repository: widget.repository, roomId: room.id),
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
    if (settings != null) {
      final room = await model.run(
        () => widget.repository.createRoom(settings),
      );
      if (room == null) return;
      for (var index = 0; index < settings.initialBotCount; index++) {
        await model.run(() => widget.repository.addBot(room.id, 'normal'));
      }
      await _open(room);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    appBar: AppBar(
      toolbarHeight: 40,
      title: const Text('PHÒNG ĐẤU'),
      actions: [
        AnimatedBuilder(
          animation: model,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Online: ${model.stats.onlineUsers}',
                style: const TextStyle(fontSize: 11, color: Color(0xffffd272)),
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: model,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              _controlBar(),
              if (model.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    model.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: model.loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rooms(),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _controlBar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: const Color(0xff26150e),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff6c4425)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final controls = [
          SizedBox(
            width: constraints.maxWidth >= 680 ? 250 : double.infinity,
            height: 38,
            child: TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Nhập mã phòng',
                filled: true,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
              ),
              onSubmitted: (_) => _joinCode(),
            ),
          ),
          OutlinedButton(
            style: _lobbyButtonStyle,
            onPressed: _joinCode,
            child: const Text('THAM GIA'),
          ),
          FilledButton.tonalIcon(
            style: _lobbyButtonStyle,
            onPressed: _quickJoin,
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('VÀO NHANH'),
          ),
          FilledButton.icon(
            style: _lobbyButtonStyle,
            onPressed: _create,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('TẠO BÀN'),
          ),
        ];
        return constraints.maxWidth >= 680
            ? Row(mainAxisSize: MainAxisSize.min, children: _spaced(controls))
            : Wrap(spacing: 7, runSpacing: 7, children: controls);
      },
    ),
  );

  List<Widget> _spaced(List<Widget> children) => [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0) const SizedBox(width: 7),
      children[index],
    ],
  ];

  Widget _rooms() => RoomGrid(
    rooms: model.rooms,
    onJoin: (room) async =>
        _open(await model.run(() => widget.repository.joinRoom(room.id))),
    onCreate: _create,
  );
}

class RoomGrid extends StatelessWidget {
  const RoomGrid({
    super.key,
    required this.rooms,
    required this.onJoin,
    required this.onCreate,
  });

  final List<OnlineRoom> rooms;
  final Future<void> Function(OnlineRoom room) onJoin;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: constraints.maxWidth >= 1050 ? 245 : 300,
          mainAxisExtent: 138,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: rooms.length < 8 ? 8 : rooms.length + 1,
        itemBuilder: (context, index) {
          if (index >= rooms.length) return _emptyTable();
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
                padding: const EdgeInsets.all(12),
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
                    Text(
                      '${room.totalCount}/${room.settings.maxPlayers} người  •  ${room.botCount} bot',
                      style: const TextStyle(color: Color(0xffffd272)),
                    ),
                    Text(
                      'Mã ${room.code}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    profile = await widget.repository.ensureSignedIn();
    subscription = widget.repository
        .watchRoom(widget.roomId)
        .listen(
          (value) {
            if (mounted) setState(() => room = value);
          },
          onError: (Object value) {
            if (mounted) setState(() => error = '$value');
          },
        );
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> _call(Future<void> Function() action) async {
    try {
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
    final requiredBots = 4 - current.totalCount;
    for (var index = 0; index < requiredBots; index++) {
      await _call(() => widget.repository.addBot(current.id, 'normal'));
    }
    await _call(() => widget.repository.startGame(current.id));
  }

  @override
  Widget build(BuildContext context) {
    final current = room;
    if (current == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (current.status == RoomStatus.starting ||
        current.phase == 'choosing_character') {
      return GameSetupScreen(repository: widget.repository, room: current);
    }
    if (current.status == RoomStatus.playing) {
      return OnlineBattleScreen(repository: widget.repository, room: current);
    }
    if (current.phase == 'game_over') {
      return Scaffold(
        backgroundColor: const Color(0xff160c08),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, size: 72, color: Color(0xffffc451)),
              SizedBox(height: 16),
              Text(
                'TRẬN ĐẤU KẾT THÚC',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xffffc451),
                ),
              ),
              const SizedBox(height: 8),
              Text(current.winner ?? 'Đang xác định phe thắng'),
            ],
          ),
        ),
      );
    }
    final isHost = profile != null && current.isHost(profile!.uid);
    final self = profile == null ? null : current.memberFor(profile!.uid);
    return Scaffold(
      backgroundColor: const Color(0xff160c08),
      appBar: AppBar(
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
                      'Test một người: tự thêm bot khi bắt đầu. ${error ?? ''}',
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
                      FilledButton.icon(
                        style: _lobbyButtonStyle,
                        onPressed: self?.isReady == true
                            ? () => _startTestGame(current)
                            : null,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('BẮT ĐẦU'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seat(RoomMember? member, int index, bool isHost) => Card(
    color: member?.isBot == true
        ? const Color(0xff26331d)
        : member?.isReady == true
        ? const Color(0xff1e3824)
        : const Color(0xff352014),
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
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      actions: [
        TextButton(
          style: _compactButtonStyle,
          onPressed: () => Navigator.pop(context),
          child: const Text('HỦY'),
        ),
        FilledButton(
          style: _compactButtonStyle,
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
          child: const Text('TẠO'),
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
