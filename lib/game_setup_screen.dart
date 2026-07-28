import 'package:flutter/material.dart';

import 'data/online_room_repository.dart';
import 'domain/online_models.dart';

class GameSetupScreen extends StatelessWidget {
  const GameSetupScreen({
    super.key,
    required this.repository,
    required this.room,
  });
  final OnlineRoomRepository repository;
  final OnlineRoom room;

  static const _names = {
    'paul_regret': 'Paul Regret',
    'el_gringo': 'El Gringo',
    'vulture_sam': 'Vulture Sam',
    'calamity_janet': 'Calamity Janet',
    'black_jack': 'Black Jack',
    'willy_the_kid': 'Willy the Kid',
    'lucky_duke': 'Lucky Duke',
    'kit_carlson': 'Kit Carlson',
    'rose_doolan': 'Rose Doolan',
    'suzy_lafayette': 'Suzy Lafayette',
    'bart_cassidy': 'Bart Cassidy',
    'jesse_jones': 'Jesse Jones',
    'slab_the_killer': 'Slab the Killer',
    'sid_ketchum': 'Sid Ketchum',
    'jourdonnais': 'Jourdonnais',
    'pedro_ramirez': 'Pedro Ramirez',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff160c08),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder<PrivateSetupState?>(
          stream: repository.watchPrivateSetup(room.id),
          builder: (context, snapshot) {
            final state = snapshot.data;
            final choosing = room.phase == 'choosing_character';
            return Column(
              children: [
                const Text(
                  'ĐANG KHỞI TẠO TRẬN ĐẤU',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xffffc451),
                  ),
                ),
                const SizedBox(height: 8),
                Text(_phaseLabel(room.phase)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: room.members
                      .map(
                        (member) => Chip(
                          avatar: Icon(
                            member.isBot ? Icons.smart_toy : Icons.person,
                          ),
                          label: Text(
                            '${member.displayName}${member.id == room.hostUid ? ' ★' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                ),
                const Spacer(),
                if (room.sheriffPlayerId != null)
                  const Text(
                    'CẢNH SÁT TRƯỞNG ĐÃ ĐƯỢC CÔNG KHAI',
                    style: TextStyle(color: Color(0xffffd366)),
                  ),
                if (state?.role != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: 240,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xfff4dfac),
                      border: Border.all(
                        color: const Color(0xffffc451),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
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
                        const SizedBox(height: 6),
                        Text(
                          _roleLabel(state!.role!),
                          style: const TextStyle(
                            color: Color(0xff2b160b),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (choosing && state != null && !state.submitted) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'CHỌN 1 TRONG 2 THẺ NHÂN VẬT',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: state.characterOptions
                        .map(
                          (id) => Padding(
                            padding: const EdgeInsets.all(8),
                            child: FilledButton(
                              onPressed: () => repository.chooseCharacter(
                                room.id,
                                id,
                                '${DateTime.now().microsecondsSinceEpoch}_$id',
                              ),
                              child: Text(_names[id] ?? id),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ] else if (choosing)
                  const Text(
                    'Đã chọn nhân vật. Đang chờ những người chơi khác...',
                  ),
                const Spacer(),
              ],
            );
          },
        ),
      ),
    ),
  );

  String _phaseLabel(String phase) => switch (phase) {
    'assigning_roles' => 'Đang chia vai trò...',
    'revealing_roles' => 'Đang công bố Cảnh sát trưởng...',
    'choosing_character' => 'Đang chọn nhân vật...',
    'finalizing_characters' => 'Đang thiết lập máu...',
    'initializing_deck' ||
    'dealing_initial_cards' => 'Đang trộn và chia bài...',
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
}
