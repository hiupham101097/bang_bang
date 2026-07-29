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
          final phase = state?.phase ?? widget.room.phase;
          final choosingRole = phase == 'role_selection';
          final choosingCharacter =
              phase == 'character_selection' || phase == 'choosing_character';
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
                    Text(_phaseLabel(phase)),
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
                    const SizedBox(height: 10),
                    if (state != null)
                      _RoleDeckPreview(
                        cards: state.roleDeck,
                        playerCount: widget.room.members.length,
                        playerId: state.playerId,
                        enabled: choosingRole && state.role == null,
                        onPick: (cardId) => widget.repository.chooseRole(
                          widget.room.id,
                          cardId,
                        ),
                      ),
                    if (state?.role != null) ...[
                      const SizedBox(height: 10),
                      _RoleCard(role: state!.role!),
                    ],
                    if (choosingRole || choosingCharacter) ...[
                      const SizedBox(height: 10),
                      _SelectionDeadline(deadline: state?.selectionDeadlineAt),
                    ],
                    if (choosingRole && state?.role == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('CHON 1 LA VAI TRO'),
                      )
                    else if (choosingCharacter &&
                        state != null &&
                        state.characterOptions.length < 2) ...[
                      const SizedBox(height: 8),
                      Text(
                        'CHON 2 LA NHAN VAT (${state.characterOptions.length}/2)',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: state.characterDeck
                            .map(
                              (card) => _SetupCharacterCard(
                                card: card,
                                selected: state.characterOptions.contains(card.value),
                                enabled: !card.isPicked,
                                onTap: () => widget.repository
                                    .takeCharacterCard(widget.room.id, card.id),
                              ),
                            )
                            .toList(),
                      ),
                    ] else if (choosingCharacter &&
                        state != null &&
                        !state.submitted) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'CHON 1 TRONG 2 LA DE NHAN CHUC NANG',
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
                    ] else if (choosingCharacter)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Da chon. Dang cho nhung nguoi choi khac...'),
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

class _RoleDeckPreview extends StatelessWidget {
  const _RoleDeckPreview({
    required this.cards,
    required this.playerCount,
    required this.playerId,
    required this.enabled,
    required this.onPick,
  });

  final List<SetupChoice> cards;
  final int playerCount;
  final String? playerId;
  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final visibleCards = cards.isEmpty
        ? _setupRoleDeck(playerCount)
              .asMap()
              .entries
              .map((entry) => SetupChoice(
                    id: 'preview_${entry.key}',
                    value: entry.value,
                  ))
              .toList()
        : cards;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: visibleCards
          .map(
            (card) {
              final selected = playerId != null && card.pickedBy == playerId;
              final canPick = enabled && !card.isPicked;
              return Opacity(
                opacity: !card.isPicked || selected ? 1 : .38,
                child: InkWell(
                  onTap: canPick ? () => onPick(card.id) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 42,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? const Color(0xffffc451)
                            : const Color(0xff6e492a),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(_roleAsset(card.value), fit: BoxFit.cover),
                  ),
                ),
              );
            },
          )
          .toList(),
    );
  }
}
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xfff4dfac),
      border: Border.all(color: const Color(0xffffc451), width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Image.asset(_roleAsset(role), height: 86, fit: BoxFit.contain),
        const SizedBox(height: 4),
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

class _SetupCharacterCard extends StatelessWidget {
  const _SetupCharacterCard({
    required this.card,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SetupChoice card;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled || selected ? 1 : .35,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        width: 94,
        height: 132,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xfff4dfac),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xffffc451) : const Color(0xff7a430e),
            width: selected ? 3 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                _characterAsset(card.value),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _characterName(card.value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff30170a),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
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
        width: 136,
        height: 184,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xfff4dfac),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffffc451), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Image.asset(_characterAsset(id), fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _characterName(id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff30170a),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
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
  'role_selection' => 'Moi nguoi chon 1 la vai tro trong 60s.',
  'character_selection' => 'Moi nguoi chon 2 la nhan vat, roi giu lai 1.',
  'choosing_character' => 'Mỗi người nhận 2 thẻ nhân vật.',
  'turn_start' => 'Sẵn sàng vào bàn đấu.',
  _ => 'Đang xác nhận người chơi...',
};

List<String> _setupRoleDeck(int playerCount) {
  final base = switch (playerCount.clamp(4, 8)) {
    4 => ['sheriff', 'deputy', 'raider', 'raider'],
    5 => ['sheriff', 'deputy', 'raider', 'raider', 'traitor'],
    6 => ['sheriff', 'deputy', 'deputy', 'raider', 'raider', 'traitor'],
    7 => [
      'sheriff',
      'deputy',
      'deputy',
      'raider',
      'raider',
      'raider',
      'traitor',
    ],
    _ => [
      'sheriff',
      'deputy',
      'deputy',
      'guardian',
      'raider',
      'raider',
      'raider',
      'traitor',
    ],
  };
  return [...base, 'guardian'].take(playerCount + 1).toList();
}

String _roleAsset(String role) => switch (role) {
  'sheriff' => 'assets/images/role_sheriff.png',
  'deputy' => 'assets/images/role_deputy.png',
  'guardian' => 'assets/images/role_guardian.png',
  'outlaw' || 'raider' => 'assets/images/role_raider.png',
  'renegade' || 'traitor' => 'assets/images/role_traitor.png',
  _ => 'assets/images/role_deputy.png',
};

String _characterAsset(String id) => switch (id) {
  'doctor_lee' => 'assets/images/doctor_lee.png',
  'iron_rose' || 'rose_doolan' || 'rose_oolan' => 'assets/images/iron_rose.png',
  'lucky_joe' || 'lucky_duke' => 'assets/images/lucky_joe.png',
  'quick_jack' || 'black_jack' => 'assets/images/quick_jack.png',
  _ => 'assets/images/characters/$id.png',
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
