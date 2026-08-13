import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/online_room_repository.dart';
import 'domain/online_models.dart';
import 'ui/bang_ui.dart';

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
  String? _inspectedCharacterId;
  String? _pendingRoleCardId;
  String? _pendingCharacterCardId;

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
          final selectedRole = _selectedRoleForCenter(state);
          final finalCharacterIds = state?.characterOptions.length == 2
              ? state!.characterOptions
              : const <String>[];
          final isRoleReveal = phase == 'role_reveal';
          if (state != null && finalCharacterIds.isEmpty) {
            _inspectedCharacterId = null;
          }
          final hasPickedRole =
              state?.roleDeck.any((card) => card.pickedBy == state.playerId) ??
              false;
          final isPickingRole = state != null && isRoleStep && !hasPickedRole;
          final isPickingCharacter =
              state != null &&
              isCharacterStep &&
              state.characterOptions.length < 2;
          final showCenterStage =
              state == null ||
              isRoleReveal ||
              (!isPickingRole && !isPickingCharacter) ||
              phase == 'choosing_character';

          return LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/images/room_table.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x66160c08)),
                  ),
                  Positioned.fill(
                    child: _SetupPlayerRing(members: widget.room.members),
                  ),
                  Positioned(
                    left: 8,
                    top: 6,
                    right: 8,
                    child: _SetupHeader(
                      phase: phase,
                      deadline: state?.selectionDeadlineAt,
                    ),
                  ),
                  if (showCenterStage)
                    Positioned.fill(
                      top: 34,
                      bottom: 8,
                      child: state == null
                          ? const Center(child: CircularProgressIndicator())
                          : _SetupCenterStage(
                              phase: phase,
                              role: selectedRole,
                              selectedCharacterId: selectedCharacter,
                              submitted: state.submitted,
                              finalCharacterIds: finalCharacterIds,
                              revealDelaySeconds: 0,
                              canConfirmCharacter:
                                  selectedCharacter != null &&
                                  !state.submitted &&
                                  state.characterOptions.contains(
                                    selectedCharacter,
                                  ),
                              onConfirmCharacter: selectedCharacter == null
                                  ? null
                                  : () => widget.repository.chooseCharacter(
                                      widget.room.id,
                                      selectedCharacter,
                                      '${DateTime.now().microsecondsSinceEpoch}_$selectedCharacter',
                                    ),
                              onInspectCharacter: (id) =>
                                  setState(() => _inspectedCharacterId = id),
                            ),
                    ),
                  if (state != null)
                    Positioned.fill(
                      top: 42,
                      bottom: 8,
                      child: IgnorePointer(
                        ignoring:
                            _pendingRoleCardId != null ||
                            _pendingCharacterCardId != null ||
                            !(isPickingRole || isPickingCharacter),
                        child: isPickingRole
                            ? _RoleDeck(
                                cards: state.roleDeck,
                                playerCount: widget.room.members.length,
                                playerId: state.playerId,
                                pendingCardId: _pendingRoleCardId,
                                canPick: !hasPickedRole,
                                onPick: (cardId) =>
                                    setState(() => _pendingRoleCardId = cardId),
                              )
                            : isPickingCharacter
                            ? _CharacterDeck(
                                cards: state.characterDeck,
                                playerId: state.playerId,
                                pendingCardId: _pendingCharacterCardId,
                                onPick: (cardId) => setState(
                                  () => _pendingCharacterCardId = cardId,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  if (state != null &&
                      isRoleStep &&
                      !hasPickedRole &&
                      _pendingRoleCardId != null)
                    Center(
                      child: _SetupPickConfirm(
                        title: 'Nhan vai tro nay?',
                        onCancel: () =>
                            setState(() => _pendingRoleCardId = null),
                        onConfirm: () async {
                          final cardId = _pendingRoleCardId;
                          if (cardId == null) return;
                          setState(() => _pendingRoleCardId = null);
                          await widget.repository.chooseRole(
                            widget.room.id,
                            cardId,
                          );
                        },
                        child: const _CardBack(
                          width: 102,
                          height: 143,
                          label: 'VAI TRO',
                          highlighted: true,
                        ),
                      ),
                    ),
                  if (state != null &&
                      isCharacterStep &&
                      state.characterOptions.length < 2 &&
                      _pendingCharacterCardId != null)
                    Center(
                      child: _SetupPickConfirm(
                        title:
                            'Chon la nhan vat ${state.characterOptions.length + 1}/2?',
                        onCancel: () =>
                            setState(() => _pendingCharacterCardId = null),
                        onConfirm: () async {
                          final cardId = _pendingCharacterCardId;
                          if (cardId == null) return;
                          setState(() => _pendingCharacterCardId = null);
                          await widget.repository.takeCharacterCard(
                            widget.room.id,
                            cardId,
                          );
                        },
                        child: const _CardBack(
                          width: 102,
                          height: 143,
                          label: 'NHAN VAT',
                          highlighted: true,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    ),
  );

  String? _selectedCharacterForCenter(PrivateSetupState? state) {
    if (state == null || state.characterOptions.isEmpty) return null;
    if (state.selectedCharacterId != null &&
        state.characterOptions.contains(state.selectedCharacterId)) {
      return state.selectedCharacterId;
    }
    if (state.characterOptions.length < 2) return null;
    if (_inspectedCharacterId != null &&
        state.characterOptions.contains(_inspectedCharacterId)) {
      return _inspectedCharacterId;
    }
    return null;
  }

  String? _selectedRoleForCenter(PrivateSetupState? state) {
    if (state == null) return null;
    final picked = state.roleDeck
        .where((card) => card.pickedBy == state.playerId)
        .firstOrNull;
    return picked?.value.isNotEmpty == true ? picked!.value : state.role;
  }
}

class _SetupHeader extends StatefulWidget {
  const _SetupHeader({required this.phase, required this.deadline});

  final String phase;
  final DateTime? deadline;

  @override
  State<_SetupHeader> createState() => _SetupHeaderState();
}

class _SetupHeaderState extends State<_SetupHeader> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _SetupHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (widget.deadline == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.deadline
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 60);
    final urgent = seconds != null && seconds <= 10;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const Icon(Icons.pause, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _phaseTitle(widget.phase),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xffffc451),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: urgent ? const Color(0xff5a1913) : const Color(0xff2c1a0f),
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
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupPlayerRing extends StatelessWidget {
  const _SetupPlayerRing({required this.members});

  final List<RoomMember> members;

  static const _seatPoints = <Offset>[
    Offset(.50, .05),
    Offset(.78, .10),
    Offset(.93, .43),
    Offset(.78, .76),
    Offset(.50, .84),
    Offset(.22, .76),
    Offset(.07, .43),
    Offset(.22, .10),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final seat = (math.min(constraints.maxWidth, constraints.maxHeight) * .14)
          .clamp(42.0, 68.0);
      final players = members.take(8).toList()
        ..sort((left, right) => left.seat.compareTo(right.seat));
      return Stack(
        children: [
          for (var index = 0; index < players.length; index++)
            () {
              final point = _seatPoints[index];
              final left = (point.dx * constraints.maxWidth - seat / 2).clamp(
                4.0,
                constraints.maxWidth - seat - 4,
              );
              final top = (point.dy * constraints.maxHeight - seat / 2).clamp(
                4.0,
                constraints.maxHeight - seat - 4,
              );
              final member = players[index];
              return Positioned(
                left: left,
                top: top,
                width: seat,
                height: seat,
                child: _SetupSeat(member: member),
              );
            }(),
        ],
      );
    },
  );
}

class _SetupSeat extends StatelessWidget {
  const _SetupSeat({required this.member});

  final RoomMember member;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xdd2a1811),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xffd6a13d), width: 2),
      boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 8)],
    ),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Image.asset(
              member.characterId == null
                  ? member.isBot
                        ? 'assets/images/role_raider.png'
                        : 'assets/images/role_deputy.png'
                  : _characterAsset(member.characterId!),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            ),
          ),
          Text(
            member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SetupCenterStage extends StatelessWidget {
  const _SetupCenterStage({
    required this.phase,
    required this.role,
    required this.selectedCharacterId,
    required this.submitted,
    required this.finalCharacterIds,
    required this.revealDelaySeconds,
    required this.canConfirmCharacter,
    required this.onConfirmCharacter,
    required this.onInspectCharacter,
  });

  final String phase;
  final String? role;
  final String? selectedCharacterId;
  final bool submitted;
  final List<String> finalCharacterIds;
  final int revealDelaySeconds;
  final bool canConfirmCharacter;
  final VoidCallback? onConfirmCharacter;
  final ValueChanged<String> onInspectCharacter;

  @override
  Widget build(BuildContext context) {
    if (phase == 'role_selection' || phase == 'role_reveal') {
      return _CenterRoleReveal(role: role);
    }
    if (phase == 'character_selection' || phase == 'choosing_character') {
      return _CenterCharacterReveal(
        id: selectedCharacterId,
        role: role,
        submitted: submitted,
        finalIds: finalCharacterIds,
        revealDelaySeconds: revealDelaySeconds,
        canConfirm: canConfirmCharacter,
        onConfirm: onConfirmCharacter,
        onInspect: onInspectCharacter,
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
            width: 116,
            height: 162,
            footer: _roleLabel(role!),
          ),
  );
}

class _CenterCharacterReveal extends StatelessWidget {
  const _CenterCharacterReveal({
    required this.id,
    required this.role,
    required this.submitted,
    required this.finalIds,
    required this.revealDelaySeconds,
    required this.canConfirm,
    required this.onConfirm,
    required this.onInspect,
  });

  final String? id;
  final String? role;
  final bool submitted;
  final List<String> finalIds;
  final int revealDelaySeconds;
  final bool canConfirm;
  final VoidCallback? onConfirm;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) => Center(
    child: id == null
        ? finalIds.length >= 2
              ? _CenterFinalCards(
                  ids: finalIds,
                  role: role,
                  revealDelaySeconds: revealDelaySeconds,
                  onInspect: onInspect,
                )
              : const _CardBack(width: 118, height: 164, label: 'CHON 2 LA')
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (role != null) ...[
                  _FramedImageCard(
                    asset: _roleCardAsset(role!),
                    width: 72,
                    height: 101,
                    footer: _roleLabel(role!),
                  ),
                  const SizedBox(width: 10),
                ],
                _FramedImageCard(
                  asset: _characterAsset(id!),
                  width: 116,
                  height: 162,
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
                      if (revealDelaySeconds > 0)
                        Text(
                          'Xem lai $revealDelaySeconds giay roi moi chon.',
                          style: const TextStyle(
                            color: Color(0xffffd272),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else
                        submitted
                            ? const Text(
                                'Dang cho nguoi choi khac...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : FilledButton(
                                onPressed: canConfirm ? onConfirm : null,
                                child: const Text('CHON'),
                              ),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );
}

class _CenterFinalCards extends StatelessWidget {
  const _CenterFinalCards({
    required this.ids,
    required this.role,
    required this.revealDelaySeconds,
    required this.onInspect,
  });

  final List<String> ids;
  final String? role;
  final int revealDelaySeconds;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (role != null) ...[
          _FramedImageCard(
            asset: _roleCardAsset(role!),
            width: 76,
            height: 106,
            footer: _roleLabel(role!),
          ),
          const SizedBox(width: 12),
        ],
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              revealDelaySeconds > 0
                  ? 'VAI TRO CUA BAN: ${_roleLabel(role ?? '')}'
                  : 'CHON 1 TRONG 2 LA',
              style: const TextStyle(
                color: Color(0xffffd272),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            if (revealDelaySeconds > 0)
              Text(
                'Dang lat bai nhan vat, con $revealDelaySeconds giay de xem.',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ids.take(2).map((id) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: InkWell(
                    onTap: () => onInspect(id),
                    borderRadius: BorderRadius.circular(10),
                    child: _FramedImageCard(
                      asset: _characterAsset(id),
                      width: 104,
                      height: 146,
                      footer: _characterName(id),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
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
    required this.pendingCardId,
    required this.canPick,
    required this.onPick,
  });

  final List<SetupChoice> cards;
  final int playerCount;
  final String? playerId;
  final String? pendingCardId;
  final bool canPick;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final visibleCards =
        (cards.isEmpty
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
                : cards)
            .take(playerCount.clamp(1, 8))
            .toList();
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
              final pending = card.id == pendingCardId;
              final enabled = canPick && !card.isPicked;
              return AnimatedOpacity(
                duration: BangMotion.resolve(context, BangMotion.fast),
                opacity: !card.isPicked || mine ? 1 : .34,
                child: AnimatedScale(
                  duration: BangMotion.resolve(context, BangMotion.standard),
                  curve: BangMotion.curve,
                  scale: mine || pending ? 1.06 : 1,
                  child: InkWell(
                    key: ValueKey('role_card_${card.id}'),
                    onTap: enabled ? () => onPick(card.id) : null,
                    borderRadius: BorderRadius.circular(5),
                    child: _CardBack(
                      width: cardWidth,
                      height: cardHeight,
                      label: '',
                      highlighted: mine || pending,
                    ),
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
    required this.playerId,
    required this.pendingCardId,
    required this.onPick,
  });

  final List<SetupChoice> cards;
  final String? playerId;
  final String? pendingCardId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = cards.length > 12 ? 8 : math.min(cards.length, 6);
      final cardWidth = (constraints.maxWidth / math.max(1, columns) - 6).clamp(
        32.0,
        52.0,
      );
      final cardHeight = cardWidth * 1.4;
      return Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 5,
          runSpacing: 5,
          children: cards.map((card) {
            final selected = playerId != null && card.pickedBy == playerId;
            final pending = card.id == pendingCardId;
            final enabled = !card.isPicked;
            return AnimatedOpacity(
              duration: BangMotion.resolve(context, BangMotion.fast),
              opacity: enabled || selected ? 1 : .32,
              child: AnimatedScale(
                duration: BangMotion.resolve(context, BangMotion.standard),
                curve: BangMotion.curve,
                scale: selected || pending ? 1.06 : 1,
                child: InkWell(
                  key: ValueKey('character_card_${card.id}'),
                  onTap: enabled ? () => onPick(card.id) : null,
                  borderRadius: BorderRadius.circular(5),
                  child: _CardBack(
                    width: cardWidth,
                    height: cardHeight,
                    label: '',
                    highlighted: selected || pending,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    },
  );
}

class _SetupPickConfirm extends StatelessWidget {
  const _SetupPickConfirm({
    required this.child,
    required this.title,
    required this.onCancel,
    required this.onConfirm,
  });

  final Widget child;
  final String title;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
    decoration: BoxDecoration(
      color: const Color(0xd9160c08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffffc451), width: 2),
      boxShadow: const [BoxShadow(color: Color(0xcc000000), blurRadius: 18)],
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xffffd272),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('HUY'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: onConfirm,
                  child: const Text('CHON'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
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
  'role_reveal' => 'Vai tro cua ban',
  'character_selection' => 'Chon nhan vat',
  'choosing_character' => 'Chon nhan vat',
  'turn_start' => 'San sang vao van',
  _ => 'Khoi tao tran dau',
};

List<String> _setupRoleDeck(int playerCount) {
  final base = switch (playerCount.clamp(4, 8)) {
    4 => ['sheriff', 'traitor', 'raider', 'raider'],
    5 => ['sheriff', 'deputy', 'raider', 'raider', 'traitor'],
    6 => ['sheriff', 'deputy', 'raider', 'raider', 'raider', 'traitor'],
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
      'raider',
      'raider',
      'raider',
      'traitor',
      'traitor',
    ],
  };
  return base.take(playerCount).toList();
}

String _roleCardAsset(String role) => switch (role) {
  'sheriff' => 'assets/images/role_cards/sheriff_card.png',
  'deputy' => 'assets/images/role_cards/deputy_card.png',
  'guardian' => 'assets/images/role_cards/guardian_card.png',
  'blank' => 'assets/images/bang_bang_logo.png',
  'outlaw' || 'raider' => 'assets/images/role_cards/raider_card.png',
  'renegade' || 'traitor' => 'assets/images/role_cards/traitor_card.png',
  _ => 'assets/images/role_cards/deputy_card.png',
};

String _characterAsset(String id) => switch (id) {
  'doctor_lee' => 'assets/images/doctor_lee.png',
  'iron_rose' => 'assets/images/iron_rose.png',
  'rose_doolan' || 'rose_oolan' => 'assets/images/characters/rose_oolan.png',
  'lucky_duke' => 'assets/images/characters/lucky_duke.png',
  'quick_jack' => 'assets/images/quick_jack.png',
  'black_jack' => 'assets/images/characters/black_jack.png',
  _ => 'assets/images/characters/$id.png',
};

String _roleLabel(String role) => switch (role) {
  'sheriff' => 'Cảnh sát trưởng',
  'deputy' => 'Phó cảnh sát',
  'guardian' => 'Hộ vệ',
  'blank' => 'Đang gán vai trò',
  'outlaw' || 'raider' => 'Cướp',
  'renegade' || 'traitor' => 'Gián điệp',
  _ => 'Vai trò',
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
