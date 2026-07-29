import 'dart:async';

import 'package:flutter/material.dart';

import 'data/online_room_repository.dart';
import 'domain/online_models.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({
    super.key,
    required this.repository,
    required this.room,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    body: SafeArea(
      child: StreamBuilder<PrivateSetupState?>(
        stream: widget.repository.watchPrivateSetup(widget.room.id),
        builder: (context, snapshot) {
          final state = snapshot.data;
          final choosing = widget.room.phase == 'choosing_character';
          return LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'KHỞI TẠO TRẬN ĐẤU',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xffffc451),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_phaseLabel(widget.room.phase)),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.room.members
                          .map(
                            (member) => Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                member.isBot ? Icons.smart_toy : Icons.person,
                                size: 15,
                              ),
                              label: Text(
                                member.displayName,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (state?.role != null) ...[
                      const SizedBox(height: 10),
                      _RoleCard(role: state!.role!),
                    ],
                    if (choosing) ...[
                      const SizedBox(height: 10),
                      _SelectionDeadline(deadline: state?.selectionDeadlineAt),
                    ],
                    if (choosing && state != null && !state.submitted) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'CHỌN 1 TRONG 2 THẺ NHÂN VẬT',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: state.characterOptions
                            .map(
                              (id) => _CharacterChoice(
                                id: id,
                                onTap: () => widget.repository.chooseCharacter(
                                  widget.room.id,
                                  id,
                                  '${DateTime.now().microsecondsSinceEpoch}_$id',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ] else if (choosing)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Đã chọn. Đang chờ những người chơi khác...',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _SelectionDeadline extends StatelessWidget {
  const _SelectionDeadline({required this.deadline});
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final seconds = deadline?.difference(DateTime.now()).inSeconds.clamp(0, 60);
    final urgent = seconds != null && seconds <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? Colors.redAccent : const Color(0xffffc451)).withValues(
          alpha: .16,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: urgent ? Colors.redAccent : const Color(0xffffc451),
        ),
      ),
      child: Text(
        seconds == null
            ? 'ĐANG ĐỒNG BỘ THẺ...'
            : 'CÒN ${seconds}s ĐỂ CHỌN · HẾT GIỜ TỰ CHỌN',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: urgent ? Colors.redAccent : const Color(0xffffd272),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xfff4dfac),
      border: Border.all(color: const Color(0xffffc451), width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        const Text(
          'VAI TRÒ CỦA BẠN',
          style: TextStyle(
            color: Color(0xff4d2410),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _roleLabel(role),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff2b160b),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _CharacterChoice extends StatelessWidget {
  const _CharacterChoice({required this.id, required this.onTap});
  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 190,
        height: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xfff4dfac),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffffc451), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _characterName(id),
              style: const TextStyle(
                color: Color(0xff30170a),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              _characterHint(id),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xff59331a), fontSize: 10),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'CHỌN',
                style: TextStyle(
                  color: Color(0xff7a430e),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _phaseLabel(String phase) => switch (phase) {
  'choosing_character' => 'Mỗi người nhận 2 thẻ nhân vật.',
  'turn_start' => 'Sẵn sàng vào bàn đấu.',
  _ => 'Đang xác nhận người chơi...',
};

String _roleLabel(String role) => switch (role) {
  'sheriff' => 'CẢNH SÁT TRƯỞNG',
  'deputy' => 'CẢNH SÁT PHÓ',
  'outlaw' => 'KẺ CƯỚP',
  'renegade' => 'KẺ PHẢN BỘI',
  _ => 'VAI TRÒ BÍ MẬT',
};

String _characterName(String id) => id
    .split('_')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String _characterHint(String id) => switch (id) {
  'willy_the_kid' => 'Có thể dùng nhiều BANG trong lượt.',
  'slab_the_killer' => 'BANG cần 2 lá Né để tránh.',
  'lucky_duke' => 'Rút 2 lá khi phán xét, chọn 1.',
  'calamity_janet' => 'Đổi BANG và Né cho nhau.',
  'vulture_sam' => 'Nhận bài của người bị loại.',
  _ => 'Chọn nhân vật để xem kỹ năng trong trận.',
};
