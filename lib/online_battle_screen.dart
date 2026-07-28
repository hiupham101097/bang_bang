import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_service.dart';
import 'card_effect_overlay.dart';
import 'data/online_room_repository.dart';
import 'domain/online_models.dart';

/// Minimal authoritative online table. Card effects stay in Cloud Functions;
/// this screen only asks the server to advance the currently visible phase.
class OnlineBattleScreen extends StatelessWidget {
  const OnlineBattleScreen({
    super.key,
    required this.repository,
    required this.room,
  });

  final OnlineRoomRepository repository;
  final OnlineRoom room;

  Future<void> _call(BuildContext context, String name) async {
    try {
      await repository.runGameAction(name, {
        'roomId': room.id,
        'actionId': '${name}_${DateTime.now().microsecondsSinceEpoch}',
      });
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _callPayload(
    BuildContext context,
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final cardId = payload['cardId'] as String? ?? '';
      if (cardId.startsWith('bang_')) {
        GameAudio.instance.playSfx('bang_shot');
      } else if (cardId.startsWith('dodge_')) {
        GameAudio.instance.playSfx('dodge');
      } else if (name == 'drawTurnCards' || name == 'drawCharacterTurnCards') {
        GameAudio.instance.playSfx('card_draw');
      } else if (name == 'acceptBangDamage') {
        GameAudio.instance.playSfx('damage');
      } else {
        GameAudio.instance.playSfx('card_play');
      }
      await repository.runGameAction(name, {'roomId': room.id, ...payload});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _playCard(
    BuildContext context,
    String cardId,
    String playerId,
  ) async {
    String? targetPlayerId;
    final needsTarget =
        cardId.startsWith('bang_') ||
        cardId.startsWith('jail_') ||
        cardId.startsWith('panico_') ||
        cardId.startsWith('cat_balou_') ||
        cardId.startsWith('duello_');
    if (needsTarget) {
      targetPlayerId = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('CHỌN MỤC TIÊU')),
              for (final member in room.members.where(
                (member) =>
                    member.id != playerId &&
                    member.isAlive &&
                    ((!cardId.startsWith('panico_') &&
                            !cardId.startsWith('cat_balou_')) ||
                        member.cardCount > 0 ||
                        member.equipment.isNotEmpty) &&
                    (!cardId.startsWith('panico_') ||
                        _distanceBetween(room, playerId, member.id) <= 1),
              ))
                ListTile(
                  leading: Icon(member.isBot ? Icons.smart_toy : Icons.person),
                  title: Text(member.displayName),
                  onTap: () => Navigator.pop(sheetContext, member.id),
                ),
            ],
          ),
        ),
      );
      if (targetPlayerId == null) return;
    }
    if (!context.mounted) return;
    String? equipmentCardId;
    if ((cardId.startsWith('panico_') || cardId.startsWith('cat_balou_')) &&
        targetPlayerId != null) {
      final target = room.memberFor(targetPlayerId);
      if (target != null && target.equipment.isNotEmpty) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('CHỌN LÁ BÀI')),
                if (target.cardCount > 0)
                  ListTile(
                    leading: Icon(Icons.style),
                    title: Text('LẤY NGẪU NHIÊN TRÊN TAY'),
                    onTap: () => Navigator.pop(sheetContext, '__hand__'),
                  ),
                for (final equipment in target.equipment)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(_cardLabel(equipment)),
                    onTap: () => Navigator.pop(sheetContext, equipment),
                  ),
              ],
            ),
          ),
        );
        if (choice == null) return;
        equipmentCardId = choice == '__hand__' ? null : choice;
      }
    }
    if (!context.mounted) return;
    final isEquipment = _isEquipmentCard(cardId);
    final actionLabel = isEquipment ? 'ĐẶT BÀI' : 'ĐÁNH';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(actionLabel),
        content: Text(
          targetPlayerId == null
              ? 'Dùng ${_cardLabel(cardId)}?'
              : 'Dùng ${_cardLabel(cardId)} vào ${room.memberFor(targetPlayerId)?.displayName ?? 'mục tiêu này'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final actionName =
        cardId.startsWith('jail_') ||
            cardId.startsWith('dilizenza_') ||
            cardId.startsWith('wells_fargo_') ||
            cardId.startsWith('saloon_') ||
            cardId.startsWith('barrel_') ||
            cardId.startsWith('mustang_') ||
            cardId.startsWith('appaloosa_') ||
            cardId.startsWith('volcanic_') ||
            cardId.startsWith('dynamite_')
        ? 'playSpecialCard'
        : cardId.startsWith('duello_')
        ? 'startDuel'
        : cardId.startsWith('panico_') || cardId.startsWith('cat_balou_')
        ? 'resolveTargetCard'
        : cardId.startsWith('general_store_')
        ? 'openGeneralStore'
        : cardId.startsWith('gatling_') || cardId.startsWith('indiani_')
        ? 'startMultiAttack'
        : 'playCard';
    await _callPayload(context, actionName, {
      'cardId': cardId,
      'targetPlayerId': targetPlayerId,
      'equipmentCardId': equipmentCardId,
      'actionId': 'play_${DateTime.now().microsecondsSinceEpoch}',
    });
  }

  Future<void> _chooseKitCarlson(
    BuildContext context,
    String actionId,
    List<String> choices,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('KIT CARLSON — CHỌN 2 LÁ')),
                Wrap(
                  spacing: 8,
                  children: choices
                      .map(
                        (cardId) => FilterChip(
                          label: Text(cardId.split('_').first.toUpperCase()),
                          selected: picks.contains(cardId),
                          onSelected: (checked) => setSheetState(() {
                            if (checked && picks.length < 2) picks.add(cardId);
                            if (!checked) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('LẤY 2 LÁ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'chooseKitCarlson', {
      'actionId': actionId,
      'cardIds': selected,
    });
  }

  Future<void> _drawTurn(
    BuildContext context,
    String playerId,
    String? characterId,
  ) async {
    var action = 'drawTurnCards';
    String? targetPlayerId;
    if (characterId == 'kit_carlson') {
      action = 'openKitCarlson';
    } else if (characterId == 'black_jack' || characterId == 'pedro_ramirez') {
      action = 'drawCharacterTurnCards';
    } else if (characterId == 'jesse_jones') {
      targetPlayerId = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.style),
                title: const Text('RÚT 2 LÁ TỪ BỘ BÀI'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              for (final member in room.members.where(
                (member) =>
                    member.id != playerId &&
                    member.isAlive &&
                    member.cardCount > 0,
              ))
                ListTile(
                  leading: const Icon(Icons.person_search),
                  title: Text('LẤY 1 LÁ TỪ ${member.displayName}'),
                  onTap: () => Navigator.pop(sheetContext, member.id),
                ),
            ],
          ),
        ),
      );
      if (targetPlayerId == null) return;
      action = 'drawJesseJones';
    }
    if (!context.mounted) return;
    await _callPayload(context, action, {
      'actionId': 'draw_${DateTime.now().microsecondsSinceEpoch}',
      if (targetPlayerId?.isNotEmpty == true) 'targetPlayerId': targetPlayerId,
    });
  }

  Future<void> _useSidKetchum(BuildContext context, List<String> hand) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('SID KETCHUM'),
                  subtitle: Text('Chọn 2 lá để hồi 1 máu.'),
                ),
                Wrap(
                  spacing: 8,
                  children: hand
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < 2) picks.add(cardId);
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('BỎ 2 LÁ VÀ HỒI MÁU'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'useSidKetchum', {'cardIds': selected});
  }

  Future<void> _discardExcessCards(
    BuildContext context,
    List<String> hand,
    int required,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('BỎ BÀI DƯ'),
                  subtitle: Text('Chọn đúng $required lá để bỏ.'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: hand
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < required) {
                              picks.add(cardId);
                            }
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == required
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('BỎ BÀI VÀ CHUYỂN LƯỢT'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'discardCards', {'cardIds': selected});
  }

  Future<void> _resolveSlabDodge(
    BuildContext context,
    String actionId,
    List<String> dodges,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        final picks = <String>{};
        return StatefulBuilder(
          builder: (_, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('SLAB THE KILLER'),
                  subtitle: Text('Cần dùng 2 lá Né để tránh phát Bang này.'),
                ),
                Wrap(
                  spacing: 8,
                  children: dodges
                      .map(
                        (cardId) => FilterChip(
                          label: Text(_cardLabel(cardId)),
                          selected: picks.contains(cardId),
                          onSelected: (selected) => setSheetState(() {
                            if (selected && picks.length < 2) picks.add(cardId);
                            if (!selected) picks.remove(cardId);
                          }),
                        ),
                      )
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: picks.length == 2
                        ? () => Navigator.pop(sheetContext, picks.toList())
                        : null,
                    child: const Text('DÙNG 2 LÁ NÉ'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;
    await _callPayload(context, 'resolveSlabDodge', {
      'pendingActionId': actionId,
      'cardIds': selected,
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayerProfile>(
    future: repository.ensureSignedIn(),
    builder: (context, profileSnapshot) {
      final playerId = profileSnapshot.data?.uid;
      final activePlayer = room.memberFor(room.currentTurnPlayerId ?? '');
      final isMyTurn = playerId != null && playerId == room.currentTurnPlayerId;
      final canPlay =
          isMyTurn &&
          room.phase == 'play_phase' &&
          room.cardsPlayedThisTurn == 0;
      final phase = room.phase;
      final needsJudgment = room.judgmentsResolvedForTurn != room.turnNumber;
      final canJudge = isMyTurn && phase == 'turn_start' && needsJudgment;
      final canDraw = isMyTurn && phase == 'turn_start' && !needsJudgment;
      return Scaffold(
        backgroundColor: const Color(0xff160c08),
        appBar: AppBar(title: const Text('BANG BANG — Bàn đấu')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  activePlayer == null
                      ? _phaseLabel(phase)
                      : isMyTurn
                      ? 'ĐẾN LƯỢT CỦA BẠN'
                      : 'ĐANG CHỜ ${activePlayer.displayName.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Color(0xffffc451),
                  ),
                ),
                const SizedBox(height: 4),
                _TurnCountdown(
                  deadline: room.turnDeadlineAt,
                  isMyTurn: isMyTurn,
                  onExpired: () => _call(context, 'resolveTurnTimeout'),
                ),
                if (isMyTurn && room.phase == 'play_phase')
                  Text(
                    room.cardsPlayedThisTurn == 0
                        ? 'Bạn còn 1 lá để dùng trong lượt này.'
                        : 'Bạn đã dùng lá duy nhất của lượt này.',
                    style: const TextStyle(color: Color(0xffffd272)),
                  ),
                const SizedBox(height: 10),
                _TurnSteps(phase: phase),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: room.members
                      .map(
                        (member) => Chip(
                          backgroundColor: member.id == room.currentTurnPlayerId
                              ? const Color(0xff6f4214)
                              : null,
                          side: BorderSide(
                            color: member.id == room.currentTurnPlayerId
                                ? const Color(0xffffc451)
                                : Colors.transparent,
                            width: 2,
                          ),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${member.displayName}  ${member.isAlive ? '${member.health}/${member.maxHealth} máu · ${member.cardCount} bài' : 'ĐÃ LOẠI'}',
                              ),
                              if (member.equipment.isNotEmpty)
                                Text(
                                  member.equipment.map(_cardLabel).join(' · '),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xffffd272),
                                  ),
                                ),
                            ],
                          ),
                          avatar: Icon(
                            member.isBot ? Icons.smart_toy : Icons.person,
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (room.discardTopCardId != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: 230,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                          'LÁ VỪA ĐÁNH',
                          style: TextStyle(
                            color: Color(0xff4d2410),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _cardLabel(room.discardTopCardId!),
                          style: const TextStyle(
                            color: Color(0xff2b160b),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (room.publicLog.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: room.publicLog.reversed
                          .take(2)
                          .map(
                            (entry) => Text(
                              _publicLogLabel(room, entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'BÀI TRÊN TAY',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<String>>(
                  stream: repository.watchHand(room.id),
                  builder: (context, snapshot) {
                    final cards = snapshot.data ?? const <String>[];
                    final discardRequired =
                        (activePlayer == null
                                ? 0
                                : cards.length - activePlayer.health)
                            .clamp(0, cards.length)
                            .toInt();
                    if (cards.isEmpty) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Chưa có bài hoặc đang chờ đồng bộ.'),
                      );
                    }
                    return SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: cards.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => OutlinedButton(
                          onPressed: canPlay
                              ? () => _playCard(context, cards[index], playerId)
                              : isMyTurn &&
                                    phase == 'discard_phase' &&
                                    discardRequired > 0
                              ? () => _discardExcessCards(
                                  context,
                                  cards,
                                  discardRequired,
                                )
                              : null,
                          child: Text(
                            '${phase == 'discard_phase'
                                ? 'BỎ'
                                : _isEquipmentCard(cards[index])
                                ? 'ĐẶT'
                                : 'ĐÁNH'} ${_cardLabel(cards[index])}',
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (isMyTurn &&
                    activePlayer?.characterId == 'sid_ketchum' &&
                    activePlayer!.health < activePlayer.maxHealth)
                  StreamBuilder<List<String>>(
                    stream: repository.watchHand(room.id),
                    builder: (context, snapshot) {
                      final hand = snapshot.data ?? const <String>[];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: hand.length >= 2
                              ? () => _useSidKetchum(context, hand)
                              : null,
                          icon: const Icon(Icons.favorite_outline),
                          label: const Text('SID KETCHUM: BỎ 2 HỒI 1'),
                        ),
                      );
                    },
                  ),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: repository.watchPendingActions(room.id),
                  builder: (context, snapshot) {
                    final action = (snapshot.data ?? const []).firstOrNull;
                    if (action == null) return const SizedBox.shrink();
                    final opened = List<String>.from(
                      action['openedCardIds'] as List? ?? const [],
                    );
                    final judgmentChoices = List<String>.from(
                      action['choices'] as List? ?? const [],
                    );
                    final responsePlayerId =
                        action['currentTargetId'] as String? ??
                        action['targetPlayerId'] as String?;
                    final isMyResponse =
                        playerId != null && responsePlayerId == playerId;
                    final isMyActor =
                        playerId != null && action['actorPlayerId'] == playerId;
                    final isMyGeneralStorePicker =
                        playerId != null &&
                        action['currentPickerId'] == playerId;
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: action['actionType'] == 'bang'
                                ? _ResponseCountdown(
                                    deadline: action['responseDeadlineAt'],
                                    onExpired: () => _callPayload(
                                      context,
                                      'resolveExpiredResponse',
                                      {'pendingActionId': action['id']},
                                    ),
                                  )
                                : null,
                            title: Text(
                              'Đang chờ: ${action['actionType'] ?? 'phản ứng'}',
                            ),
                            subtitle: Text(_actionSummary(room, action)),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                if (action['actionType'] == 'bang')
                                  FilledButton.tonal(
                                    onPressed: isMyResponse
                                        ? () => _callPayload(
                                            context,
                                            'acceptBangDamage',
                                            {'pendingActionId': action['id']},
                                          )
                                        : null,
                                    child: const Text('NHẬN ĐẠN'),
                                  ),
                                if (isMyResponse)
                                  OutlinedButton(
                                    onPressed: () => _callPayload(
                                      context,
                                      'resolveExpiredResponse',
                                      {'pendingActionId': action['id']},
                                    ),
                                    child: const Text('CHẤP NHẬN'),
                                  ),
                              ],
                            ),
                          ),
                          if (action['actionType'] == 'general_store' &&
                              opened.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Wrap(
                                spacing: 8,
                                children: opened
                                    .map(
                                      (cardId) => OutlinedButton(
                                        onPressed: isMyGeneralStorePicker
                                            ? () => _callPayload(
                                                context,
                                                'chooseGeneralStoreCard',
                                                {
                                                  'actionId': action['id'],
                                                  'cardId': cardId,
                                                },
                                              )
                                            : null,
                                        child: Text(
                                          cardId.split('_').first.toUpperCase(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (action['actionType'] == 'lucky_duke_judgment' &&
                              judgmentChoices.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Wrap(
                                spacing: 8,
                                children: judgmentChoices
                                    .map(
                                      (cardId) => FilledButton.tonal(
                                        onPressed: isMyActor
                                            ? () => _callPayload(
                                                context,
                                                'chooseLuckyDukeJudgment',
                                                {
                                                  'actionId': action['id'],
                                                  'resultCardId': cardId,
                                                },
                                              )
                                            : null,
                                        child: Text(
                                          cardId.split('_').first.toUpperCase(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (action['actionType'] == 'kit_carlson' &&
                              judgmentChoices.length == 3)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: FilledButton.tonal(
                                onPressed: isMyActor
                                    ? () => _chooseKitCarlson(
                                        context,
                                        action['id'] as String,
                                        judgmentChoices,
                                      )
                                    : null,
                                child: const Text('KIT CARLSON: CHỌN 2 LÁ'),
                              ),
                            ),
                          if (isMyResponse &&
                              (action['actionType'] == 'duello' ||
                                  action['actionType'] == 'gatling' ||
                                  action['actionType'] == 'indiani'))
                            StreamBuilder<List<String>>(
                              stream: repository.watchHand(room.id),
                              builder: (context, handSnapshot) {
                                final requiredType =
                                    action['actionType'] == 'gatling'
                                    ? 'dodge_'
                                    : 'bang_';
                                final usable =
                                    (handSnapshot.data ?? const <String>[])
                                        .where(
                                          (card) =>
                                              card.startsWith(requiredType),
                                        )
                                        .toList();
                                final functionName =
                                    action['actionType'] == 'duello'
                                    ? 'respondDuel'
                                    : 'respondMultiAttack';
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    12,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    children: usable
                                        .map(
                                          (cardId) => FilledButton.tonal(
                                            onPressed: () => _callPayload(
                                              context,
                                              functionName,
                                              {
                                                'actionId': action['id'],
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: Text(
                                              'DÙNG ${cardId.split('_').first.toUpperCase()}',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                );
                              },
                            ),
                          if (action['actionType'] == 'bang' && isMyResponse)
                            const Center(child: BangEffectOverlay(size: 130)),
                          if (action['actionType'] == 'gatling' ||
                              action['actionType'] == 'indiani')
                            const Center(
                              child: AreaAttackEffectOverlay(size: 150),
                            ),
                          if (action['actionType'] == 'bang' && isMyResponse)
                            StreamBuilder<List<String>>(
                              stream: repository.watchHand(room.id),
                              builder: (context, handSnapshot) {
                                final hand =
                                    handSnapshot.data ?? const <String>[];
                                final dodges = hand
                                    .where((card) => card.startsWith('dodge_'))
                                    .toList();
                                final requiresTwoDodges =
                                    (action['requiredDodges'] as num? ?? 1) ==
                                    2;
                                final bangs = hand
                                    .where((card) => card.startsWith('bang_'))
                                    .toList();
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    12,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (requiresTwoDodges)
                                        FilledButton.tonal(
                                          onPressed: dodges.length >= 2
                                              ? () => _resolveSlabDodge(
                                                  context,
                                                  action['id'] as String,
                                                  dodges,
                                                )
                                              : null,
                                          child: const Text('DÙNG 2 LÁ NÉ'),
                                        )
                                      else
                                        ...dodges.map(
                                          (cardId) => FilledButton.tonal(
                                            onPressed: () => _callPayload(
                                              context,
                                              'respondToAction',
                                              {
                                                'pendingActionId': action['id'],
                                                'responseType': 'missed',
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: const Text('NÉ'),
                                          ),
                                        ),
                                      if (!requiresTwoDodges)
                                        ...bangs.map(
                                          (cardId) => OutlinedButton(
                                            onPressed: () => _callPayload(
                                              context,
                                              'useCalamityJanetDodge',
                                              {
                                                'pendingActionId': action['id'],
                                                'cardId': cardId,
                                              },
                                            ),
                                            child: const Text('BANG → NÉ'),
                                          ),
                                        ),
                                      if (!requiresTwoDodges)
                                        OutlinedButton(
                                          onPressed: () => _callPayload(
                                            context,
                                            'resolveJourdonnais',
                                            {'pendingActionId': action['id']},
                                          ),
                                          child: const Text('PHÁN XÉT NÉ'),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (canDraw)
                  FilledButton(
                    onPressed: () => _call(context, 'resolveTurnJudgments'),
                    child: const Text('PHÁN XÉT ĐẦU LƯỢT'),
                  ),
                if (canJudge)
                  FilledButton(
                    onPressed: () =>
                        _drawTurn(context, playerId, activePlayer?.characterId),
                    child: const Text('RÚT 2 LÁ'),
                  ),
                if (canPlay)
                  FilledButton.tonal(
                    onPressed: () => _call(context, 'requestEndTurn'),
                    child: const Text('KẾT THÚC LƯỢT'),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _phaseLabel(String phase) => switch (phase) {
  'turn_start' => 'BẮT ĐẦU LƯỢT · RÚT 2 LÁ',
  'play_phase' => 'ĐÁNH BÀI HOẶC KẾT THÚC LƯỢT',
  'discard_phase' => 'BỎ BÀI DƯ',
  'waiting_response' => 'ĐANG CHỜ PHẢN ỨNG',
  'waiting_multi_response' => 'ĐANG CHỜ MỌI NGƯỜI PHẢN ỨNG',
  'waiting_duel_response' => 'ĐANG ĐẤU SÚNG',
  _ => 'ĐANG XỬ LÝ: ${phase.toUpperCase()}',
};

String _cardLabel(String cardId) => cardId
    .split('_')
    .takeWhile((part) => part != 'ace' && part != 'two' && part != 'three')
    .join(' ')
    .replaceAll('DILIZENZA', 'DILIGENZA')
    .toUpperCase();

bool _isEquipmentCard(String cardId) => [
  'gun_range_',
  'volcanic_',
  'mustang_',
  'appaloosa_',
  'barrel_',
  'dynamite_',
  'jail_',
].any(cardId.startsWith);

String _actionSummary(OnlineRoom room, Map<String, dynamic> action) {
  final actor = room.memberFor(action['actorPlayerId'] as String? ?? '');
  final target = room.memberFor(
    action['currentTargetId'] as String? ??
        action['targetPlayerId'] as String? ??
        '',
  );
  final actorName = actor?.displayName ?? 'Một người chơi';
  final targetName = target?.displayName;
  return targetName == null
      ? '$actorName đang xử lý hành động.'
      : '$actorName nhắm tới $targetName.';
}

String _publicLogLabel(OnlineRoom room, String entry) {
  final parts = entry.split(':');
  final actor = room.memberFor(parts.length > 1 ? parts[1] : '');
  final actorName = actor?.displayName ?? 'Một người chơi';

  if (parts.first == 'draw') {
    return '$actorName đã rút bài.';
  }
  if (parts.first == 'bot') {
    return '$actorName đã hoàn tất lượt.';
  }

  final card = parts.length > 2 ? _cardLabel(parts[2]) : 'một lá bài';
  if (parts.first == 'equip') {
    return '$actorName đã đặt $card.';
  }

  final target = room.memberFor(parts.length > 3 ? parts[3] : '');
  return target == null
      ? '$actorName đã dùng $card.'
      : '$actorName dùng $card vào ${target.displayName}.';
}

int _distanceBetween(OnlineRoom room, String actorId, String targetId) {
  final alive = room.members.where((member) => member.isAlive).toList()
    ..sort((a, b) => a.seat.compareTo(b.seat));
  final actorIndex = alive.indexWhere((member) => member.id == actorId);
  final targetIndex = alive.indexWhere((member) => member.id == targetId);
  if (actorIndex < 0 || targetIndex < 0 || alive.length < 2) return 999;

  final actor = alive[actorIndex];
  final target = alive[targetIndex];
  final base = (targetIndex - actorIndex).abs();
  final baseDistance = base < alive.length - base ? base : alive.length - base;
  final actorHasAppaloosa = actor.equipment.any(
    (cardId) => cardId.startsWith('appaloosa_'),
  );
  final targetHasMustang = target.equipment.any(
    (cardId) => cardId.startsWith('mustang_'),
  );
  return (baseDistance +
          (actor.characterId == 'rose_doolan' ? -1 : 0) +
          (target.characterId == 'paul_regret' ? 1 : 0) +
          (actorHasAppaloosa ? -1 : 0) +
          (targetHasMustang ? 1 : 0))
      .clamp(1, 99)
      .toInt();
}

class _TurnCountdown extends StatefulWidget {
  const _TurnCountdown({
    required this.deadline,
    required this.isMyTurn,
    required this.onExpired,
  });

  final DateTime? deadline;
  final bool isMyTurn;
  final VoidCallback onExpired;

  @override
  State<_TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnSteps extends StatelessWidget {
  const _TurnSteps({required this.phase});

  final String phase;

  @override
  Widget build(BuildContext context) {
    final step = phase == 'turn_start'
        ? 0
        : phase == 'play_phase'
        ? 1
        : 2;
    const labels = ['1. RÚT BÀI', '2. ĐÁNH 1 LÁ', '3. KẾT THÚC'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Container(width: 20, height: 1, color: const Color(0xff8b6339)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: index == step
                  ? const Color(0xffffc451)
                  : const Color(0xff392016),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              labels[index],
              style: TextStyle(
                color: index == step ? const Color(0xff2b160b) : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TurnCountdownState extends State<_TurnCountdown> {
  late final Timer _timer;
  bool _expiredSent = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _TurnCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) _expiredSent = false;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.deadline
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 60);
    final color = seconds == null || seconds > 20
        ? Colors.white
        : seconds > 10
        ? const Color(0xffffc451)
        : Colors.redAccent;
    final text = seconds == null
        ? 'Đang đồng bộ lượt...'
        : 'Còn $seconds giây${widget.isMyTurn ? ' · Hành động của bạn' : ''}';
    if (seconds == 0 && !_expiredSent) {
      _expiredSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpired());
    }
    return Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}

class _ResponseCountdown extends StatefulWidget {
  const _ResponseCountdown({required this.deadline, required this.onExpired});
  final dynamic deadline;
  final VoidCallback onExpired;

  @override
  State<_ResponseCountdown> createState() => _ResponseCountdownState();
}

class _ResponseCountdownState extends State<_ResponseCountdown> {
  late final Timer _timer;
  int _seconds = 0;
  bool _expiredSent = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _ResponseCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      _expiredSent = false;
      _tick();
    }
  }

  void _tick() {
    final value = widget.deadline;
    final date = value == null ? null : value.toDate() as DateTime;
    final seconds = date == null
        ? 0
        : (date.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
            0,
            10,
          );
    if (mounted) setState(() => _seconds = seconds);
    if (seconds == 0 && !_expiredSent) {
      _expiredSent = true;
      widget.onExpired();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('Phản ứng: $_seconds giây');
}
