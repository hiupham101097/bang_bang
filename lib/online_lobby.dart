import 'dart:async';

import 'package:flutter/material.dart';

import 'data/online_room_repository.dart';
import 'domain/online_models.dart';
import 'game_setup_screen.dart';
import 'online_battle_screen.dart';

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
      title: const Text('PHÒNG ĐẤU'),
      actions: [
        AnimatedBuilder(
          animation: model,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('Online: ${model.stats.onlineUsers}')),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: model,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'Nhập mã phòng',
                        filled: true,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _joinCode(),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _joinCode,
                    child: const Text('THAM GIA'),
                  ),
                  FilledButton(
                    onPressed: _quickJoin,
                    child: const Text('THAM GIA NHANH'),
                  ),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('TẠO VÁN ĐẤU'),
                  ),
                ],
              ),
              if (model.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    model.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 12),
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

  Widget _rooms() {
    if (model.rooms.isNotEmpty) {
      return RoomGrid(
        rooms: model.rooms,
        onJoin: (room) async =>
            _open(await model.run(() => widget.repository.joinRoom(room.id))),
      );
    }
    if (model.rooms.isEmpty) {
      return const Center(child: Text('Chưa có phòng công khai đang chờ.'));
    }
    return ListView.separated(
      itemCount: model.rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = model.rooms[index];
        return Card(
          color: const Color(0xff352014),
          child: ListTile(
            leading: const Icon(Icons.meeting_room, color: Color(0xffffc451)),
            title: Text(room.settings.roomName),
            subtitle: Text(
              'Mã ${room.code}  •  ${room.humanCount} người thật, ${room.botCount} bot  •  ${room.totalCount}/${room.settings.maxPlayers}\nVoice ${room.settings.voiceEnabled ? 'Bật' : 'Tắt'}  •  Lượt ${room.settings.turnDurationSeconds}s',
            ),
            isThreeLine: true,
            trailing: FilledButton(
              onPressed: () async => _open(
                await model.run(() => widget.repository.joinRoom(room.id)),
              ),
              child: const Text('THAM GIA'),
            ),
          ),
        );
      },
    );
  }
}

class RoomGrid extends StatelessWidget {
  const RoomGrid({super.key, required this.rooms, required this.onJoin});

  final List<OnlineRoom> rooms;
  final Future<void> Function(OnlineRoom room) onJoin;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return const Center(child: Text('Chưa có bàn công khai.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: constraints.maxWidth >= 1050 ? 260 : 320,
          mainAxisExtent: 150,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
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
                padding: const EdgeInsets.all(10),
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
                      room.settings.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${room.totalCount}/${room.settings.maxPlayers} người',
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
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: Text(
                      'Cần ≥4 tổng, ≥2 người thật và mọi người thật sẵn sàng. ${error ?? ''}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await _call(
                        () => widget.repository.leaveRoom(current.id),
                      );
                      if (!mounted) return;
                      Navigator.of(this.context).pop();
                    },
                    child: const Text('RỜI PHÒNG'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: self == null
                        ? null
                        : () => _call(
                            () => widget.repository.setReady(
                              current.id,
                              !self.isReady,
                            ),
                          ),
                    child: Text(
                      self?.isReady == true ? 'HỦY READY' : 'SẴN SÀNG',
                    ),
                  ),
                  if (isHost) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: current.settings.allowBots && current.hasSeats
                          ? () => _call(
                              () => widget.repository.addBot(
                                current.id,
                                'normal',
                              ),
                            )
                          : null,
                      child: const Text('THÊM BOT'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: current.canStart(profile!.uid)
                          ? () => _call(
                              () => widget.repository.startGame(current.id),
                            )
                          : null,
                      child: const Text('BẮT ĐẦU'),
                    ),
                  ],
                ],
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
  final name = TextEditingController();
  int maxPlayers = 8, duration = 45, botCount = 0;
  bool isPublic = true, voice = true, chat = true, bots = true;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('TẠO VÁN ĐẤU'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 24,
              decoration: const InputDecoration(labelText: 'Tên phòng'),
            ),
            DropdownButtonFormField<int>(
              initialValue: maxPlayers,
              decoration: const InputDecoration(labelText: 'Tối đa'),
              items: [4, 5, 6, 7, 8]
                  .map(
                    (v) => DropdownMenuItem(value: v, child: Text('$v người')),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                maxPlayers = v ?? 8;
                if (botCount >= maxPlayers) botCount = maxPlayers - 1;
              }),
            ),
            DropdownButtonFormField<int>(
              initialValue: duration,
              decoration: const InputDecoration(labelText: 'Lượt'),
              items: [30, 45, 60, 90]
                  .map(
                    (v) => DropdownMenuItem(value: v, child: Text('$v giây')),
                  )
                  .toList(),
              onChanged: (v) => setState(() => duration = v ?? 45),
            ),
            DropdownButtonFormField<int>(
              initialValue: botCount,
              decoration: const InputDecoration(labelText: 'Thêm bot ngay'),
              items: List.generate(maxPlayers, (index) => index)
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value bot'),
                    ),
                  )
                  .toList(),
              onChanged: bots
                  ? (value) => setState(() => botCount = value ?? 0)
                  : null,
            ),
            SwitchListTile(
              value: isPublic,
              onChanged: (v) => setState(() => isPublic = v),
              title: const Text('Công khai'),
            ),
            SwitchListTile(
              value: voice,
              onChanged: (v) => setState(() => voice = v),
              title: const Text('Voice'),
            ),
            SwitchListTile(
              value: chat,
              onChanged: (v) => setState(() => chat = v),
              title: const Text('Chat'),
            ),
            SwitchListTile(
              value: bots,
              onChanged: (v) => setState(() => bots = v),
              title: const Text('Cho phép bot'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('HỦY'),
      ),
      FilledButton(
        onPressed: () {
          final v = name.text.trim();
          if (v.isNotEmpty && v.length < 2) return;
          Navigator.pop(
            context,
            RoomSettings(
              roomName: v.isEmpty ? 'Phòng của Lucky Joe' : v,
              maxPlayers: maxPlayers,
              isPublic: isPublic,
              turnDurationSeconds: duration,
              voiceEnabled: voice,
              chatEnabled: chat,
              allowBots: bots,
              initialBotCount: bots ? botCount : 0,
            ),
          );
        },
        child: const Text('TẠO'),
      ),
    ],
  );
}
