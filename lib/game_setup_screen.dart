import 'dart:async';
import 'dart:math' as math;

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
  String? _inspectedCharacterId;

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
          final isRoleStep = phase == 'role_selection';
          final isCharacterStep =
              phase == 'character_selection' || phase == 'choosing_character';
          final selectedCharacter = _selectedCharacterForCenter(state);

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 620;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  children: [
                    _SetupHeader(
                      phase: phase,
                      deadline: state?.selectionDeadlineAt,
                      members: widget.room.members,
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    Expanded(
                      child: _SetupCenterStage(
                        phase: phase,
                        role: state?.role,
                        selectedCharacterId: selectedCharacter,
                        canConfirmCharacter:
                            selectedCharacter != null &&
                            state != null &&
                            !state.submitted &&
                            state.characterOptions.contains(selectedCharacter),
                        onConfirmCharacter: selectedCharacter == null
                            ? null
                            : () => widget.repository.chooseCharacter(
                                widget.room.id,
                                selectedCharacter,
                                '${DateTime.now().microsecondsSinceEpoch}_$selectedCharacter',
                              ),
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    SizedBox(
                      height: compact ? 150 : 184,
                      child: state == null
                          ? const Center(child: CircularProgressIndicator())
                          : isRoleStep
                          ? _RoleDeck(
                              cards: state.roleDeck,
                              playerCount: widget.room.members.length,
                              playerId: state.playerId,
                              canPick: state.role == null,
                              onPick: (cardId) => widget.repository.chooseRole(
                                widget.room.id,
                                cardId,
                              ),
                            )
                          : isCharacterStep &&
                                state.characterOptions.length < 2
                          ? _CharacterDeck(
                              cards: state.characterDeck,
                              selectedValues: state.characterOptions.toSet(),
                              onPick: (cardId) => widget.repository
                                  .takeCharacterCard(widget.room.id, cardId),
                            )
                          : isCharacterStep && !state.submitted
                          ? _FinalCharacterChoices(
                              ids: state.characterOptions,
                              inspectedId: selectedCharacter,
                              onInspect: (id) =>
                                  setState(() => _inspectedCharacterId = id),
                            )
                          : const Center(
                              child: Text(
                                'Dang cho nhung nguoi choi khac...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );

  String? _selectedCharacterForCenter(PrivateSetupState? state) {
    if (state == null || state.characterOptions.isEmpty) return null;
    if (state.characterOptions.length < 2) return null;
    if (_inspectedCharacterId != null &&
        state.characterOptions.contains(_inspectedCharacterId)) {
      return _inspectedCharacterId;
    }
    return null;
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({
    required this.phase,
    required this.deadline,
    required this.members,
  });

  final String phase;
  final DateTime? deadline;
  final List<RoomMember> members;

  @override
  Widget build(BuildContext context) {
    final seconds = deadline?.difference(DateTime.now()).inSeconds.clamp(0, 60);
    final urgent = seconds != null && seconds <= 10;
    return SizedBox(
      height: 58,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _phaseTitle(phase),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffffc451),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: urgent
                      ? const Color(0xff5a1913)
                      : const Color(0xff2c1a0f),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: urgent ? Colors.redAccent : const Color(0xffffc451),
                  ),
                ),
                child: Text(
                  seconds == null ? '--' : '${seconds}s',
                  style: TextStyle(
                    color: urgent ? Colors.redAccent : const Color(0xffffd272),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 25,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: members
                    .map(
                      (member) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          avatar: Icon(
                            member.isBot ? Icons.smart_toy : Icons.person,
                            size: 13,
                          ),
                          label: Text(
                            member.displayName,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupCenterStage extends StatelessWidget {
  const _SetupCenterStage({
    required this.phase,
    required this.role,
    required this.selectedCharacterId,
    required this.canConfirmCharacter,
    required this.onConfirmCharacter,
  });

  final String phase;
  final String? role;
  final String? selectedCharacterId;
  final bool canConfirmCharacter;
  final VoidCallback? onConfirmCharacter;

  @override
  Widget build(BuildContext context) {
    if (phase == 'role_selection') {
      return _CenterRoleReveal(role: role);
    }
    if (phase == 'character_selection' || phase == 'choosing_character') {
      return _CenterCharacterReveal(
        id: selectedCharacterId,
        canConfirm: canConfirmCharacter,
        onConfirm: onConfirmCharacter,
      );
    }
    return const Center(
      child: Text(
        'Dang dong bo tran dau...',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}

class _CenterRoleReveal extends StatelessWidget {
  const _CenterRoleReveal({required this.role});
  final String? role;

  @override
  Widget build(BuildContext context) => Center(
    child: role == null
        ? const _CardBack(width: 118, height: 164, label: 'CHON 1 LA')
        : _FramedImageCard(
            asset: _roleCardAsset(role!),
            width: 126,
            height: 176,
            footer: _roleLabel(role!),
          ),
  );
}

class _CenterCharacterReveal extends StatelessWidget {
  const _CenterCharacterReveal({
    required this.id,
    required this.canConfirm,
    required this.onConfirm,
  });

  final String? id;
  final bool canConfirm;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) => Center(
    child: id == null
        ? const _CardBack(width: 118, height: 164, label: 'NHAN XEM')
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FramedImageCard(
                asset: _characterAsset(id!),
                width: 126,
                height: 176,
                footer: _characterName(id!),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _characterName(id!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffffd272),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _characterHint(id!),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: canConfirm ? onConfirm : null,
                      child: const Text('CHON'),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}

class _RoleDeck extends StatelessWidget {
  const _RoleDeck({
    required this.cards,
    required this.playerCount,
    required this.playerId,
    required this.canPick,
    required this.onPick,
  });

  final List<SetupChoice> cards;
  final int playerCount;
  final String? playerId;
  final bool canPick;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final visibleCards = cards.isEmpty
        ? _setupRoleDeck(playerCount)
              .asMap()
              .entries
              .map(
                (entry) => SetupChoice(
                  id: 'preview_${entry.key}',
                  value: entry.value,
                ),
              )
              .toList()
        : cards;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth / visibleCards.length - 6)
            .clamp(34.0, 54.0);
        final cardHeight = cardWidth * 1.4;
        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: visibleCards.map((card) {
              final mine = playerId != null && card.pickedBy == playerId;
              final enabled = canPick && !card.isPicked;
              return Opacity(
                opacity: !card.isPicked || mine ? 1 : .34,
                child: InkWell(
                  onTap: enabled ? () => onPick(card.id) : null,
                  borderRadius: BorderRadius.circular(5),
                  child: _CardBack(
                    width: cardWidth,
                    height: cardHeight,
                    label: '',
                    highlighted: mine,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CharacterDeck extends StatelessWidget {
  const _CharacterDeck({
    required this.cards,
    required this.selectedValues,
    required this.onPick,
  });

  final List<SetupChoice> cards;
  final Set<String> selectedValues;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = cards.length > 12 ? 8 : math.min(cards.length, 6);
      final cardWidth = (constraints.maxWidth / math.max(1, columns) - 6)
          .clamp(32.0, 52.0);
      final cardHeight = cardWidth * 1.4;
      return Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 5,
          runSpacing: 5,
          children: cards.map((card) {
            final selected = selectedValues.contains(card.value);
            final enabled = !card.isPicked;
            return Opacity(
              opacity: enabled || selected ? 1 : .32,
              child: InkWell(
                onTap: enabled ? () => onPick(card.id) : null,
                borderRadius: BorderRadius.circular(5),
                child: _CardBack(
                  width: cardWidth,
                  height: cardHeight,
                  label: '',
                  highlighted: selected,
                ),
              ),
            );
          }).toList(),
        ),
      );
    },
  );
}

class _FinalCharacterChoices extends StatelessWidget {
  const _FinalCharacterChoices({
    required this.ids,
    required this.inspectedId,
    required this.onInspect,
  });

  final List<String> ids;
  final String? inspectedId;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: ids.map((id) {
      final selected = id == inspectedId;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: InkWell(
          onTap: () => onInspect(id),
          borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 76,
          height: 106,
          padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xfff4dfac),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xffffc451)
                    : const Color(0xff7a430e),
                width: selected ? 3 : 1,
              ),
            ),
            child: Image.asset(_characterAsset(id), fit: BoxFit.contain),
          ),
        ),
      );
    }).toList(),
  );
}

class _FramedImageCard extends StatelessWidget {
  const _FramedImageCard({
    required this.asset,
    required this.width,
    required this.height,
    required this.footer,
  });

  final String asset;
  final double width;
  final double height;
  final String footer;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0xfff4dfac),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffffc451), width: 2),
      boxShadow: const [BoxShadow(color: Color(0xaa000000), blurRadius: 10)],
    ),
    child: Column(
      children: [
        Expanded(child: Image.asset(asset, fit: BoxFit.contain)),
        const SizedBox(height: 4),
        Text(
          footer,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xff30170a),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.width,
    required this.height,
    required this.label,
    this.highlighted = false,
  });

  final double width;
  final double height;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xff3a2115),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: highlighted ? const Color(0xffffc451) : const Color(0xffb5823b),
        width: highlighted ? 3 : 2,
      ),
      image: const DecorationImage(
        image: AssetImage('assets/images/bang_bang_logo.png'),
        fit: BoxFit.contain,
        opacity: .34,
      ),
    ),
    child: label.isEmpty
        ? null
        : Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xffffd272),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
  );
}

String _phaseTitle(String phase) => switch (phase) {
  'role_selection' => 'Chon vai tro',
  'character_selection' => 'Chon nhan vat',
  'choosing_character' => 'Chon nhan vat',
  'turn_start' => 'San sang vao van',
  _ => 'Khoi tao tran dau',
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

String _roleCardAsset(String role) => switch (role) {
  'sheriff' => 'assets/images/role_cards/sheriff_card.png',
  'deputy' => 'assets/images/role_cards/deputy_card.png',
  'guardian' => 'assets/images/role_cards/guardian_card.png',
  'outlaw' || 'raider' => 'assets/images/role_cards/raider_card.png',
  'renegade' || 'traitor' => 'assets/images/role_cards/traitor_card.png',
  _ => 'assets/images/role_cards/deputy_card.png',
};

String _characterAsset(String id) => switch (id) {
  'doctor_lee' => 'assets/images/doctor_lee.png',
  'iron_rose' || 'rose_doolan' || 'rose_oolan' => 'assets/images/iron_rose.png',
  'lucky_joe' || 'lucky_duke' => 'assets/images/lucky_joe.png',
  'quick_jack' || 'black_jack' => 'assets/images/quick_jack.png',
  _ => 'assets/images/characters/$id.png',
};

String _roleLabel(String role) => switch (role) {
  'sheriff' => 'Sheriff',
  'deputy' => 'Deputy',
  'guardian' => 'Guardian',
  'outlaw' || 'raider' => 'Raider',
  'renegade' || 'traitor' => 'Traitor',
  _ => 'Role',
};

String _characterName(String id) => id
    .split('_')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String _characterHint(String id) => switch (id) {
  'willy_the_kid' => 'Co the dung nhieu BANG trong mot luot.',
  'slab_the_killer' => 'BANG cua ban can 2 la Ne de tranh.',
  'lucky_duke' || 'lucky_joe' => 'Rut 2 la khi phan xet, chon 1.',
  'calamity_janet' => 'Co the dung BANG va Ne thay the nhau.',
  'vulture_sam' => 'Nhan bai cua nguoi vua bi loai.',
  'kit_carlson' => 'Xem 3 la dau bo bai, lay 2 va tra 1.',
  'black_jack' || 'quick_jack' => 'Neu la thu hai do, rut them 1 la.',
  'sid_ketchum' => 'Bo 2 la de hoi 1 mau.',
  'rose_doolan' || 'rose_oolan' || 'iron_rose' => 'Tam ban cua ban xa hon 1.',
  'paul_regret' => 'Nguoi khac nhin ban xa hon 1.',
  _ => 'Nhan vat co ky nang rieng trong van dau.',
};
